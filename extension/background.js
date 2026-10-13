import { DEFAULT_SETTINGS } from "./lib/settings.js";
import { buildDownloadRequest, pingApp, sendToApp } from "./lib/native.js";
import { getMedia, needsPageExtractor, startMediaDetection } from "./lib/media.js";
import { sendDownloadToApp, startDownloadInterception } from "./lib/intercept.js";

startDownloadInterception();
startMediaDetection();

chrome.runtime.onInstalled.addListener(async () => {
  const current = await chrome.storage.sync.get(null);
  await chrome.storage.sync.set({ ...DEFAULT_SETTINGS, ...current });

  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "mdm-link",
      title: "Download with Mac Download Manager",
      contexts: ["link"],
    });
    chrome.contextMenus.create({
      id: "mdm-media",
      title: "Download this media with Mac Download Manager",
      contexts: ["video", "audio"],
    });
  });

  chrome.action.setBadgeBackgroundColor({ color: "#2563eb" });
  pingApp(); // lets the app's setup window know the extension is installed
});

chrome.runtime.onStartup.addListener(() => pingApp());

async function mediaForTab(tab, currentSrc = "") {
  if (tab?.url && needsPageExtractor(tab.url)) {
    return [{ url: tab.url, kind: "page", mime: "", size: -1, label: "Video on this page" }];
  }
  const items = await getMedia(tab.id);
  if (/^https?:/i.test(currentSrc) && !items.some((item) => item.url === currentSrc)) {
    items.unshift({ url: currentSrc, kind: "file", mime: "", size: -1 });
  }
  return items;
}

async function sendMedia(item, tab) {
  const request = await buildDownloadRequest({
    url: item.url,
    source: "video",
    kind: item.kind,
    mime: item.mime,
    size: item.size,
    pageUrl: tab?.url || "",
    pageTitle: tab?.title || "",
  });
  return sendToApp(request);
}

async function handleMessage(message, sender) {
  switch (message.type) {
    case "get-status":
      return pingApp();

    case "get-media": {
      const tab = message.tabId ? await chrome.tabs.get(message.tabId) : sender.tab;
      return { items: await mediaForTab(tab, message.currentSrc) };
    }

    case "download-link":
      return sendDownloadToApp({
        url: message.url,
        filename: message.filename || "",
        referrer: sender.tab?.url || "",
        pageUrl: sender.tab?.url || "",
        incognito: sender.tab?.incognito || false,
      });

    case "list-jobs":
      return sendToApp({ type: "list-jobs" });

    case "job-action":
      if (!["pause", "resume", "cancel", "reveal", "open", "clear-finished"].includes(message.action)) {
        throw new Error(`Unknown action: ${message.action}`);
      }
      return sendToApp({ type: message.action, id: message.id });

    case "download-media": {
      const tab = message.tabId ? await chrome.tabs.get(message.tabId) : sender.tab;
      return sendMedia(message.item, tab);
    }

    default:
      throw new Error(`Unknown message: ${message.type}`);
  }
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender)
    .then(sendResponse)
    .catch((error) => sendResponse({ ok: false, error: String(error?.message || error) }));
  return true;
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const url = info.linkUrl || info.srcUrl;
  if (!url) return;

  if (info.menuItemId === "mdm-media" && !/^https?:/i.test(url)) {
    // blob: players: fall back to the streams detected for this tab
    const items = await mediaForTab(tab);
    if (items[0]) await sendMedia(items[0], tab).catch((e) => console.warn(e));
    return;
  }

  try {
    const request = await buildDownloadRequest({
      url,
      source: "context-menu",
      pageUrl: info.pageUrl || tab?.url || "",
      pageTitle: tab?.title || "",
    });
    await sendToApp(request);
  } catch (error) {
    console.warn("[context-menu] App unavailable, using the browser instead:", error);
    if (/^https?:/i.test(url)) chrome.downloads.download({ url });
  }
});
