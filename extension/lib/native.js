export const HOST_NAME = "com.ahmed.downloadmanager";

export async function sendToApp(message) {
  const reply = await chrome.runtime.sendNativeMessage(HOST_NAME, message);
  if (!reply || reply.ok !== true) {
    throw new Error(reply?.error || "The app rejected the request");
  }
  return reply;
}

export async function pingApp() {
  try {
    const reply = await sendToApp({ type: "ping" });
    return { online: true, version: reply.version };
  } catch (error) {
    return { online: false, error: String(error?.message || error) };
  }
}

async function cookieHeaderFor(url, storeId) {
  try {
    const cookies = await chrome.cookies.getAll(storeId ? { url, storeId } : { url });
    return cookies.map((c) => `${c.name}=${c.value}`).join("; ");
  } catch {
    return "";
  }
}

// Everything the app needs to repeat the request exactly as the browser would.
export async function buildDownloadRequest({
  url,
  source,
  kind = "file",
  filename = "",
  mime = "",
  size = -1,
  referrer = "",
  pageUrl = "",
  pageTitle = "",
  cookieStoreId,
}) {
  return {
    type: "download",
    id: crypto.randomUUID(),
    source,
    kind,
    url,
    filename,
    mime,
    size,
    referrer: referrer || pageUrl,
    pageUrl,
    pageTitle,
    cookies: await cookieHeaderFor(url, cookieStoreId),
    userAgent: navigator.userAgent,
  };
}
