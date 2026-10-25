#!/bin/zsh
# Compile l'app et l'emballe en Maxwell.app.
# Usage : ./build.sh            → build/Maxwell.app
#         ./build.sh --install  → copie aussi dans /Applications et la lance
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Maxwell.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Maxwell "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "✅ $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Maxwell || true
  rm -rf /Applications/Maxwell.app
  cp -R "$APP" /Applications/
  open /Applications/Maxwell.app
  echo "✅ Installée dans /Applications et lancée"
fi
