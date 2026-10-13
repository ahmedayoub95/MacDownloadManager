## Install

1. Download **`MacDownloadManager-<version>.dmg`** below, open it and drag **Mac Download Manager** onto **Applications**.
   Or with Homebrew:
   ```bash
   brew tap ahmedayoub95/mdm https://github.com/ahmedayoub95/MacDownloadManager
   brew install --cask ahmedayoub95/mdm/mac-download-manager
   ```
2. **First launch:** the app isn't notarized by Apple, so macOS blocks it once. Open it, click **Done**, then go to **System Settings → Privacy & Security** and click **Open Anyway**. (Homebrew installs skip this.)
3. **Follow the setup window.** It installs the download tools and connects the app to your browsers.
4. **Add the browser extension. This is required.** The extension is what sends the files you click in Chrome, Brave, Edge or Vivaldi to the app, and adds the "Download this video" button. Without it, the browser keeps downloading files itself. The setup window shows you how; it takes about a minute.

Requires macOS 14 (Sonoma) or newer, on Apple Silicon or Intel. Full instructions are in the [README](https://github.com/ahmedayoub95/MacDownloadManager#installation).
