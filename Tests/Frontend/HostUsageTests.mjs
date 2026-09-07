import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const script = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/app.js", import.meta.url), "utf8");
const GiB = 1024 ** 3;

function loadFunction(name, context = {}) {
  const match = script.match(new RegExp(`(?:async )?function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
  assert.ok(match, `${name} must be defined`);
  return runInNewContext(`${match[0]}; ${name}`, context);
}

function fixture() {
  return {
    host: { cpuCount: 16, memoryBytes: 32 * GiB },
    items: [
      { containerId: "a", cpuState: "ready", cpuPercent: 300, memoryUsageBytes: 3 * GiB, memoryLimitBytes: 4 * GiB },
      { containerId: "b", cpuState: "ready", cpuPercent: 100, memoryUsageBytes: GiB, memoryLimitBytes: 2 * GiB }
    ],
    observedAt: "2026-09-07T00:00:00Z"
  };
}

const containers = [{ id: "a", state: "running" }, { id: "b", state: "running" }, { id: "c", state: "stopped" }];

test("all container usage is normalized to host capacity, not allocated quotas", () => {
  const usage = loadFunction("hostUsage")(fixture(), containers);
  assert.equal(usage.cpuPercent, 25);
  assert.equal(usage.cpuCores, 4);
  assert.equal(usage.memoryUsageBytes, 4 * GiB);
  assert.equal(usage.memoryPercent, 12.5);
  assert.equal(usage.status, "ready");
});

test("first CPU sample stays unknown while memory is already available", () => {
  const snapshot = fixture();
  snapshot.items[1].cpuState = "sampling";
  snapshot.items[1].cpuPercent = null;
  const usage = loadFunction("hostUsage")(snapshot, containers);
  assert.equal(usage.cpuPercent, null);
  assert.equal(usage.cpuCores, null);
  assert.equal(usage.memoryPercent, 12.5);
  assert.equal(usage.status, "sampling");
});

test("empty running set is zero, but missing or extra samples are not a full total", () => {
  const compute = loadFunction("hostUsage");
  const empty = { ...fixture(), items: [] };
  const usage = compute(empty, [{ id: "c", state: "stopped" }]);
  assert.equal(usage.cpuPercent, 0);
  assert.equal(usage.memoryPercent, 0);
  for (const [snapshot, list] of [[empty, containers], [fixture(), containers.slice(0, 1)]]) {
    const incomplete = compute(snapshot, list);
    assert.equal(incomplete.status, "incomplete");
    assert.equal(incomplete.cpuPercent, null);
    assert.equal(incomplete.memoryPercent, null);
  }
});

test("bad capacity, duplicate IDs and invalid counters never produce misleading percentages", () => {
  const compute = loadFunction("hostUsage");
  assert.equal(compute(null, containers), null);
  for (const host of [undefined, { cpuCount: 0, memoryBytes: GiB }, { cpuCount: 16, memoryBytes: 0 }]) {
    assert.equal(compute({ ...fixture(), host }, containers), null);
  }
  const duplicate = fixture();
  duplicate.items[1].containerId = "a";
  assert.equal(compute(duplicate, containers), null);
  for (const invalid of [-1, NaN, Infinity]) {
    const snapshot = fixture();
    snapshot.items[0].cpuPercent = invalid;
    assert.equal(compute(snapshot, containers).cpuPercent, null);
    snapshot.items[0].memoryUsageBytes = invalid;
    assert.equal(compute(snapshot, containers), null);
  }
});

test("memory totals above physical capacity are not silently clamped", () => {
  const snapshot = fixture();
  snapshot.host.memoryBytes = 2 * GiB;
  assert.equal(loadFunction("hostUsage")(snapshot, containers).memoryPercent, 200);
});

test("rendering hides stale meters on failure and restores live values on recovery", () => {
  const elements = Object.fromEntries([
    "hostUsageStatus", "hostCPUValue", "hostCPUDetail", "hostCPUMeter",
    "hostMemoryValue", "hostMemoryDetail", "hostMemoryMeter"
  ].map((id) => [id, {}]));
  const context = {
    elements,
    state: { containers, containersLoaded: true, metricsStatus: "ready", metricsSnapshot: fixture() },
    hostUsage: loadFunction("hostUsage"),
    formatTime: () => "09:00:00", formatPercent: (number) => `${number.toFixed(2)}%`,
    formatBytes: (bytes) => `${bytes / GiB} GiB`
  };
  const render = loadFunction("renderHostUsage", context);
  render();
  assert.equal(elements.hostCPUValue.textContent, "25.00%");
  assert.equal(elements.hostMemoryDetail.textContent, "4 GiB / 32 GiB");
  assert.equal(elements.hostCPUMeter.hidden, false);
  assert.equal(elements.hostCPUMeter.value, 25);
  context.state.metricsSnapshot = null;
  context.state.metricsStatus = "error";
  render();
  assert.equal(elements.hostCPUValue.textContent, "暂不可用");
  assert.equal(elements.hostCPUMeter.hidden, true);
  assert.equal(elements.hostMemoryMeter.hidden, true);
  context.state.metricsSnapshot = fixture();
  context.state.metricsStatus = "ready";
  render();
  assert.equal(elements.hostCPUValue.textContent, "25.00%");
  assert.equal(elements.hostCPUMeter.hidden, false);
  context.state.containersLoaded = false;
  render();
  assert.equal(elements.hostCPUMeter.hidden, true);
  assert.equal(elements.hostMemoryMeter.hidden, true);
});

test("a failed refresh clears stale aggregate metrics and the next refresh recovers", async () => {
  const snapshot = fixture();
  let fail = true;
  let renders = 0;
  const context = {
    state: { containers, metricsSnapshot: snapshot, selectedID: null },
    elements: {}, document: { documentElement: { dataset: {} } },
    ENDPOINTS: { metrics: "metrics", health: "health", containers: "containers" },
    fetchJSON: async (url) => {
      if (url === "metrics") { if (fail) throw new Error("Timeout"); return snapshot; }
      return { items: containers };
    },
    loadImages: async () => {}, setBusy: () => {}, renderHealth: () => {},
    updateStatistics: () => {}, renderContainers: () => {}, renderFacts: () => {},
    renderHostUsage: () => { renders += 1; }
  };
  const refresh = loadFunction("refreshDashboard", context);
  await refresh();
  assert.equal(context.state.metricsSnapshot, null);
  assert.equal(context.state.metricsStatus, "error");
  fail = false;
  await refresh();
  assert.equal(context.state.metricsSnapshot, snapshot);
  assert.equal(context.state.metricsStatus, "ready");
  assert.equal(renders, 2);
});
