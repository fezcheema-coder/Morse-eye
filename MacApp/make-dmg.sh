#!/bin/bash
# Packages build/Morse Eye.app into build/MorseEye.dmg with a drag-to-Applications layout.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Morse Eye.app"
[ -d "$APP" ] || { echo "Build the app first: ./build-app.sh --no-install"; exit 1; }

STAGE="build/dmg"
rm -rf "$STAGE" build/MorseEye.dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/If macOS says the app is damaged.txt" <<'TXT'
Morse Eye isn't registered with Apple, so macOS may say it "is damaged" or
"can't be opened" the first time.

After dragging Morse Eye into Applications, open Terminal and paste:

    xattr -dr com.apple.quarantine "/Applications/Morse Eye.app"

Then open Morse Eye again. You only need to do this once per version.
TXT

hdiutil create -volname "Morse Eye" -srcfolder "$STAGE" -ov -format UDZO build/MorseEye.dmg
echo "Created $(pwd)/build/MorseEye.dmg"
