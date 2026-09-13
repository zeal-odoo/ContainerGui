import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const assets = new URL("../../Sources/ContainerGUI/Resources/Public/", import.meta.url);
const helper = readFileSync(new URL("update-check.js", assets), "utf8");
const script = readFileSync(new URL("container-update.js", assets), "utf8");
const newer = { currentVersion: "1.3.1", latestVersion: "1.4.1", updateAvailable: true,
  releaseURL: "https://github.com/apple/container/releases/tag/1.4.1" };

function setup(fetcher) {
  let time = 1_000_000;
  let timer;
  const nodes = new Map();
  const document = { visibilityState: "visible", addEventListener() {}, getElementById(id) {
    if (!nodes.has(id)) nodes.set(id, { hidden: true, textContent: "", setAttribute() {}, addEventListener() {} });
    return nodes.get(id);
  } };
  const context = { URL, document, Date: { now: () => time }, window: { setInterval(callback) { timer = callback; } } };
  const api = runInNewContext(`${helper}\n${script}; ContainerGUIEngineUpdate`, context);
  const controller = api.start(fetcher);
  return { nodes, document, api, controller, tick: () => timer(), advance: value => { time += value; } };
}
const settle = () => new Promise(resolve => setImmediate(resolve));

test("automatic discovery is non-modal, throttled, resumes when visible, and manual check bypasses interval", async () => {
  let calls = 0;
  const s = setup(async path => { assert.equal(path, "/api/v1/container-update-check"); calls++; return newer; });
  await settle();
  assert.equal(calls, 1);
  assert.equal(s.nodes.get("containerUpdateBanner").hidden, false);
  assert.equal(s.nodes.get("containerUpdateVersions").textContent, "1.3.1 → 1.4.1");
  await s.tick();
  assert.equal(calls, 1);
  s.advance(s.api.CHECK_INTERVAL_MS);
  s.document.visibilityState = "hidden";
  await s.tick();
  assert.equal(calls, 1);
  s.document.visibilityState = "visible";
  await s.tick();
  assert.equal(calls, 2);
  await s.controller.check();
  assert.equal(calls, 3);
});

test("failed or malicious response does not hide a known update or claim up-to-date; failures retry", async () => {
  let result = newer;
  let calls = 0;
  const s = setup(async () => { calls++; if (!result) throw Error("offline"); return result; });
  await settle();
  result = { ...newer, releaseURL: "https://evil.example/" };
  await s.controller.check();
  assert.equal(s.nodes.get("containerUpdateBanner").hidden, false);
  assert.equal(s.nodes.get("containerUpdateLink").href, newer.releaseURL);
  assert.match(s.nodes.get("containerUpdateStatus").textContent, /失败/);
  assert.equal(s.nodes.get("checkContainerUpdatesButton").disabled, false);
  result = null;
  s.advance(s.api.RETRY_INTERVAL_MS);
  await s.tick();
  assert.equal(calls, 3);
});

test("equal version clears reminder and duplicate in-flight checks are ignored", async () => {
  let complete;
  let calls = 0;
  const s = setup(() => { calls++; return new Promise(resolve => { complete = resolve; }); });
  await s.controller.check();
  assert.equal(calls, 1);
  complete({ ...newer, currentVersion: "1.4.1", updateAvailable: false });
  await settle();
  assert.equal(s.nodes.get("containerUpdateBanner").hidden, true);
  assert.equal(s.nodes.get("containerUpdateStatus").textContent, "Container 已是最新版本");
});
