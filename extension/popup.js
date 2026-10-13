import { DEFAULT_SETTINGS } from "./lib/settings.js";

const statusEl = document.getElementById("status");
const mediaEl = document.getElementById("media");

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

async function showStatus() {
  const status = await chrome.runtime.sendMessage({ type: "get-status" });
  statusEl.className = `status ${status.online ? "online" : "offline"}`;
  statusEl.textContent = status.online
    ? `App connected (${status.version})`
    : "App not found. Downloads will stay in the browser.";
  statusEl.title = status.error || "";
}

async function bindToggles() {
  const settings = await chrome.storage.sync.get(DEFAULT_SETTINGS);
  for (const key of ["interceptEnabled", "videoButtonEnabled"]) {
    const box = document.getElementById(key);
    box.checked = settings[key];
    box.addEventListener("change", () => chrome.storage.sync.set({ [key]: box.checked }));
  }
}

async function showMedia() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return;
  const { items = [] } = await chrome.runtime.sendMessage({ type: "get-media", tabId: tab.id });
  if (!items.length) return;

  mediaEl.replaceChildren(
    ...items.map((item) => {
      const row = document.createElement("div");
      row.className = "item";

      let name = item.label || "";
      if (!name) {
        try {
          name = decodeURIComponent(new URL(item.url).pathname.split("/").pop()) || item.url;
        } catch {
          name = item.url;
        }
      }

      const info = document.createElement("div");
      info.className = "info";
      info.innerHTML = `<div class="name"></div><div class="muted"></div>`;
      info.querySelector(".name").textContent = name;
      info.querySelector(".muted").textContent = [item.kind.toUpperCase(), formatBytes(item.size)]
        .filter(Boolean)
        .join(" · ");
      info.title = item.url;

      const button = document.createElement("button");
      button.textContent = "Download";
      button.addEventListener("click", async () => {
        button.disabled = true;
        const reply = await chrome.runtime.sendMessage({ type: "download-media", tabId: tab.id, item });
        button.textContent = reply?.ok ? "Sent ✓" : "Failed";
        button.title = reply?.error || "";
      });

      row.append(info, button);
      return row;
    })
  );
}

const jobsEl = document.getElementById("jobs");
const jobRows = new Map();

const STATE_LABELS = {
  starting: "Starting…",
  downloading: "Downloading",
  merging: "Joining video and audio…",
  done: "Done",
  failed: "Failed",
  cancelled: "Cancelled",
};

function jobAction(action, id) {
  return chrome.runtime.sendMessage({ type: "job-action", action, id });
}

function createJobRow(job) {
  const row = document.createElement("div");
  row.className = "job";
  row.innerHTML = `
    <div class="name"></div>
    <div class="bar"><div class="fill"></div></div>
    <div class="job-foot">
      <span class="muted detail"></span>
      <span class="job-actions">
        <button class="small cancel">Cancel</button>
        <button class="small reveal">Show in Finder</button>
      </span>
    </div>`;
  row.querySelector(".cancel").addEventListener("click", () => jobAction("cancel", job.id).then(refreshJobs));
  row.querySelector(".reveal").addEventListener("click", () => jobAction("reveal", job.id));
  row.querySelector(".name").addEventListener("dblclick", () => jobAction("open", job.id));
  return row;
}

function renderJob(row, job) {
  const active = !["done", "failed", "cancelled"].includes(job.state);
  const percent = job.state === "done" ? 100 : Math.max(0, Math.min(100, job.percent || 0));

  row.className = `job ${job.state}`;
  row.querySelector(".name").textContent = job.name || job.url;
  row.querySelector(".name").title = job.path || job.url;
  row.querySelector(".fill").style.width = `${percent}%`;

  let detail = STATE_LABELS[job.state] || job.state;
  if (job.state === "downloading") {
    const stage = job.stage === "audio" ? "audio" : job.stage === "video" ? "video" : "";
    detail = [
      `${percent.toFixed(1)}%${stage ? ` (${stage})` : ""}`,
      job.size,
      job.speed,
      job.eta ? `${job.eta} left` : "",
    ]
      .filter(Boolean)
      .join(" · ");
  } else if (job.state === "failed" && job.error) {
    detail = `Failed: ${job.error}`;
  }
  const detailEl = row.querySelector(".detail");
  detailEl.textContent = detail;
  detailEl.title = job.error || "";

  row.querySelector(".cancel").hidden = !active;
  row.querySelector(".reveal").hidden = job.state !== "done";
}

async function refreshJobs() {
  const reply = await chrome.runtime.sendMessage({ type: "list-jobs" });
  const jobs = reply?.ok ? reply.jobs : [];
  if (!jobs.length) {
    jobRows.clear();
    jobsEl.innerHTML = `<p class="muted">No downloads yet.</p>`;
    return;
  }
  const seen = new Set();
  const ordered = jobs.map((job) => {
    seen.add(job.id);
    let row = jobRows.get(job.id);
    if (!row) {
      row = createJobRow(job);
      jobRows.set(job.id, row);
    }
    renderJob(row, job);
    return row;
  });
  for (const id of jobRows.keys()) if (!seen.has(id)) jobRows.delete(id);
  jobsEl.replaceChildren(...ordered);
}

document.getElementById("clearFinished").addEventListener("click", async (event) => {
  event.preventDefault();
  await jobAction("clear-finished");
  refreshJobs();
});

refreshJobs();
setInterval(refreshJobs, 1000);

document.getElementById("openOptions").addEventListener("click", (event) => {
  event.preventDefault();
  chrome.runtime.openOptionsPage();
});

bindToggles();
showStatus();
showMedia();
