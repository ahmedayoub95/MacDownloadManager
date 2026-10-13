import { getSettings, parseList } from "./settings.js";
import { buildDownloadRequest, sendToApp } from "./native.js";

const MIME_EXTENSIONS = {
  "application/zip": "zip",
  "application/x-zip-compressed": "zip",
  "application/x-rar-compressed": "rar",
  "application/vnd.rar": "rar",
  "application/x-7z-compressed": "7z",
  "application/gzip": "gz",
  "application/x-apple-diskimage": "dmg",
  "application/x-iso9660-image": "iso",
  "application/pdf": "pdf",
  "application/epub+zip": "epub",
  "video/mp4": "mp4",
  "video/webm": "webm",
  "video/x-matroska": "mkv",
  "video/quicktime": "mov",
  "audio/mpeg": "mp3",
  "audio/mp4": "m4a",
};

function extensionFromName(name) {
  const base = name.split(/[\\/]/).pop() || "";
  const dot = base.lastIndexOf(".");
  return dot > 0 ? base.slice(dot + 1).toLowerCase() : "";
}

function guessExtension(item, url) {
  if (item.filename) {
    const ext = extensionFromName(item.filename);
    if (ext) return ext;
  }
  try {
    const ext = extensionFromName(decodeURIComponent(new URL(url).pathname));
    if (ext) return ext;
  } catch {}
  return MIME_EXTENSIONS[(item.mime || "").toLowerCase()] || "";
}

function isExcluded(url, excludedSites) {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return parseList(excludedSites).some((site) => host === site || host.endsWith("." + site));
  } catch {
    return false;
  }
}

export function shouldIntercept(item, url, settings) {
  if (!settings.interceptEnabled) return false;
  if (!/^https?:/i.test(url)) return false; // blob: and data: URLs only exist inside the browser
  if (isExcluded(url, settings.excludedSites) || isExcluded(item.referrer || "", settings.excludedSites)) return false;

  const ext = guessExtension(item, url);
  if (ext && parseList(settings.extensions).includes(ext)) return true;

  const size = item.fileSize > 0 ? item.fileSize : item.totalBytes;
  return settings.minSizeMB > 0 && size > 0 && size >= settings.minSizeMB * 1024 * 1024;
}

// Cached so the decision in onCreated is synchronous and Chrome's copy can be cancelled at once.
let settingsCache = null;
getSettings().then((s) => (settingsCache = s));
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "sync" || !settingsCache) return;
  for (const [key, { newValue }] of Object.entries(changes)) settingsCache[key] = newValue;
});

// Hides Chrome's download bubble while we take a download away from it.
let hiddenCount = 0;
function hideChromeDownloadUI() {
  hiddenCount++;
  chrome.downloads.setUiOptions?.({ enabled: false }).catch(() => {});
}
function restoreChromeDownloadUI(delayMs = 1500) {
  setTimeout(() => {
    hiddenCount = Math.max(0, hiddenCount - 1);
    if (hiddenCount === 0) chrome.downloads.setUiOptions?.({ enabled: true }).catch(() => {});
  }, delayMs);
}

/** Hands a download to the app; if the app can't take it, the browser downloads it instead. */
export async function sendDownloadToApp({ url, filename = "", mime = "", size = -1, referrer = "", pageUrl = "", incognito = false }) {
  try {
    const request = await buildDownloadRequest({
      url,
      source: "intercept",
      filename,
      mime,
      size,
      referrer,
      pageUrl,
      cookieStoreId: incognito ? "1" : undefined,
    });
    return await sendToApp(request);
  } catch (error) {
    console.warn("[intercept] App unavailable, letting the browser download:", error);
    // Marked as ours via byExtensionId, so it won't be intercepted again.
    await chrome.downloads.download({ url, ...(filename ? { filename } : {}) }).catch(() => {});
    return { ok: false, error: String(error?.message || error) };
  }
}

function handleCreated(item) {
  if (item.byExtensionId === chrome.runtime.id) return;
  if (item.state !== "in_progress") return;
  if (!settingsCache) {
    // The service worker was just woken up by this download.
    getSettings().then((s) => {
      settingsCache = s;
      handleCreated(item);
    });
    return;
  }

  const url = item.finalUrl || item.url;
  if (!shouldIntercept(item, url, settingsCache)) return;

  hideChromeDownloadUI();
  chrome.downloads
    .cancel(item.id)
    .catch(() => {})
    .then(() => chrome.downloads.erase({ id: item.id }))
    .catch(() => {})
    .finally(() => restoreChromeDownloadUI());

  sendDownloadToApp({
    url,
    filename: item.filename ? item.filename.split(/[\\/]/).pop() : "",
    mime: item.mime || "",
    size: item.fileSize > 0 ? item.fileSize : item.totalBytes,
    referrer: item.referrer || "",
    incognito: item.incognito,
  });
}

export function startDownloadInterception() {
  chrome.downloads.onCreated.addListener((item) => {
    try {
      handleCreated(item);
    } catch (error) {
      console.error("[intercept]", error);
    }
  });
}
