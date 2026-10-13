#!/bin/bash
# Prints the Homebrew cask for a release: scripts/make-cask.sh <version> <sha256 of the .dmg>
set -euo pipefail

VERSION="$1"
SHA256="$2"

cat <<EOF
cask "mac-download-manager" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/ahmedayoub95/MacDownloadManager/releases/download/v#{version}/MacDownloadManager-#{version}.dmg"
  name "Mac Download Manager"
  desc "Multi-connection download manager with a browser extension for videos"
  homepage "https://github.com/ahmedayoub95/MacDownloadManager"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Mac Download Manager.app"

  # The app isn't notarized (that needs a paid Apple account). Installing it with brew is the
  # user's choice to trust it, so skip the "Open Anyway" step.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Mac Download Manager.app"]
  end

  uninstall quit: "com.ahmed.MacDownloadManager"

  zap trash: [
    "~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.ahmed.downloadmanager.json",
    "~/Library/Application Support/Chromium/NativeMessagingHosts/com.ahmed.downloadmanager.json",
    "~/Library/Application Support/Google/Chrome Beta/NativeMessagingHosts/com.ahmed.downloadmanager.json",
    "~/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts/com.ahmed.downloadmanager.json",
    "~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.ahmed.downloadmanager.json",
    "~/Library/Application Support/MacDownloadManager",
    "~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.ahmed.downloadmanager.json",
    "~/Library/Application Support/Vivaldi/NativeMessagingHosts/com.ahmed.downloadmanager.json",
    "~/Library/Caches/MacDownloadManager",
    "~/Library/Logs/MacDownloadManager",
    "~/Library/Preferences/com.ahmed.MacDownloadManager.plist",
    "~/Library/Preferences/com.ahmed.MacDownloadManager.shared.plist",
  ]

  caveats <<~EOS
    Open Mac Download Manager once; its setup window installs the download tools
    and walks you through adding the browser extension.
  EOS
end
EOF
