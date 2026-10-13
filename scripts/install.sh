#!/bin/bash
# Builds Mac Download Manager.app from source, installs it in ~/Applications and opens it.
# On launch the app connects itself to your browsers and offers to install any missing tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Download Manager"
INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"

"$ROOT/scripts/build-app.sh"

# Stop the running app (downloads keep going in their own processes).
pkill -x MacDownloadManager 2>/dev/null && sleep 1 || true

mkdir -p "$INSTALL_DIR"
rm -rf "$APP"
cp -R "$ROOT/dist/$APP_NAME.app" "$APP"
touch "$APP" # make Finder and the Dock pick up a changed icon
echo "Installed $APP"

open "$APP"
