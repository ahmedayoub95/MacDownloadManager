#!/bin/bash
# Packs the .dmg and the browser extension into dist/MacDownloadManager-<version>.zip,
# so one download has everything. Run scripts/make-dmg.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
DIST="$ROOT/dist"
NAME="MacDownloadManager-$VERSION"
DMG="$DIST/$NAME.dmg"
ZIP="$DIST/$NAME.zip"

[ -f "$DMG" ] || { echo "Make the .dmg first: scripts/make-dmg.sh" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/$NAME"
cp "$DMG" "$STAGE/$NAME/"
cp -R "$ROOT/extension" "$STAGE/$NAME/Browser Extension"

cat > "$STAGE/$NAME/How to install.txt" <<EOF
Mac Download Manager $VERSION

1. Open $NAME.dmg and drag Mac Download Manager onto Applications.

2. Open the app. The first time, macOS blocks it because it isn't notarized by Apple:
   click Done, then go to System Settings > Privacy & Security and click Open Anyway.

3. Follow the setup window. It installs the download tools and connects the app to your browsers.

4. Add the browser extension. This is required: without it, the browser keeps downloading
   files itself and the "Download this video" button isn't there.
   a. In Chrome, Brave, Edge or Vivaldi, open chrome://extensions
   b. Turn on Developer mode (top right).
   c. Click "Load unpacked" and choose the "Browser Extension" folder.

   Keep that folder: the browser loads the extension from it, so moving or deleting it
   removes the extension. The setup window can also give you a copy that lives inside
   the app's own folder, so you can delete this download afterwards.

More help: https://github.com/ahmedayoub95/MacDownloadManager#installation
EOF

rm -f "$ZIP"
(cd "$STAGE" && ditto -c -k --norsrc --noextattr --keepParent "$NAME" "$ZIP")
echo "Created $ZIP"
