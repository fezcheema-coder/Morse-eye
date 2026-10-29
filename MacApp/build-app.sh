#!/bin/bash
# Builds "Morse Eye.app" and installs it into /Applications.
#   ./build-app.sh               build, install and open
#   ./build-app.sh --no-install  just build into ./build
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Apple's free developer tools are needed to build the app."
  echo "A window will open: click Install, wait for it to finish, then run this again."
  xcode-select --install || true
  exit 1
fi

echo "==> Compiling (the first build takes a minute or two)…"
# UNIVERSAL=1 builds for both Apple Silicon and Intel (needs full Xcode, used by CI)
ARCH_FLAGS=()
[ "${UNIVERSAL:-}" = "1" ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="build/Morse Eye.app"
echo "==> Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MorseEye" "$APP/Contents/MacOS/MorseEye"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> Drawing icon"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
if swift scripts/make-icon.swift build/icon-1024.png 2>/dev/null; then
  for size in 16 32 128 256 512; do
    sips -z $size $size build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "    (skipped icon)"
fi

echo "==> Signing (ad-hoc, for this Mac)"
codesign --force --sign - --identifier app.morseeye.MorseEye "$APP"

if [ "${1:-}" = "--no-install" ]; then
  echo "Built: $(pwd)/$APP"
  exit 0
fi

echo "==> Installing to /Applications"
osascript -e 'tell application id "app.morseeye.MorseEye" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/Morse Eye.app"
cp -R "$APP" /Applications/
open "/Applications/Morse Eye.app"
echo
echo "Done! Look for the Morse Eye icon in your menu bar (top right of the screen)."
