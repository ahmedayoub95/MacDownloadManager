// Point the download buttons at the newest .zip (app + extension) and .dmg. Without this (or if
// GitHub's API is unreachable) they open the latest release page, which works too.
(async () => {
  try {
    const response = await fetch("https://api.github.com/repos/ahmedayoub95/MacDownloadManager/releases/latest");
    if (!response.ok) return;
    const release = await response.json();
    const assets = release.assets || [];
    const dmg = assets.find((asset) => asset.name.endsWith(".dmg"));
    const zip = assets.find((asset) => asset.name.endsWith(".zip")) || dmg;
    if (!zip) return;
    if (dmg) document.getElementById("dmg-link").href = dmg.browser_download_url;
    for (const id of ["download", "zip-link"]) {
      document.getElementById(id).href = zip.browser_download_url;
    }
    const sizeMB = (zip.size / 1024 / 1024).toFixed(1);
    document.getElementById("download-detail").textContent =
      `Version ${release.tag_name.replace(/^v/, "")} · ${sizeMB} MB · macOS 14 or newer`;
  } catch {
    // Keep the release page links.
  }
})();

for (const button of document.querySelectorAll(".copy")) {
  button.addEventListener("click", async () => {
    const text = document.getElementById(button.dataset.copy).textContent;
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "Copied";
    } catch {
      button.textContent = "Press ⌘C";
      getSelection().selectAllChildren(document.getElementById(button.dataset.copy));
    }
    setTimeout(() => (button.textContent = "Copy"), 1600);
  });
}
