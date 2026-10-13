export const DEFAULT_SETTINGS = {
  interceptEnabled: true,
  videoButtonEnabled: true,
  // Downloads at least this big are sent to the app even if the extension isn't listed. 0 turns it off.
  minSizeMB: 20,
  extensions:
    "zip rar 7z tar gz tgz bz2 xz dmg pkg iso img exe msi apk " +
    "pdf epub doc docx xls xlsx ppt pptx " +
    "mp4 mkv avi mov wmv flv webm m4v mpg mpeg 3gp " +
    "mp3 m4a wav flac aac ogg opus",
  excludedSites: "",
};

export async function getSettings() {
  return chrome.storage.sync.get(DEFAULT_SETTINGS);
}

export function parseList(text) {
  return text
    .toLowerCase()
    .split(/[\s,]+/)
    .map((s) => s.replace(/^\./, "").trim())
    .filter(Boolean);
}
