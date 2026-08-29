import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";
import test from "node:test";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const script = readFileSync(
  resolve(testDirectory, "../../Sources/ContainerGUI/Resources/Public/app.js"),
  "utf8"
);

function functionSource(name) {
  const match = script.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
  assert.ok(match, `${name} must be defined in app.js`);
  return match[0];
}

function loadStorageDisplay(metricsStatus, metric) {
  return runInNewContext(`
    const state = {
      metricsStatus: ${JSON.stringify(metricsStatus)},
      metricsByID: new Map([["demo", ${JSON.stringify(metric)}]])
    };
    ${functionSource("metricFor")}
    ${functionSource("formatPercent")}
    ${functionSource("formatBytes")}
    ${functionSource("storageDisplay")}
    storageDisplay;
  `);
}

test("storage display shows root filesystem usage and capacity", () => {
  const display = loadStorageDisplay("ready", {
    rootFilesystem: {
      state: "ready",
      usedBytes: 1_073_741_824,
      capacityBytes: 4_294_967_296,
      availableBytes: 3_221_225_472,
      usagePercent: 25
    }
  })({ id: "demo", state: "running" });

  assert.equal(display.value, "25.00%");
  assert.equal(display.detail, "1.00 GiB / 4.00 GiB");
});

test("storage display distinguishes stopped, loading, and unavailable states", () => {
  const stopped = loadStorageDisplay("ready", null)({ id: "demo", state: "stopped" });
  const loading = loadStorageDisplay("loading", null)({ id: "missing", state: "running" });
  const unavailable = loadStorageDisplay("ready", {
    rootFilesystem: {
      state: "unavailable",
      usedBytes: null,
      capacityBytes: null,
      availableBytes: null,
      usagePercent: null
    }
  })({ id: "demo", state: "running" });

  assert.equal(stopped.value, "未运行");
  assert.equal(loading.value, "读取中");
  assert.equal(unavailable.value, "暂不可用");
});
