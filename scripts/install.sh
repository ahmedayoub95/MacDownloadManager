#!/bin/bash
# Builds Mac Download Manager.app from source, installs it in ~/Applications and opens it.
# On launch the app connects itself to your browsers and offers to install any missing tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Download Manager"
BUNDLE_ID="com.ahmed.MacDownloadManager"
VERSION="0.5.0"

INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"

echo "Building…"
swift build -c release --package-path "$ROOT/app"
BIN="$(swift build -c release --package-path "$ROOT/app" --show-bin-path)"

STAGE="$ROOT/app/.build/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN/MacDownloadManager" "$STAGE/Contents/MacOS/MacDownloadManager"
cp "$BIN/mdm-native-host" "$STAGE/Contents/MacOS/mdm-native-host"

# The browser extension ships inside the app; the app copies it somewhere Chrome can load it from.
cp -R "$ROOT/extension" "$STAGE/Contents/Resources/extension"

# App icon: a square PNG (ideally 1024×1024) converted into the .icns format macOS uses.
ICON_SOURCE="$ROOT/app/Resources/AppIcon.png"
ICON_PLIST=""
if [ -f "$ICON_SOURCE" ]; then
  ICONSET="$ROOT/app/.build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$STAGE/Contents/Resources/AppIcon.icns"
  ICON_PLIST="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$STAGE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>MacDownloadManager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  $ICON_PLIST
</dict>
</plist>
EOF

codesign --force --deep --sign - "$STAGE" >/dev/null

# Stop the running app (downloads keep going in their own processes).
pkill -x MacDownloadManager 2>/dev/null && sleep 1 || true

mkdir -p "$INSTALL_DIR"
rm -rf "$APP"
cp -R "$STAGE" "$APP"
touch "$APP" # make Finder and the Dock pick up a changed icon
echo "Installed $APP"

open "$APP"
