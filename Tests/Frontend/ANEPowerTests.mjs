import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const publicDirectory = new URL("../../Sources/ContainerGUI/Resources/Public/", import.meta.url);
const script = readFileSync(new URL("app.js", publicDirectory), "utf8");
const html = readFileSync(new URL("index.html", publicDirectory), "utf8");
const i18nScript = readFileSync(new URL("i18n.js", publicDirectory), "utf8");

function functionSource(name) {
  const match = script.match(new RegExp(`(?:async )?function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
  assert.ok(match, `${name} must be defined`);
  return match[0];
}

function snapshot(overrides = {}) {
  return {
    state: "ready", watts: 2.5, observedAt: "2026-09-08T00:00:00Z", sampleSeconds: 5,
    reason: null, scope: "host", estimated: true, utilizationPercent: null,
    utilizationState: "unavailable", ...overrides
  };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

async function settle() {
  for (let index = 0; index < 15; index += 1) await Promise.resolve();
}

function fixture() {
  const i18n = runInNewContext(`${i18nScript}; ContainerGUII18n`);
  let language = "zh";
  let responder = async () => snapshot();
  let timerID = 0;
  const requests = [];
  const timers = new Map();
  const elements = Object.fromEntries([
    "anePowerStatus", "anePowerValue", "anePowerWindow", "aneUtilizationValue"
  ].map((id) => [id, {
    textContent: "",
    set innerHTML(_) { throw new Error("ANE data must be rendered as plain text"); }
  }]));
  const context = {
    AbortController, Date, Number,
    state: { activeView: "containers", aneSnapshot: null, aneStatus: "sampling", aneController: null, aneRequestID: 0 },
    elements, document: { visibilityState: "visible" },
    ENDPOINTS: { ane: "/api/v1/system/ane" },
    ContainerGUII18n: { language: () => language, translate: (text) => i18n.translate(text, language) },
    formatTime: () => "09:00:00",
    fetchJSON: (url, options) => { requests.push({ url, options }); return responder(url, options); },
    setTimeout(callback, delay) { const id = ++timerID; timers.set(id, { callback, delay }); return id; },
    clearTimeout(id) { timers.delete(id); }
  };
  const names = ["anePowerSnapshot", "renderANEPower", "resetANEPower", "refreshANEPower"];
  const functions = runInNewContext(`${names.map(functionSource).join("\n")}; ({ ${names.join(", ")} })`, context);
  Object.assign(context, functions);
  return {
    ...functions, context, elements, requests, timers,
    respondWith(value) { responder = typeof value === "function" ? value : async () => value; },
    setLanguage(value) { language = value; }
  };
}

test("ANE is a separate whole-host estimated-power region with no utilization meter", () => {
  const section = html.match(/<section\b[^>]*id="anePowerSection"[\s\S]*?<\/section>/)?.[0];
  assert.ok(section, "independent ANE section must exist");
  for (const text of ["整机 ANE", "估算功耗", "计算使用率", "不可用", "非 Container GUI 专属", "功耗不是计算使用率"]) {
    assert.ok(section.includes(text), `missing scope or metric copy: ${text}`);
  }
  assert.match(section, /aria-labelledby="anePowerTitle"/);
  assert.match(section, /aria-describedby="anePowerNote"/);
  assert.doesNotMatch(section, /<meter|<progress|%/);
  assert.match(script, /ane: "\/api\/v1\/system\/ane"/);
});

test("ready watts, a valid zero and sampling never imply a utilization percentage", async () => {
  const f = fixture();
  await f.refreshANEPower();
  assert.equal(f.elements.anePowerValue.textContent, "2.50 W");
  assert.equal(f.elements.anePowerWindow.textContent, "采样窗口 5.0 秒");
  assert.equal(f.elements.anePowerStatus.textContent, "已更新 09:00:00");
  assert.equal(f.elements.aneUtilizationValue.textContent, "不可用");
  f.respondWith(snapshot({ watts: 0 }));
  await f.refreshANEPower();
  assert.equal(f.elements.anePowerValue.textContent, "0.00 W");
  f.respondWith(snapshot({ state: "sampling", watts: null, sampleSeconds: null }));
  await f.refreshANEPower();
  assert.equal(f.elements.anePowerValue.textContent, "采样中");
  assert.equal(f.elements.anePowerWindow.textContent, "等待两次有效采样");
  assert.equal(f.elements.aneUtilizationValue.textContent, "不可用");
});

test("malformed or misleading snapshots are rejected and erase the last power value", async () => {
  const f = fixture();
  const bad = [null, {}, [], snapshot({ watts: -1 }), snapshot({ watts: NaN }), snapshot({ watts: Infinity }),
    snapshot({ watts: "2.5" }), snapshot({ sampleSeconds: 0 }), snapshot({ sampleSeconds: Infinity }),
    snapshot({ sampleSeconds: null }), snapshot({ observedAt: "invalid" }), snapshot({ observedAt: null }),
    snapshot({ scope: "gui" }), snapshot({ estimated: false }), snapshot({ utilizationPercent: 50 }),
    snapshot({ utilizationState: "ready" }), snapshot({ state: "other" }), snapshot({ reason: "read_failed" }),
    snapshot({ state: "sampling" }), snapshot({ state: "unavailable", watts: null, sampleSeconds: null, reason: "<img src=x>" })];
  for (const value of bad) {
    f.respondWith(snapshot());
    await f.refreshANEPower();
    f.respondWith(value);
    await f.refreshANEPower();
    assert.equal(f.context.state.aneSnapshot, null, JSON.stringify(value));
    assert.equal(f.elements.anePowerValue.textContent, "暂不可用");
    assert.doesNotMatch(f.elements.anePowerStatus.textContent, /<img|2\.50/);
    assert.doesNotMatch(f.elements.anePowerWindow.textContent, /5\.0/);
  }
});

test("HTTP errors clear old watts without rendering an arbitrary server error", async () => {
  const f = fixture();
  await f.refreshANEPower();
  f.respondWith(async () => { throw new Error("<script>hostile</script>"); });
  await f.refreshANEPower();
  assert.equal(f.context.state.aneSnapshot, null);
  assert.equal(f.elements.anePowerValue.textContent, "暂不可用");
  assert.equal(f.elements.anePowerStatus.textContent, "暂时无法读取 ANE 指标");
  assert.equal(f.timers.size, 0);
  f.respondWith(snapshot());
  await f.refreshANEPower();
  assert.equal(f.elements.anePowerValue.textContent, "2.50 W");
});

test("finite unavailable reasons and dynamic labels are translated in both languages", async () => {
  const f = fixture();
  const reasons = [
    ["unsupported", "此系统暂不支持 ANE 功耗读取", "ANE power readings are not supported on this system"],
    ["read_failed", "暂时无法读取 ANE 指标", "Unable to read ANE metrics right now"],
    ["invalid_sample", "ANE 样本无效，等待重新采样", "Invalid ANE sample; waiting for a new sample"]
  ];
  for (const [reason, zh, en] of reasons) {
    f.setLanguage("zh");
    f.respondWith(snapshot({ state: "unavailable", watts: null, sampleSeconds: null, reason }));
    await f.refreshANEPower();
    assert.equal(f.elements.anePowerStatus.textContent, zh);
    f.setLanguage("en");
    f.renderANEPower();
    assert.equal(f.elements.anePowerStatus.textContent, en);
    assert.equal(f.elements.aneUtilizationValue.textContent, "Unavailable");
  }
  f.respondWith(snapshot());
  await f.refreshANEPower();
  assert.equal(f.elements.anePowerWindow.textContent, "Sample window 5.0 s");
  assert.equal(f.elements.anePowerStatus.textContent, "Updated 09:00:00");
  f.setLanguage("zh");
  f.renderANEPower();
  assert.equal(f.elements.anePowerWindow.textContent, "采样窗口 5.0 秒");
  const i18n = runInNewContext(`${i18nScript}; ContainerGUII18n`);
  assert.equal(i18n.translate("整机 ANE", "en"), "Host ANE");
  assert.equal(i18n.translate("估算功耗", "en"), "Estimated power");
  assert.equal(i18n.translate("功耗不是计算使用率", "en"), "Power is not compute utilization");
});

test("hidden and non-container views never request ANE data or start AI", async () => {
  const f = fixture();
  for (const [visibilityState, activeView] of [["hidden", "containers"], ["visible", "images"], ["visible", "registry"]]) {
    Object.assign(f.context.document, { visibilityState });
    Object.assign(f.context.state, { activeView });
    await f.refreshANEPower();
  }
  assert.equal(f.requests.length, 0);
  Object.assign(f.context.document, { visibilityState: "visible" });
  Object.assign(f.context.state, { activeView: "containers", containers: [], containersLoaded: false });
  await f.refreshANEPower();
  assert.equal(f.elements.anePowerValue.textContent, "2.50 W");
  assert.deepEqual(f.requests.map((request) => request.url), ["/api/v1/system/ane"]);
});

test("an in-flight read is coalesced and late pre-hide responses cannot restore watts", async () => {
  const f = fixture();
  const old = deferred();
  f.respondWith(() => old.promise);
  const first = f.refreshANEPower();
  await f.refreshANEPower();
  assert.equal(f.requests.length, 1);
  f.resetANEPower();
  assert.equal(f.requests[0].options.signal.aborted, true);
  assert.equal(f.elements.anePowerValue.textContent, "采样中");
  f.respondWith(snapshot({ state: "sampling", watts: null, sampleSeconds: null }));
  await f.refreshANEPower();
  old.resolve(snapshot({ watts: 8 }));
  await first;
  assert.equal(f.elements.anePowerValue.textContent, "采样中");
  assert.equal(f.context.state.aneSnapshot.state, "sampling");
});

test("bounded request timeout clears a stale value and allows the next refresh", async () => {
  const f = fixture();
  await f.refreshANEPower();
  f.respondWith((_, { signal }) => new Promise((resolve, reject) => {
    signal.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
  }));
  const request = f.refreshANEPower();
  const timeout = [...f.timers.values()][0];
  assert.ok(timeout.delay > 0 && timeout.delay <= 5000);
  timeout.callback();
  await request;
  assert.equal(f.elements.anePowerValue.textContent, "暂不可用");
  assert.equal(f.context.state.aneController, null);
  f.respondWith(snapshot());
  await f.refreshANEPower();
  assert.equal(f.elements.anePowerValue.textContent, "2.50 W");
});

test("dashboard starts ANE independently even while a previous CLI refresh is busy", async () => {
  const f = fixture();
  f.context.state.refreshing = true;
  const refresh = runInNewContext(`${functionSource("refreshDashboard")}; refreshDashboard`, f.context);
  await refresh();
  await settle();
  assert.equal(f.requests.length, 1);
  assert.equal(f.elements.anePowerValue.textContent, "2.50 W");
});

test("failed health, list and container metrics requests do not discard successful ANE data", async () => {
  const f = fixture();
  const aneFetch = f.context.fetchJSON;
  f.context.fetchJSON = (url, options) => url === f.context.ENDPOINTS.ane
    ? aneFetch(url, options) : Promise.reject(new Error("CLI unavailable"));
  Object.assign(f.context.ENDPOINTS, { metrics: "metrics", health: "health", containers: "containers" });
  Object.assign(f.context.state, { containers: [], selectedID: null });
  Object.assign(f.context.elements, {
    loadingState: {}, healthCard: { dataset: {}, setAttribute() {}, querySelector: () => ({}) },
    healthLabel: {}, healthDetail: {}
  });
  f.context.document.documentElement = { dataset: {} };
  Object.assign(f.context, {
    loadImages: async () => false,
    setBusy: (value) => { f.context.state.refreshing = value; },
    renderSystemStart() {}, showListError() {}, renderHostUsage() {}
  });
  await runInNewContext(`${functionSource("refreshDashboard")}; refreshDashboard`, f.context)();
  await settle();
  assert.equal(f.context.state.metricsSnapshot, null);
  assert.equal(f.context.state.metricsStatus, "error");
  assert.equal(f.context.state.containersLoaded, false);
  assert.equal(f.elements.anePowerValue.textContent, "2.50 W");
});

test("old success and failure cannot unlock or overwrite a newer in-flight sample", async () => {
  for (const fails of [false, true]) {
    const f = fixture();
    const old = deferred();
    const current = deferred();
    f.respondWith(() => old.promise);
    const oldRequest = f.refreshANEPower();
    f.resetANEPower();
    f.respondWith(() => current.promise);
    const currentRequest = f.refreshANEPower();
    const currentController = f.context.state.aneController;
    if (fails) old.reject(new Error("old request failed"));
    else old.resolve(snapshot({ watts: 8 }));
    await oldRequest;
    assert.equal(f.context.state.aneController, currentController);
    assert.equal(f.context.state.aneSnapshot, null);
    await f.refreshANEPower();
    assert.equal(f.requests.length, 2);
    current.resolve(snapshot({ watts: 3 }));
    await currentRequest;
    assert.equal(f.elements.anePowerValue.textContent, "3.00 W");
  }
});

test("view and visibility hooks clear stale readings and request fresh data on return", async () => {
  const f = fixture();
  await f.refreshANEPower();
  const events = new Map();
  f.context.window = {
    addEventListener: (name, handler) => events.set(name, handler),
    scrollTo() {}
  };
  f.context.document.addEventListener = (name, handler) => events.set(name, handler);
  f.context.elements.pageTitle = { focus() {} };
  f.context.renderWorkspace = () => {};
  f.context.refreshDashboard = () => f.refreshANEPower();
  for (const [owner, name] of [["window", "hashchange"], ["document", "visibilitychange"]]) {
    const match = script.match(new RegExp(`${owner}\\.addEventListener\\("${name}", \\(\\) => \\{[\\s\\S]*?\\n\\}\\);`));
    assert.ok(match);
    runInNewContext(match[0], f.context);
  }
  f.context.state.activeView = "images";
  events.get("hashchange")();
  assert.equal(f.context.state.aneSnapshot, null);
  assert.equal(f.requests.length, 1);
  f.context.state.activeView = "containers";
  events.get("hashchange")();
  await settle();
  assert.equal(f.requests.length, 2);
  f.context.document.visibilityState = "hidden";
  events.get("visibilitychange")();
  assert.equal(f.context.state.aneSnapshot, null);
  assert.equal(f.requests.length, 2);
  f.context.document.visibilityState = "visible";
  events.get("visibilitychange")();
  await settle();
  assert.equal(f.requests.length, 3);
  assert.equal(f.elements.anePowerValue.textContent, "2.50 W");
});
