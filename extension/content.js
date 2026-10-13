(() => {
  if (window.__mdmContentLoaded) return;
  window.__mdmContentLoaded = true;

  const MIN_WIDTH = 200;
  const MIN_HEIGHT = 120;
  const MARGIN = 12;

  const videos = new Set();
  let enabled = true;
  let target = null;
  let hovered = null;
  let menuOpen = false;
  let rafId = 0;
  let toastTimer = 0;

  // ---------- UI (inside a closed shadow root so page CSS can't touch it) ----------

  const host = document.createElement("mdm-video-button");
  host.style.cssText = "all: initial; position: fixed; top: 0; left: 0; width: 0; height: 0; z-index: 2147483647;";
  const root = host.attachShadow({ mode: "closed" });
  root.innerHTML = `
    <style>
      .wrap { position: fixed; display: none; flex-direction: column; align-items: flex-end; gap: 6px;
              font: 13px/1.35 -apple-system, BlinkMacSystemFont, system-ui, sans-serif; }
      .btn { all: unset; display: flex; align-items: center; gap: 6px; padding: 6px 10px; border-radius: 6px;
             background: rgba(37, 99, 235, 0.92); color: #fff; font-weight: 600; cursor: pointer;
             white-space: nowrap; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35); }
      .btn:hover { background: #1d4ed8; }
      .panel { background: #111827; color: #f9fafb; border-radius: 8px; box-shadow: 0 6px 20px rgba(0, 0, 0, 0.45); }
      .menu { min-width: 280px; max-width: 420px; max-height: 300px; overflow: auto; padding: 4px; }
      .menu button { all: unset; display: block; box-sizing: border-box; width: 100%; padding: 8px 10px;
                     border-radius: 6px; cursor: pointer; }
      .menu button:hover { background: #1f2937; }
      .title { font-weight: 600; }
      .meta { color: #9ca3af; font-size: 11px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .toast { max-width: 300px; padding: 8px 10px; }
      [hidden] { display: none !important; }
    </style>
    <div class="wrap">
      <button class="btn" type="button">⬇ Download this video</button>
      <div class="panel menu" hidden></div>
      <div class="panel toast" hidden></div>
    </div>`;

  const wrap = root.querySelector(".wrap");
  const button = root.querySelector(".btn");
  const menu = root.querySelector(".menu");
  const toast = root.querySelector(".toast");

  for (const type of ["pointerdown", "mousedown", "mouseup", "click", "dblclick"]) {
    wrap.addEventListener(type, (event) => event.stopPropagation());
  }

  function showToast(text, ms = 4000) {
    toast.textContent = text;
    toast.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (toast.hidden = true), ms);
  }

  function closeMenu() {
    menuOpen = false;
    menu.hidden = true;
    menu.replaceChildren();
  }

  function formatBytes(bytes) {
    if (!(bytes > 0)) return "";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let i = 0;
    while (bytes >= 1024 && i < units.length - 1) {
      bytes /= 1024;
      i++;
    }
    return `${bytes.toFixed(i ? 1 : 0)} ${units[i]}`;
  }

  function describe(item) {
    const names = { hls: "HLS stream (.m3u8)", dash: "DASH stream (.mpd)", page: "Video on this page" };
    let file = "";
    try {
      file = decodeURIComponent(new URL(item.url).pathname.split("/").pop() || "");
    } catch {}
    const title = names[item.kind] || item.mime || file.split(".").pop()?.toUpperCase() || "Media file";
    const meta = [formatBytes(item.size), file].filter(Boolean).join(" · ");
    return { title, meta };
  }

  // ---------- talking to the background script ----------

  async function ask(message) {
    try {
      return await chrome.runtime.sendMessage(message);
    } catch {
      return { ok: false, error: "The extension was updated. Reload this page and try again." };
    }
  }

  async function download(item) {
    closeMenu();
    button.textContent = "Sending…";
    const reply = await ask({ type: "download-media", item });
    button.textContent = "⬇ Download this video";
    if (reply?.ok) {
      showToast(
        reply.duplicate
          ? "This video is already downloading in Mac Download Manager."
          : "Download started ✓ Progress is shown in Mac Download Manager.",
        3500
      );
    } else {
      showToast(
        /updated/.test(reply?.error || "")
          ? reply.error
          : "Couldn't reach the Mac Download Manager app. Make sure it's installed."
      );
    }
  }

  function openMenu(items) {
    menu.replaceChildren(
      ...items.map((item) => {
        const { title, meta } = describe(item);
        const row = document.createElement("button");
        row.type = "button";
        row.innerHTML = `<div class="title"></div><div class="meta"></div>`;
        row.querySelector(".title").textContent = title;
        row.querySelector(".meta").textContent = meta;
        row.title = item.url;
        row.addEventListener("click", () => download(item));
        return row;
      })
    );
    menu.hidden = false;
    menuOpen = true;
  }

  button.addEventListener("click", async () => {
    if (menuOpen) return closeMenu();
    toast.hidden = true;
    const reply = await ask({ type: "get-media", currentSrc: target?.currentSrc || "" });
    const items = reply?.items || [];
    if (reply?.ok === false) showToast(reply.error);
    else if (!items.length) showToast("No downloadable stream found yet. Let the video play for a few seconds, then try again.");
    else if (items.length === 1) download(items[0]);
    else openMenu(items);
  });

  // ---------- choosing which video gets the button ----------

  function isUsable(video) {
    if (!video.isConnected) return false;
    const r = video.getBoundingClientRect();
    if (r.width < MIN_WIDTH || r.height < MIN_HEIGHT) return false;
    if (r.bottom <= 0 || r.right <= 0 || r.top >= innerHeight || r.left >= innerWidth) return false;
    const style = getComputedStyle(video);
    return style.visibility !== "hidden" && style.display !== "none" && Number(style.opacity) > 0;
  }

  function area(video) {
    const r = video.getBoundingClientRect();
    return r.width * r.height;
  }

  function pickTarget() {
    for (const v of videos) if (!v.isConnected) videos.delete(v);
    if (hovered && isUsable(hovered)) return hovered;
    const playing = [...videos].filter((v) => !v.paused && !v.ended && isUsable(v));
    playing.sort((a, b) => area(b) - area(a));
    return playing[0] || null;
  }

  function mount() {
    const fs = document.fullscreenElement;
    const parent = fs && fs.tagName !== "VIDEO" ? fs : document.documentElement;
    if (parent && host.parentNode !== parent) parent.appendChild(host);
  }

  function hide() {
    wrap.style.display = "none";
    closeMenu();
  }

  function tick() {
    rafId = 0;
    if (!target || !target.isConnected) return hide();
    const r = target.getBoundingClientRect();
    if (r.width < MIN_WIDTH || r.height < MIN_HEIGHT || r.bottom <= 0 || r.top >= innerHeight) return hide();
    wrap.style.display = "flex";
    wrap.style.top = `${Math.max(r.top, 0) + MARGIN}px`;
    wrap.style.right = `${Math.max(innerWidth - Math.min(r.right, innerWidth), 0) + MARGIN}px`;
    rafId = requestAnimationFrame(tick);
  }

  function update() {
    if (!enabled) {
      target = null;
      return hide();
    }
    if (!menuOpen) target = pickTarget();
    mount();
    if (!target) return hide();
    if (!rafId) tick();
  }

  // ---------- finding videos ----------

  function scan() {
    document.querySelectorAll("video").forEach((v) => videos.add(v));
    update();
  }

  for (const type of ["play", "playing", "pause", "ended", "loadedmetadata", "emptied"]) {
    document.addEventListener(
      type,
      (event) => {
        const el = event.composedPath()[0];
        if (el instanceof HTMLVideoElement) {
          videos.add(el);
          update();
        }
      },
      true
    );
  }

  document.addEventListener(
    "pointermove",
    (event) => {
      if (event.composedPath().includes(host)) return;
      let found = null;
      for (const v of videos) {
        const r = v.getBoundingClientRect();
        if (event.clientX >= r.left && event.clientX <= r.right && event.clientY >= r.top && event.clientY <= r.bottom) {
          found = v;
          break;
        }
      }
      if (found !== hovered) {
        hovered = found;
        update();
      }
    },
    { capture: true, passive: true }
  );

  document.addEventListener("fullscreenchange", update);
  document.addEventListener("keydown", (event) => event.key === "Escape" && menuOpen && closeMenu(), true);

  let scanTimer = 0;
  new MutationObserver(() => {
    if (!scanTimer) scanTimer = setTimeout(() => ((scanTimer = 0), scan()), 500);
  }).observe(document.documentElement, { childList: true, subtree: true });

  setInterval(update, 1000);

  // ---------- taking over download links before the browser starts them ----------

  // Clicking these normally opens them in a browser tab, so only take them over when the link
  // explicitly says "download".
  const BROWSER_VIEWABLE = new Set(["pdf", "mp4", "webm", "m4v", "mov", "mp3", "m4a", "ogg", "opus", "wav", "flac", "aac", "txt"]);
  let linkSettings = null;

  function parseList(text) {
    return (text || "").toLowerCase().split(/[\s,]+/).map((s) => s.replace(/^\./, "")).filter(Boolean);
  }

  function hostExcluded(hostname, sites) {
    return sites.some((site) => hostname === site || hostname.endsWith("." + site));
  }

  function extensionOf(name) {
    const base = name.split(/[\\/]/).pop() || "";
    const dot = base.lastIndexOf(".");
    return dot > 0 ? base.slice(dot + 1).toLowerCase() : "";
  }

  function loadLinkSettings() {
    chrome.storage.sync.get(["interceptEnabled", "extensions", "excludedSites"]).then((s) => {
      linkSettings = {
        enabled: s.interceptEnabled !== false && typeof s.extensions === "string",
        extensions: new Set(parseList(s.extensions)),
        excluded: parseList(s.excludedSites),
      };
    });
  }
  loadLinkSettings();
  chrome.storage.onChanged.addListener((_, area) => area === "sync" && loadLinkSettings());

  document.addEventListener(
    "click",
    (event) => {
      if (!linkSettings?.enabled || event.defaultPrevented || event.button !== 0) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const link = event.composedPath().find((el) => el instanceof HTMLAnchorElement && el.href);
      if (!link) return;

      let url;
      try {
        url = new URL(link.href);
      } catch {
        return;
      }
      if (url.protocol !== "http:" && url.protocol !== "https:") return;
      if (hostExcluded(url.hostname, linkSettings.excluded) || hostExcluded(location.hostname, linkSettings.excluded)) return;

      let path = url.pathname;
      try {
        path = decodeURIComponent(path);
      } catch {}
      const ext = extensionOf(link.getAttribute("download") || "") || extensionOf(path);
      if (!ext || !linkSettings.extensions.has(ext)) return;
      if (BROWSER_VIEWABLE.has(ext) && !link.hasAttribute("download")) return;

      event.preventDefault();
      event.stopImmediatePropagation();
      ask({ type: "download-link", url: link.href, filename: link.getAttribute("download") || "" }).then((reply) => {
        if (reply?.ok === false && /updated/.test(reply.error || "")) location.href = link.href;
      });
    },
    true
  );

  chrome.storage.sync.get({ videoButtonEnabled: true }).then((s) => {
    enabled = s.videoButtonEnabled;
    scan();
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "sync" && changes.videoButtonEnabled) {
      enabled = changes.videoButtonEnabled.newValue;
      update();
    }
  });
})();
