# Mac Download Manager

A free download manager for macOS, inspired by Internet Download Manager (IDM) on Windows.

**[Download](https://github.com/ahmedayoub95/MacDownloadManager/releases/latest) · [Website](https://ahmedayoub95.github.io/MacDownloadManager/)**

![The Mac Download Manager window with a download in progress](docs/screenshots/app.png)

- **Fast:** up to 16 connections per file, with pause and resume.
- **Videos:** a "⬇ Download this video" button on YouTube and other sites, saved as MP4.
- **Catches browser downloads** in Chrome, Brave, Edge, Vivaldi and Chromium.

Requires **macOS 14 (Sonoma) or newer**, on Apple Silicon or Intel.

> [!IMPORTANT]
> It comes as **a Mac app and a browser extension, and you need both.** Without the extension, your browser keeps downloading files itself and the video button doesn't appear.

## Installation

### 1. Download

Get **`MacDownloadManager-<version>.zip`** from the [latest release](https://github.com/ahmedayoub95/MacDownloadManager/releases/latest). It contains the app's `.dmg` and the **Browser Extension** folder. Open the `.dmg` and drag **Mac Download Manager** onto **Applications**.

Or with [Homebrew](https://brew.sh):

```bash
brew tap ahmedayoub95/mdm https://github.com/ahmedayoub95/MacDownloadManager
brew install --cask ahmedayoub95/mdm/mac-download-manager
```

### 2. Open it the first time

The app isn't notarized by Apple, so macOS blocks it once. (Homebrew installs skip this.)

- **macOS 15 and newer:** open the app and click **Done**. Then go to **System Settings → Privacy & Security** and click **Open Anyway**.
- **macOS 14:** right-click the app, choose **Open**, then **Open** again.

### 3. Follow the setup window

1. Click **Install Missing Tools** (yt-dlp, ffmpeg and Deno; nothing is installed system-wide).
2. The app connects itself to your browsers. Nothing to click.
3. **Add the extension (required):**
   1. Open `chrome://extensions`.
   2. Turn on **Developer mode**.
   3. Click **Load unpacked** and choose the folder the setup window shows.
   4. Pin the extension and refresh any open tabs.

The setup window shows **"Extension connected"** when it's done. You can reopen it from **Mac Download Manager → Setup…**.

## Using it

- **Click a download link** in the browser. Files of the listed types, or 20 MB or more, go to the app.
- **Click "⬇ Download this video"** over a playing video.
- **Right-click** a link → **Download with Mac Download Manager**.
- **Paste a link** in the app with **⌘N**.

Downloads keep going when you close the window or the browser. Change the download folder in **Settings** (⌘,).

## Updating

Download the new release and replace the app in Applications, or run `brew upgrade --cask mac-download-manager`. Then click **↻** on the extension in `chrome://extensions`.

## Troubleshooting

- **Downloads still go to the browser:** check that the extension is on at `chrome://extensions` and that its popup says **"App connected"**.
- **Popup says "App not found":** open **Setup…** and click **Connect Again**, then fully quit the browser (⌘Q) and reopen it.
- **No video button:** refresh the page, and let the video play.
- **YouTube download fails:** usually an outdated yt-dlp; the app updates it daily, so try again later.
- **A download fails:** hover over **Failed** for the error, or click ▶ to retry. Logs are in `~/Library/Logs/MacDownloadManager/`.

Still stuck? [Open an issue](https://github.com/ahmedayoub95/MacDownloadManager/issues).

## Uninstalling

Remove the extension at `chrome://extensions`, quit the app, then run:

```bash
brew uninstall --zap --cask mac-download-manager   # if you used Homebrew
```

Otherwise:

```bash
rm -rf "/Applications/Mac Download Manager.app" ~/Library/Application\ Support/MacDownloadManager \
       ~/Library/Caches/MacDownloadManager ~/Library/Logs/MacDownloadManager
for b in "Google/Chrome" "Chromium" "BraveSoftware/Brave-Browser" "Microsoft Edge" "Vivaldi"; do
  rm -f ~/Library/Application\ Support/"$b"/NativeMessagingHosts/com.ahmed.downloadmanager.json
done
```

Your downloaded files are not touched.

## Privacy

Nothing is sent anywhere except the downloads themselves: no analytics, no account, no server. The extension passes your cookies only to the app on your Mac, so downloads that need you to be signed in work.

## Building from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ahmedayoub95/MacDownloadManager.git
cd MacDownloadManager
./scripts/install.sh
```

**Releasing:** bump `VERSION`, commit, then `git tag v<version> && git push origin v<version>`. GitHub Actions publishes the `.zip` and `.dmg` and updates the Homebrew cask.

## Disclaimer

Only download content you have the right to download. This app does not bypass DRM, so Netflix, Spotify and similar services are not supported. It is not affiliated with Internet Download Manager, Google or YouTube.

## License

[MIT](LICENSE). The tools it downloads keep their own licenses: [yt-dlp](https://github.com/yt-dlp/yt-dlp), [ffmpeg](https://ffmpeg.org/legal.html) and [Deno](https://github.com/denoland/deno).
