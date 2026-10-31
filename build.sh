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
# Signature ad hoc : le framework d'abord, puis l'app qui le contient.
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
echo "✅ $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Maxwell || true
  rm -rf /Applications/Maxwell.app
  cp -R "$APP" /Applications/
  open /Applications/Maxwell.app
  echo "✅ Installée dans /Applications et lancée"
fi
