// Tracks video/audio streams each tab loads, so the video button knows what to download.

const MAX_ITEMS_PER_TAB = 50;
const MIN_FILE_BYTES = 512 * 1024;

const FILE_EXTENSIONS = new Set([
  "mp4", "m4v", "webm", "mkv", "mov", "flv", "avi", "mp3", "m4a", "ogg", "opus", "wav", "flac",
]);
const SEGMENT_EXTENSIONS = new Set(["ts", "m4s", "aac", "vtt", "key"]);

// Sites that split audio/video or obfuscate stream URLs; the app has to extract from the page URL.
const PAGE_EXTRACTOR_SITES = ["youtube.com", "youtu.be"];
const IGNORED_STREAM_HOSTS = ["googlevideo.com"];

const tabMedia = new Map();
let queue = Promise.resolve();

function enqueue(task) {
  queue = queue.then(task).catch((error) => console.error("[media]", error));
  return queue;
}

function hostMatches(hostname, domains) {
  return domains.some((d) => hostname === d || hostname.endsWith("." + d));
}

function extensionOf(url) {
  try {
    const last = new URL(url).pathname.split("/").pop() || "";
    const dot = last.lastIndexOf(".");
    return dot > 0 ? last.slice(dot + 1).toLowerCase() : "";
  } catch {
    return "";
  }
}

function header(headers, name) {
  const h = headers?.find((x) => x.name.toLowerCase() === name);
  return h?.value || "";
}

function totalSize(headers) {
  const range = header(headers, "content-range").match(/\/(\d+)\s*$/);
  if (range) return Number(range[1]);
  const length = Number(header(headers, "content-length"));
  return Number.isFinite(length) && length > 0 ? length : -1;
}

export function classify(url, contentType) {
  const type = contentType.split(";")[0].trim().toLowerCase();
  const ext = extensionOf(url);

  if (ext === "m3u8" || /mpegurl/.test(type)) return "hls";
  if (ext === "mpd" || type === "application/dash+xml") return "dash";
  if (SEGMENT_EXTENSIONS.has(ext) || type === "video/mp2t" || type === "video/iso.segment") return null;
  if (type.startsWith("video/") || type.startsWith("audio/")) return "file";
  if (FILE_EXTENSIONS.has(ext) && (type === "" || type === "application/octet-stream")) return "file";
  return null;
}

export function needsPageExtractor(pageUrl) {
  try {
    return hostMatches(new URL(pageUrl).hostname, PAGE_EXTRACTOR_SITES);
  } catch {
    return false;
  }
}

async function load(tabId) {
  if (!tabMedia.has(tabId)) {
    const key = `media:${tabId}`;
    const stored = await chrome.storage.session.get(key);
    tabMedia.set(tabId, stored[key] || []);
  }
  return tabMedia.get(tabId);
}

async function save(tabId) {
  const items = tabMedia.get(tabId) || [];
  await chrome.storage.session.set({ [`media:${tabId}`]: items });
  await chrome.action.setBadgeText({ tabId, text: items.length ? String(items.length) : "" }).catch(() => {});
}

export function clearTab(tabId) {
  return enqueue(async () => {
    tabMedia.delete(tabId);
    await chrome.storage.session.remove(`media:${tabId}`);
    await chrome.action.setBadgeText({ tabId, text: "" }).catch(() => {});
  });
}

function onHeadersReceived(details) {
  if (details.tabId < 0) return;
  if (details.statusCode !== 200 && details.statusCode !== 206) return;

  let hostname;
  try {
    hostname = new URL(details.url).hostname;
  } catch {
    return;
  }
  if (hostMatches(hostname, IGNORED_STREAM_HOSTS)) return;

  const contentType = header(details.responseHeaders, "content-type");
  const kind = classify(details.url, contentType);
  if (!kind) return;

  const size = totalSize(details.responseHeaders);
  if (kind === "file" && size >= 0 && size < MIN_FILE_BYTES) return;

  enqueue(async () => {
    const items = await load(details.tabId);
    if (items.some((item) => item.url === details.url)) return;
    items.push({
      url: details.url,
      kind,
      mime: contentType.split(";")[0].trim(),
      size,
      frameUrl: details.initiator || "",
      detectedAt: Date.now(),
    });
    if (items.length > MAX_ITEMS_PER_TAB) items.shift();
    await save(details.tabId);
  });
}

export function getMedia(tabId) {
  return enqueue(() => load(tabId)).then(() => [...(tabMedia.get(tabId) || [])]);
}

export function startMediaDetection() {
  chrome.webRequest.onHeadersReceived.addListener(
    onHeadersReceived,
    {
      urls: ["<all_urls>"],
      types: ["sub_frame", "media", "xmlhttprequest", "object", "other"],
    },
    ["responseHeaders"]
  );

  chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
    if (changeInfo.status === "loading" && changeInfo.url) clearTab(tabId);
  });
  chrome.tabs.onRemoved.addListener((tabId) => clearTab(tabId));
}
