import { DEFAULT_SETTINGS, getSettings } from "./lib/settings.js";

const fields = Object.keys(DEFAULT_SETTINGS);
const savedEl = document.getElementById("saved");

function fill(settings) {
  for (const key of fields) {
    const el = document.getElementById(key);
    if (el.type === "checkbox") el.checked = settings[key];
    else el.value = settings[key];
  }
}

function read() {
  const settings = {};
  for (const key of fields) {
    const el = document.getElementById(key);
    if (el.type === "checkbox") settings[key] = el.checked;
    else if (el.type === "number") settings[key] = Math.max(0, Number(el.value) || 0);
    else settings[key] = el.value.trim();
  }
  return settings;
}

function flash(text) {
  savedEl.textContent = text;
  setTimeout(() => (savedEl.textContent = ""), 2000);
}

document.getElementById("save").addEventListener("click", async () => {
  await chrome.storage.sync.set(read());
  flash("Saved");
});

document.getElementById("reset").addEventListener("click", async () => {
  await chrome.storage.sync.set(DEFAULT_SETTINGS);
  fill(DEFAULT_SETTINGS);
  flash("Defaults restored");
});

getSettings().then(fill);
