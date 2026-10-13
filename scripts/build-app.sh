#!/bin/bash
# Builds "Mac Download Manager.app" into dist/.
#   VERSION=1.2.3   version written into the app (default: contents of the VERSION file)
#   UNIVERSAL=1     build for both Apple Silicon and Intel (needs Xcode, not just the Command Line Tools)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Download Manager"
BUNDLE_ID="com.ahmed.MacDownloadManager"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

BUILD_FLAGS=(-c release --package-path "$ROOT/app")
if [ "${UNIVERSAL:-0}" = "1" ]; then
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "Building $APP_NAME ${VERSION}…"
swift build "${BUILD_FLAGS[@]}"
BIN="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MacDownloadManager" "$APP/Contents/MacOS/MacDownloadManager"
cp "$BIN/mdm-native-host" "$APP/Contents/MacOS/mdm-native-host"

# The browser extension ships inside the app; the app copies it somewhere Chrome can load it from.
cp -R "$ROOT/extension" "$APP/Contents/Resources/extension"

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
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  ICON_PLIST="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<EOF
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

# Ad-hoc signature: required to run on Apple Silicon. Not notarized (that needs a paid Apple account).
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
