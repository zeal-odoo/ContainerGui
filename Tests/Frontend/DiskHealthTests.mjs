import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/disk-health.js", import.meta.url), "utf8");
const tick = () => new Promise((resolve) => setImmediate(resolve));

function setup(request) {
  const node = () => ({
    textContent: "", children: [], dataset: {}, hidden: false, disabled: false, events: {},
    append(...children) { this.children.push(...children); },
    replaceChildren(...children) { this.children = children; },
    setAttribute(name, value) { this[name] = value; },
    addEventListener(event, callback) { this.events[event] = callback; }
  });
  const elements = Object.fromEntries(["diskHealthSection", "diskHealthCards", "diskHealthStatus", "diskHealthError", "diskHealthEmpty", "refreshDisksButton", "diskTotalCount", "diskPassedCount", "diskAttentionCount", "diskUnknownCount"].map((id) => [id, node()]));
  const document = { visibilityState: "visible", createElement: node, getElementById: (id) => elements[id], events: {}, addEventListener(event, callback) { this.events[event] = callback; } };
  const intervals = [];
  const timeouts = [];
  const window = { addEventListener() {}, setInterval(callback, delay) { intervals.push({ callback, delay }); }, setTimeout(callback) { timeouts.push(callback); return timeouts.length; }, clearTimeout() {} };
  const api = runInNewContext(`${source}; ContainerGUIDiskHealth`, { document, window, AbortController });
  const monitor = api.start(request, (value) => value == null ? "—" : String(value));
  return { api, monitor, elements, document, intervals, timeouts };
}

const healthy = (disks = [{ id: "disk6", model: "<img onerror=bad()>", health: "passed", source: "smartctl", capacityBytes: 2000, spaces: [{ names: ["External"], freeBytes: 50, totalBytes: 1000, shared: true }] }]) => ({ disks, observedAt: "2026-11-26T06:00:00Z" });
const text = (node) => [node.textContent, ...node.children.map(text)].join(" ");

test("disk polling starts only in its visible view and refreshes every five seconds", async () => {
  let calls = 0;
  const fixture = setup(async () => { calls++; return healthy(); });
  assert.equal(fixture.intervals[0].delay, 5000);
  await fixture.intervals[0].callback();
  assert.equal(calls, 0);
  fixture.monitor.setActive(true); await tick();
  assert.equal(calls, 1);
  await fixture.intervals[0].callback(); assert.equal(calls, 2);
  fixture.document.visibilityState = "hidden"; fixture.document.events.visibilitychange();
  await fixture.intervals[0].callback(); assert.equal(calls, 2);
  fixture.document.visibilityState = "visible"; fixture.document.events.visibilitychange(); await tick();
  assert.equal(calls, 3);
  fixture.monitor.setActive(false); await fixture.intervals[0].callback(); assert.equal(calls, 3);
});

test("failures remove old healthy cards and retain only the previous successful time", async () => {
  let fail = false;
  const f = setup(async () => { if (fail) throw new Error("offline"); return healthy(); });
  f.monitor.setActive(true); await tick();
  assert.equal(f.elements.diskPassedCount.textContent, "1");
  assert.ok(text(f.elements.diskHealthCards).includes("健康检查通过"));
  assert.ok(text(f.elements.diskHealthCards).includes("可用空间不足 10%"));
  assert.ok(text(f.elements.diskHealthCards).includes("<img onerror=bad()>"));
  fail = true; await f.monitor.refresh();
  assert.equal(f.elements.diskHealthCards.children.length, 0);
  assert.equal(f.elements.diskPassedCount.textContent, "—");
  assert.equal(f.elements.diskHealthError.hidden, false);
  assert.ok(text(f.elements.diskHealthStatus).includes("本次检测失败"));
  assert.ok(text(f.elements.diskHealthStatus).includes("上次成功检测"));
  fail = false; await f.monitor.refresh();
  assert.equal(f.elements.diskHealthError.hidden, true);
  assert.equal(f.elements.diskHealthCards.children.length, 1);
});

test("unplugging a disk removes it and unsupported disks remain unknown", async () => {
  let result = healthy([{ id: "disk8", model: "USB", health: "unavailable", reason: "tool_unavailable", spaces: [] }]);
  const f = setup(async () => result);
  f.monitor.setActive(true); await tick();
  assert.equal(f.elements.diskUnknownCount.textContent, "1");
  assert.equal(f.elements.diskPassedCount.textContent, "0");
  assert.ok(text(f.elements.diskHealthCards).includes("smartmontools"));
  result = healthy([]); await f.monitor.refresh();
  assert.equal(f.elements.diskHealthCards.children.length, 0);
  assert.equal(f.elements.diskHealthEmpty.hidden, false);
});

test("late responses from a hidden view cannot overwrite a newer reading", async () => {
  const pending = [];
  const f = setup(() => new Promise((resolve) => pending.push(resolve)));
  f.monitor.setActive(true);
  f.monitor.setActive(false);
  f.monitor.setActive(true);
  assert.equal(pending.length, 2);
  pending[1](healthy([])); await tick();
  pending[0](healthy()); await tick();
  assert.equal(f.elements.diskTotalCount.textContent, "0");
  assert.equal(f.elements.refreshDisksButton.disabled, false);
});

test("overlapping requests are suppressed and timeouts clear old data", async () => {
  let calls = 0;
  const f = setup((_, options) => {
    calls++;
    return new Promise((resolve, reject) => options.signal.addEventListener("abort", () => reject(new Error("timeout"))));
  });
  f.monitor.setActive(true); await f.monitor.refresh();
  assert.equal(calls, 1);
  f.timeouts[0](); await tick();
  assert.equal(f.elements.diskHealthError.hidden, false);
  assert.equal(f.elements.refreshDisksButton.disabled, false);
});

test("unknown or malformed health states are rejected and low space is separate", () => {
  const { api } = setup(async () => healthy());
  assert.equal(api.validSnapshot(healthy()), true);
  assert.equal(api.validSnapshot({ ...healthy(), error: "read_failed" }), false);
  assert.equal(api.validSnapshot({ ...healthy(), observedAt: "invalid" }), false);
  assert.equal(api.validSnapshot(healthy([{ id: "disk0", model: "SSD", health: "__proto__", spaces: [] }])), false);
  assert.equal(api.lowSpace({ totalBytes: 100, freeBytes: 9 }), true);
  assert.equal(api.lowSpace({ totalBytes: 100, freeBytes: 10 }), false);
  assert.equal(api.lowSpace({ totalBytes: 100, freeBytes: null }), false);
  assert.equal(api.lowSpace({ totalBytes: 0, freeBytes: 0 }), false);
});
