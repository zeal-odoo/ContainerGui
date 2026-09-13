"use strict";

globalThis.ContainerGUIEngineUpdate = (() => {
  const CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;
  const RETRY_INTERVAL_MS = 30 * 60 * 1000;

  function start(fetchJSON) {
    const button = document.getElementById("checkContainerUpdatesButton");
    const status = document.getElementById("containerUpdateStatus");
    const banner = document.getElementById("containerUpdateBanner");
    const versions = document.getElementById("containerUpdateVersions");
    const link = document.getElementById("containerUpdateLink");
    let checking = false;
    let nextCheckAt = 0;

    async function check({ automatic = false } = {}) {
      if (checking || (automatic && (document.visibilityState !== "visible" || Date.now() < nextCheckAt))) return;
      checking = true;
      button.disabled = true;
      button.setAttribute("aria-busy", "true");
      if (!automatic) status.textContent = "正在检查 Container 更新…";
      try {
        const result = await fetchJSON("/api/v1/container-update-check");
        const releaseURL = ContainerGUIUpdate.validatedContainerReleaseURL(result.releaseURL);
        if (!releaseURL || typeof result.updateAvailable !== "boolean" ||
            !/^\d+\.\d+\.\d+$/.test(result.currentVersion) ||
            !/^\d+\.\d+\.\d+$/.test(result.latestVersion)) throw new Error("Invalid release");
        banner.hidden = !result.updateAvailable;
        versions.textContent = `${result.currentVersion} → ${result.latestVersion}`;
        link.href = releaseURL;
        status.textContent = result.updateAvailable ? "Container 有新版本" : "Container 已是最新版本";
        nextCheckAt = Date.now() + CHECK_INTERVAL_MS;
      } catch {
        // Keep any known update visible. Network failure must not imply up-to-date.
        status.textContent = "Container 更新检查失败，可点击重试。";
        nextCheckAt = Date.now() + RETRY_INTERVAL_MS;
      } finally {
        checking = false;
        button.disabled = false;
        button.setAttribute("aria-busy", "false");
        globalThis.ContainerGUII18n?.apply(status);
        globalThis.ContainerGUII18n?.apply(banner);
      }
    }

    button.addEventListener("click", () => check());
    document.addEventListener("visibilitychange", () => check({ automatic: true }));
    window.setInterval(() => check({ automatic: true }), 60 * 1000);
    check({ automatic: true });
    return { check };
  }

  return Object.freeze({ start, CHECK_INTERVAL_MS, RETRY_INTERVAL_MS });
})();
