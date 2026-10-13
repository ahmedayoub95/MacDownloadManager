cask "mac-download-manager" do
  version "0.5.0"
  sha256 "e893eb22987d41a9bb28ebec75221f37fa325dd4d64b030627ba989c755ffd2b"

  url "https://github.com/ahmedayoub95/MacDownloadManager/releases/download/v#{version}/MacDownloadManager-#{version}.dmg"
  name "Mac Download Manager"
  desc "Multi-connection download manager with a browser extension for videos"
  homepage "https://github.com/ahmedayoub95/MacDownloadManager"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Mac Download Manager.app"

  # The app isn't notarized (that needs a paid Apple account). Installing it with brew is the
  # user's choice to trust it, so skip the "Open Anyway" step.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/Mac Download Manager.app"],
        must_succeed: false
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
