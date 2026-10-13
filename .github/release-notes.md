## Which file do I download?

- **`MacDownloadManager-<version>.zip`** (recommended): the app's `.dmg` **and** the browser extension in one download, with a "How to install" guide.
- **`MacDownloadManager-<version>.dmg`**: just the app. The app can still give you the extension from its setup window.

## Install

1. Open the `.zip`, then open **`MacDownloadManager-<version>.dmg`** inside it and drag **Mac Download Manager** onto **Applications**.
   Or with Homebrew:
   ```bash
   brew tap ahmedayoub95/mdm https://github.com/ahmedayoub95/MacDownloadManager
   brew install --cask ahmedayoub95/mdm/mac-download-manager
   ```
2. **First launch:** the app isn't notarized by Apple, so macOS blocks it once. Open it, click **Done**, then go to **System Settings → Privacy & Security** and click **Open Anyway**. (Homebrew installs skip this.)
3. **Follow the setup window.** It installs the download tools and connects the app to your browsers.
4. **Add the browser extension. This is required.** The extension is what sends the files you click in Chrome, Brave, Edge or Vivaldi to the app, and adds the "Download this video" button. Without it, the browser keeps downloading files itself.
   Open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked** and choose the **Browser Extension** folder from the zip. Keep that folder where it is afterwards: the browser loads the extension from it.

Requires macOS 14 (Sonoma) or newer, on Apple Silicon or Intel. Full instructions are in the [README](https://github.com/ahmedayoub95/MacDownloadManager#installation).
