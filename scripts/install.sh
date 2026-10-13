#!/bin/bash
# Builds Mac Download Manager.app, installs it in ~/Applications and registers its browser helper
# with every Chromium browser installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Download Manager"
BUNDLE_ID="com.ahmed.MacDownloadManager"
HOST_NAME="com.ahmed.downloadmanager"
EXTENSION_ID="pgfkdonjalnlcemopglppogdghdghigg"
VERSION="0.4.0"

INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"
HOST_BINARY="$APP/Contents/MacOS/mdm-native-host"

for tool in yt-dlp ffmpeg aria2c; do
  if [ ! -x "/opt/homebrew/bin/$tool" ] && [ ! -x "/usr/local/bin/$tool" ]; then
    echo "Missing $tool. Install the download tools with: brew install yt-dlp ffmpeg aria2" >&2
    exit 1
  fi
done

echo "Building…"
swift build -c release --package-path "$ROOT/app"
BIN="$(swift build -c release --package-path "$ROOT/app" --show-bin-path)"

STAGE="$ROOT/app/.build/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS"
cp "$BIN/MacDownloadManager" "$STAGE/Contents/MacOS/MacDownloadManager"
cp "$BIN/mdm-native-host" "$STAGE/Contents/MacOS/mdm-native-host"

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
</dict>
</plist>
EOF

codesign --force --deep --sign - "$STAGE" >/dev/null

# Stop the running app (downloads keep going in their own processes).
pkill -x MacDownloadManager 2>/dev/null && sleep 1 || true

mkdir -p "$INSTALL_DIR"
rm -rf "$APP"
cp -R "$STAGE" "$APP"
echo "Installed $APP"

SUPPORT="$HOME/Library/Application Support"
for browser in "Google/Chrome" "Google/Chrome Beta" "Google/Chrome Canary" "Chromium" \
               "BraveSoftware/Brave-Browser" "Microsoft Edge" "Vivaldi"; do
  [ -d "$SUPPORT/$browser" ] || continue
  dir="$SUPPORT/$browser/NativeMessagingHosts"
  mkdir -p "$dir"
  cat > "$dir/$HOST_NAME.json" <<EOF
{
  "name": "$HOST_NAME",
  "description": "$APP_NAME",
  "path": "$HOST_BINARY",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXTENSION_ID/"]
}
EOF
  echo "Registered browser helper for $browser"
done

open "$APP"
