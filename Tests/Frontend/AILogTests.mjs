import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const script = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/ai-logs.js", import.meta.url), "utf8");
const i18nScript = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/i18n.js", import.meta.url), "utf8");

function status(overrides = {}) {
  return {
    enabled: false, phase: "off", containerId: null, language: "zh", workerPID: null,
    error: null, result: null,
    model: { name: "Qwen3-1.7B", installed: true, downloading: false, downloadedBytes: 0, totalBytes: 1_750_000_000 },
    ...overrides
  };
}

function deferred() {
  let resolve;
  const promise = new Promise((yes) => { resolve = yes; });
  return { promise, resolve };
}

async function settle() {
  for (let index = 0; index < 20; index += 1) await Promise.resolve();
}

function fixture(initial = status()) {
  const requests = [];
  const timers = new Map();
  const listeners = new Map();
  const nodes = new Map();
  let timerID = 0;
  let now = 0;
  let snapshot = initial;
  let responder = async () => snapshot;
  const i18n = runInNewContext(`${i18nScript}; ContainerGUII18n`);
  const document = {
    visibilityState: "visible",
    getElementById(id) {
      if (!nodes.has(id)) nodes.set(id, {
        textContent: "", hidden: false, disabled: false, dataset: {}, attributes: {}, handlers: {},
        setAttribute(name, value) { this.attributes[name] = value; },
        removeAttribute(name) { delete this.attributes[name]; },
        addEventListener(name, callback) { this.handlers[name] = callback; },
        set innerHTML(_) { throw new Error("AI data must not be rendered as HTML"); }
      });
      return nodes.get(id);
    },
    addEventListener(name, callback) { listeners.set(name, callback); }
  };
  const context = {
    document, ContainerGUII18n: i18n, AbortController, Date: { now: () => now },
    setTimeout(callback, delay) { const id = ++timerID; timers.set(id, { callback, delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    addEventListener(name, callback) { listeners.set(name, callback); },
    async fetch(url, options = {}) {
      const request = { url, ...options, body: options.body ? JSON.parse(options.body) : undefined };
      requests.push(request);
      const value = await responder(request);
      return value?.problem
        ? { ok: false, status: value.status, json: async () => value.problem }
        : { ok: true, status: 200, json: async () => value };
    }
  };
  const api = runInNewContext(`${script}; globalThis.ContainerGUIAILogs`, context);
  return {
    api, requests, document, nodes, i18n,
    setStatus(value) { snapshot = value; },
    respond(callback) { responder = callback; },
    node(id) { return document.getElementById(id); },
    async click(id) { document.getElementById(id).handlers.click(); await settle(); },
    async event(name) { listeners.get(name)?.(); await settle(); },
    async tick(milliseconds = 1500) {
      now += milliseconds;
      const entry = [...timers.entries()].find(([, timer]) => timer.delay <= 1500);
      if (entry) { timers.delete(entry[0]); entry[1].callback(); }
      await settle();
    }
  };
}

test("selection is passive and first download requires confirmation with the backend size", async () => {
  const model = { name: "Qwen3-1.7B", installed: false, downloading: false, downloadedBytes: 0, totalBytes: 1_750_000_000 };
  const f = fixture(status({ model }));
  await f.api.setContainer("demo");
  assert.deepEqual(f.requests.map((request) => request.url), ["/api/v1/ai/logs/status"]);
  await f.click("aiLogsToggle");
  assert.equal(f.node("aiLogsConsent").hidden, false);
  assert.match(f.node("aiLogsDownloadSize").textContent, /1\.75 GB/);
  assert.equal(f.requests.filter((request) => request.method === "POST").length, 0);
  await f.tick(20_000);
  assert.equal(f.requests.length, 1, "Unconfirmed download consent does not start polling");
  await f.click("aiLogsCancelDownload");
  assert.equal(f.node("aiLogsConsent").hidden, true);
  assert.equal(f.requests.filter((request) => request.method === "POST").length, 0);
  await f.click("aiLogsToggle");
  f.setStatus(status({ phase: "downloading", model: { ...model, downloading: true, downloadedBytes: 350_000_000 } }));
  await f.click("aiLogsConfirmDownload");
  assert.equal(f.requests.at(-1).url, "/api/v1/ai/logs/install");
  assert.deepEqual(f.requests.at(-1).body, { confirmed: true });
  assert.equal(f.node("aiLogsProgress").value, 350_000_000);
  assert.equal(f.node("aiLogsToggle").disabled, false);
});

test("disable wins over a late enable response and never starts stale analysis", async () => {
  const f = fixture();
  await f.api.setContainer("first");
  const pending = deferred();
  f.respond((request) => request.url.endsWith("/enable") ? pending.promise : status());
  await f.click("aiLogsToggle");
  assert.equal(f.node("aiLogsToggle").disabled, false);
  await f.click("aiLogsToggle");
  pending.resolve(status({ enabled: true, phase: "ready", containerId: "first", workerPID: 123 }));
  await settle();
  assert.equal(f.node("aiLogsToggle").attributes["aria-checked"], "false");
  assert.equal(f.node("aiLogsResult").hidden, true);
  assert.equal(f.requests.some((request) => /\/(analyse|heartbeat)$/.test(request.url)), false);
});

test("late status for a previous selection cannot replace the current panel", async () => {
  const f = fixture();
  const pending = deferred();
  f.respond(() => pending.promise);
  const first = f.api.setContainer("first");
  f.respond(() => status());
  await f.api.setContainer("second");
  pending.resolve(status({ enabled: true, phase: "analysing", containerId: "first", workerPID: 123 }));
  await first;
  assert.equal(f.node("aiLogsToggle").attributes["aria-checked"], "false");
  assert.equal(f.node("aiLogsTarget").hidden, true);
});

test("failed shutdown stays unverified and its switch permits retry", async () => {
  const active = status({ enabled: true, phase: "analysing", containerId: "demo", workerPID: 123 });
  const f = fixture(active);
  await f.api.setContainer("demo");
  f.respond(() => ({ status: 503, problem: { message: "worker_stop_failed", code: "SERVICE_UNAVAILABLE" } }));
  await f.click("aiLogsToggle");
  assert.match(f.node("aiLogsError").textContent, /未确认释放/);
  assert.equal(f.node("aiLogsToggle").attributes["aria-checked"], "true");
  assert.equal(f.node("aiLogsToggle").disabled, false);
  f.respond(() => status());
  await f.click("aiLogsToggle");
  assert.equal(f.node("aiLogsToggle").attributes["aria-checked"], "false");
  assert.equal(f.node("aiLogsError").hidden, true);
});

test("results and evidence remain literal text and a different global target is not adopted", async () => {
  const result = { text: "<img src=x onerror=alert(1)>\nPossible cause", evidence: "<script>restart()</script>", observedAt: "2026-09-08T10:00:00Z", elapsedSeconds: 1 };
  const f = fixture(status({ enabled: true, phase: "ready", containerId: "other", result }));
  await f.api.setContainer("demo");
  assert.equal(f.node("aiLogsResult").hidden, true);
  assert.match(f.node("aiLogsTarget").textContent, /other/);
  await f.tick(15_000);
  assert.equal(f.requests.some((request) => /\/(enable|analyse|heartbeat)$/.test(request.url)), false);
  await f.api.setContainer("other");
  assert.equal(f.node("aiLogsAnswer").textContent, result.text);
  assert.equal(f.node("aiLogsEvidence").textContent, result.evidence);
});

test("Chinese and English controls translate and explicit enable passes the chosen language", async () => {
  const f = fixture();
  await f.api.setContainer("demo");
  f.i18n.setLanguage("en");
  f.api.languageChanged();
  assert.equal(f.node("aiLogsToggleLabel").textContent, "Enable AI");
  assert.match(f.node("aiLogsPrivacy").textContent, /not uploaded/);
  f.respond(() => status({ enabled: true, phase: "loading", containerId: "demo", language: "en" }));
  await f.click("aiLogsToggle");
  assert.deepEqual(f.requests.find((request) => request.url.endsWith("/enable")).body, { containerId: "demo", language: "en" });
  f.i18n.setLanguage("zh");
  f.api.languageChanged();
  assert.match(f.node("aiLogsStatus").textContent, /加载/);
});

test("owned visible sessions analyse bounded batches and hidden/pagehide release via keepalive", async () => {
  const f = fixture();
  await f.api.setContainer("demo");
  f.respond((request) => request.url.endsWith("/disable") ? status() : status({ enabled: true, phase: "ready", containerId: "demo" }));
  await f.click("aiLogsToggle");
  await f.tick(1500);
  assert.equal(f.requests.filter((request) => request.url.endsWith("/analyse")).length, 1);
  await f.tick(10_000);
  assert.equal(f.requests.filter((request) => request.url.endsWith("/heartbeat")).length, 1);
  f.document.visibilityState = "hidden";
  await f.event("visibilitychange");
  assert.equal(f.requests.at(-1).url, "/api/v1/ai/logs/disable");
  assert.equal(f.requests.at(-1).keepalive, true);
  const count = f.requests.length;
  await f.tick(20_000);
  assert.equal(f.requests.length, count);
});

test("a failed install permits an explicit retry but never loops downloads automatically", async () => {
  const model = { name: "Qwen3-1.7B", installed: false, downloading: false, downloadedBytes: 0, totalBytes: 1000 };
  const f = fixture(status({ model }));
  await f.api.setContainer("demo");
  await f.click("aiLogsToggle");
  f.respond(() => ({ status: 503, problem: { message: "ai_model_download_failed" } }));
  await f.click("aiLogsConfirmDownload");
  assert.equal(f.node("aiLogsConsent").hidden, false);
  assert.equal(f.node("aiLogsConfirmDownload").disabled, false);
  await f.tick(20_000);
  assert.equal(f.requests.filter((request) => request.url.endsWith("/install")).length, 1);
});

test("a global disable from another window never causes the owning page to re-enable", async () => {
  const f = fixture();
  await f.api.setContainer("demo");
  f.respond(() => status({ enabled: true, phase: "loading", containerId: "demo" }));
  await f.click("aiLogsToggle");
  f.respond(() => status());
  await f.tick(1500);
  assert.equal(f.node("aiLogsToggle").attributes["aria-checked"], "false");
  assert.equal(f.requests.filter((request) => request.url.endsWith("/enable")).length, 1);
});

test("switching containers during unconfirmed consent does not send a global disable", async () => {
  const f = fixture(status({ model: { name: "Qwen3-1.7B", installed: false, downloading: false, totalBytes: 1000 } }));
  await f.api.setContainer("first");
  await f.click("aiLogsToggle");
  await f.api.setContainer("second");
  assert.equal(f.requests.some((request) => request.method === "POST"), false);
  assert.equal(f.node("aiLogsConsent").hidden, true);
});

test("a confirmed completed download enables once, while a cancelled late install cannot enable", async () => {
  const model = { name: "Qwen3-1.7B", installed: false, downloading: false, totalBytes: 1000 };
  for (const cancel of [false, true]) {
    const f = fixture(status({ model }));
    await f.api.setContainer("demo");
    await f.click("aiLogsToggle");
    const pending = deferred();
    f.respond((request) => request.url.endsWith("/install") ? pending.promise : status());
    await f.click("aiLogsConfirmDownload");
    if (cancel) await f.click("aiLogsToggle");
    pending.resolve(status());
    await settle();
    assert.equal(f.requests.filter((request) => request.url.endsWith("/enable")).length, cancel ? 0 : 1);
  }
});

test("slow analysis requests do not overlap and changing the selection shuts down the owned session", async () => {
  const f = fixture();
  const active = status({ enabled: true, phase: "ready", containerId: "first" });
  await f.api.setContainer("first");
  const pending = deferred();
  f.respond((request) => request.url.endsWith("/analyse") ? pending.promise : request.url.endsWith("/disable") ? status() : active);
  await f.click("aiLogsToggle");
  await f.tick(1500);
  await f.tick(20_000);
  assert.equal(f.requests.filter((request) => request.url.endsWith("/analyse")).length, 1);
  f.respond(() => status());
  await f.api.setContainer("second");
  pending.resolve({ ...active, result: { text: "stale answer", evidence: "old log" } });
  await settle();
  assert.equal(f.requests.filter((request) => request.url.endsWith("/disable")).length, 1);
  assert.equal(f.node("aiLogsResult").hidden, true);
});

test("a visible owned download renews its lease before AI is enabled", async () => {
  const model = { name: "Qwen3-1.7B", installed: false, downloading: false, downloadedBytes: 0, totalBytes: 1_750_000_000 };
  const f = fixture(status({ model }));
  await f.api.setContainer("demo");
  await f.click("aiLogsToggle");
  f.setStatus(status({ phase: "downloading", model: { ...model, downloading: true } }));
  await f.click("aiLogsConfirmDownload");
  for (let index = 0; index < 7; index += 1) await f.tick(10_000);
  assert.equal(f.requests.filter((request) => request.url.endsWith("/heartbeat")).length, 7);
  assert.equal(f.requests.some((request) => request.url.endsWith("/analyse")), false);
  f.document.visibilityState = "hidden";
  f.setStatus(status({ model }));
  await f.event("visibilitychange");
  assert.equal(f.requests.at(-1).url, "/api/v1/ai/logs/disable");
});

test("accepted download keeps polling before the model store reports downloading", async () => {
  const model = { name: "Qwen3-1.7B", installed: false, downloading: false, downloadedBytes: 0, totalBytes: 1_750_000_000 };
  const f = fixture(status({ model }));
  await f.api.setContainer("demo");
  await f.click("aiLogsToggle");
  f.setStatus(status({ phase: "downloading", model }));
  await f.click("aiLogsConfirmDownload");
  const before = f.requests.length;
  f.setStatus(status({ phase: "downloading", model: { ...model, downloading: true, downloadedBytes: 100_000_000 } }));
  await f.tick(1500);
  assert.equal(f.requests.length, before + 1);
  assert.equal(f.requests.at(-1).url, "/api/v1/ai/logs/status");
  assert.equal(f.node("aiLogsProgress").hidden, false);
  assert.equal(f.node("aiLogsProgress").value, 100_000_000);
  await f.tick(10_000);
  assert.equal(f.requests.at(-1).url, "/api/v1/ai/logs/heartbeat");
});

test("a terminal off status after download clears pending enable when the model is absent", async () => {
  const model = { name: "Qwen3-1.7B", installed: false, downloading: false, downloadedBytes: 0, totalBytes: 1_750_000_000 };
  const f = fixture(status({ model }));
  await f.api.setContainer("demo");
  await f.click("aiLogsToggle");
  f.setStatus(status({ phase: "downloading", model: { ...model, downloading: true } }));
  await f.click("aiLogsConfirmDownload");
  f.setStatus(status({ model }));
  await f.tick(1500);
  assert.equal(f.node("aiLogsToggle").attributes["aria-checked"], "false");
  assert.equal(f.node("aiLogsConsent").hidden, true);
  assert.equal(f.requests.some((request) => request.url.endsWith("/enable")), false);
  const count = f.requests.length;
  await f.tick(20_000);
  assert.equal(f.requests.length, count);
});

test("HTTP problems decode message and retain a localizable specific failure", async () => {
  const f = fixture();
  await f.api.setContainer("demo");
  f.respond((request) => request.url.endsWith("/enable")
    ? { status: 503, problem: { code: "SERVICE_UNAVAILABLE", message: "insufficient_memory", detail: "Wrong field" } }
    : status());
  await f.click("aiLogsToggle");
  assert.equal(f.node("aiLogsError").textContent, "可用内存不足，请关闭部分应用后重试。");
  f.i18n.setLanguage("en");
  f.api.languageChanged();
  assert.equal(f.node("aiLogsError").textContent, "Not enough available memory. Close some apps and try again.");
  f.i18n.setLanguage("zh");
  f.api.languageChanged();
  assert.equal(f.node("aiLogsError").textContent, "可用内存不足，请关闭部分应用后重试。");
});

test("known safe status codes have Chinese and English descriptions", async () => {
  for (const [code, zh, en] of [
    ["no_recent_logs", "暂无最近日志可供分析。", "There are no recent logs to analyse."],
    ["worker_stop_failed", "关闭失败，尚未确认释放；请重试关闭。", "Shutdown failed; release is not verified. Try turning AI off again."],
    ["ai_model_insufficient_disk_space", "磁盘空间不足，无法下载模型。", "There is not enough disk space to download the model."],
    ["ai_model_not_installed", "模型尚未安装，请确认下载后重试。", "The model is not installed. Confirm its download and try again."],
    ["ai_model_verification_failed", "模型文件校验失败，请重新下载。", "Model verification failed. Download the model again."],
    ["ai_model_download_failed", "模型下载失败，请检查网络后重试。", "The model download failed. Check your connection and try again."],
    ["ai_model_unsafe_directory", "模型目录不符合安全要求，请检查本机模型目录。", "The model directory failed safety checks. Check the local model directory."],
    ["ai_model_invalid_manifest", "模型清单无效，请更新应用后重试。", "The model manifest is invalid. Update the app and try again."]
  ]) {
    const f = fixture(status({ phase: "error", error: code }));
    await f.api.setContainer("demo");
    assert.equal(f.node("aiLogsError").textContent, zh, code);
    f.i18n.setLanguage("en");
    f.api.languageChanged();
    assert.equal(f.node("aiLogsError").textContent, en, code);
  }
});

test("HTTP conflict and missing error messages keep safe localized fallback text", async () => {
  const f = fixture();
  await f.api.setContainer("demo");
  f.i18n.setLanguage("en");
  f.respond((request) => request.url.endsWith("/enable") ? { status: 409, problem: { code: "OPERATION_IN_PROGRESS" } } : status());
  await f.click("aiLogsToggle");
  assert.equal(f.node("aiLogsError").textContent, "Another AI operation is in progress. Check the current status.");
});
