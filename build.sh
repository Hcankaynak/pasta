#!/bin/bash
# 🍝 Builds Pasta.app
#   ./build.sh           → builds build/Pasta.app
#   ./build.sh install   → builds, copies to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Pasta.app"
ARCH="$(uname -m)"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "❌ Swift compiler not found."
  echo "   Install Apple's Command Line Tools first:  xcode-select --install"
  exit 1
fi

echo "🍝 Boiling the water..."
rm -rf "$APP" build/Pasta.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "🍝 Cooking the code ($ARCH)..."
swiftc -O \
  -target "$ARCH-apple-macos13.0" \
  -module-name Pasta \
  -o "$APP/Contents/MacOS/Pasta" \
  Sources/*.swift

echo "🎨 Plating the icon..."
ICONS=AppStore/Assets.xcassets/AppIcon.appiconset
if [ -d "$ICONS" ]; then
  mkdir -p build/Pasta.iconset
  cp "$ICONS"/icon_*.png build/Pasta.iconset/
  iconutil -c icns build/Pasta.iconset -o "$APP/Contents/Resources/Pasta.icns" 2>/dev/null \
    || echo "   (icon skipped — app still works)"
else
  echo "   (icon skipped — app still works)"
fi

# Ad-hoc signature so macOS is happy running it locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

if [[ "${1:-}" == "install" ]]; then
  pkill -x Pasta 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Pasta.app
  cp -R "$APP" /Applications/
  open /Applications/Pasta.app
  echo "✅ Installed to /Applications. Look for 🍝 in your menu bar! (⇧⌘V opens it)"
else
  echo "✅ Built $APP"
  echo "   Run it:      open $APP"
  echo "   Install it:  ./build.sh install"
fi
