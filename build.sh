#!/bin/zsh
# Compile l'app et l'emballe en Maxwell.app.
# Usage : ./build.sh            → build/Maxwell.app
#         ./build.sh --install  → copie aussi dans /Applications et la lance
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Maxwell.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/Maxwell "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# ditto garde les liens symboliques du framework.
ditto .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

# Signé avec le certificat auto-signé de Max, la signature reste la même d'une version à l'autre :
# macOS garde les autorisations données à Maxwell, comme celle de lire l'onglet actif de Chrome.
# Sans ce certificat dans le Trousseau, la signature est ad hoc et ces autorisations sont redemandées.
IDENTITY="Maxwell Self-Signed"
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "⚠️  Certificat « $IDENTITY » absent du Trousseau : signature ad hoc."
  IDENTITY=-
fi
# Le framework d'abord, puis l'app qui le contient.
codesign --force --deep --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" "$APP"
echo "✅ $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Maxwell || true
  # L'ouvrir pendant que l'ancienne se ferme encore échoue (erreur -600).
  while pgrep -x Maxwell >/dev/null; do sleep 0.2; done
  rm -rf /Applications/Maxwell.app
  cp -R "$APP" /Applications/
  open /Applications/Maxwell.app
  echo "✅ Installée dans /Applications et lancée"
fi
