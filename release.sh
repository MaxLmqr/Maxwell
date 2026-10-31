#!/bin/zsh
# Publie une nouvelle version de Maxwell pour les amis.
# Usage : ./release.sh 0.2.0 "Ce qui change dans cette version"
#
# Augmente la version dans Info.plist, compile, zippe l'app, la signe pour Sparkle,
# écrit l'appcast, puis commit, tag et crée la release GitHub avec le zip et l'appcast.
# Les apps installées trouvent l'appcast à l'adresse SUFeedURL d'Info.plist.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?Usage : ./release.sh <version> [notes]}
NOTES=${2:-"Maxwell $VERSION"}
PLIST=Resources/Info.plist
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin

if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌ Des modifications ne sont pas commitées." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "❌ La version $VERSION existe déjà." >&2
  exit 1
fi

# Lit la valeur qui suit une clé d'Info.plist.
plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" $PLIST; }
# Remplace la valeur qui suit une clé. sed plutôt que PlistBuddy, qui réécrirait le fichier sans ses commentaires.
set_plist_value() { sed -i '' "/<key>$1<\/key>/{n;s|<string>.*</string>|<string>$2</string>|;}" $PLIST; }

# CFBundleVersion est le numéro que Sparkle compare : il augmente de 1 à chaque release.
BUILD=$(( $(plist_value CFBundleVersion) + 1 ))
set_plist_value CFBundleShortVersionString "$VERSION"
set_plist_value CFBundleVersion "$BUILD"
MIN_OS=$(plist_value LSMinimumSystemVersion)

./build.sh

ZIP=build/Maxwell-$VERSION.zip
ditto -c -k --keepParent build/Maxwell.app "$ZIP"
# Renvoie « sparkle:edSignature="…" length="…" », signé avec la clé du Trousseau.
SIGNATURE=$($SPARKLE_BIN/sign_update --account Maxwell "$ZIP")

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Maxwell</title>
    <item>
      <title>Maxwell $VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$NOTES</p>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Maxwell-$VERSION.zip"
                 type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF

git commit -qm "Version $VERSION" $PLIST
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" "$ZIP" build/appcast.xml --title "Maxwell $VERSION" --notes "$NOTES"
echo "✅ Maxwell $VERSION publiée : https://github.com/$REPO/releases/tag/v$VERSION"
