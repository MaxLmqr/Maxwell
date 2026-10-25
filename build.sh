#!/bin/zsh
# Compile l'app et l'emballe en MaxActivity.app.
# Usage : ./build.sh            → build/MaxActivity.app
#         ./build.sh --install  → copie aussi dans /Applications et la lance
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/MaxActivity.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MaxActivity "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "✅ $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MaxActivity || true
  rm -rf /Applications/MaxActivity.app
  cp -R "$APP" /Applications/
  open /Applications/MaxActivity.app
  echo "✅ Installée dans /Applications et lancée"
fi
