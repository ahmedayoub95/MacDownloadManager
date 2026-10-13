#!/bin/bash
# Packs dist/Mac Download Manager.app into dist/MacDownloadManager-<version>.dmg,
# with an Applications shortcut to drag the app onto. Run scripts/build-app.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Download Manager"
VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
DIST="$ROOT/dist"
DMG="$DIST/MacDownloadManager-$VERSION.dmg"

[ -d "$DIST/$APP_NAME.app" ] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$DIST/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Created $DMG"
