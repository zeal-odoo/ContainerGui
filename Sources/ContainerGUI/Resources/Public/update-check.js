"use strict";

globalThis.ContainerGUIUpdate = (() => {
  const AUTO_UPDATE_CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;
  const STORAGE_KEY = "container-gui-last-update-check";
  const RELEASE_PATH_PREFIX = "/zeal-odoo/ContainerGui/releases/";

  function shouldRunAutomaticCheck(lastCheckedAt, now = Date.now()) {
    const last = Number(lastCheckedAt);
    return !Number.isFinite(last) || last < 0 || last > now || now - last >= AUTO_UPDATE_CHECK_INTERVAL_MS;
  }

  function validatedReleaseURL(value) {
    try {
      const url = new URL(value);
      if (url.protocol !== "https:" ||
          url.hostname !== "github.com" ||
          url.port ||
          url.username ||
          url.password ||
          url.search ||
          url.hash ||
          !url.pathname.startsWith(RELEASE_PATH_PREFIX)) return null;
      return url.href;
    } catch {
      return null;
    }
  }

  return Object.freeze({
    AUTO_UPDATE_CHECK_INTERVAL_MS,
    STORAGE_KEY,
    shouldRunAutomaticCheck,
    validatedReleaseURL
  });
})();
