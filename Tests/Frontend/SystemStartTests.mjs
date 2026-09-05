import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const script = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/app.js", import.meta.url), "utf8");

function loadFunctions(context) {
  const functions = ["canStartSystem", "renderSystemStart", "startSystem"].map((name) => {
    const match = script.match(new RegExp(`(?:async )?function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
    assert.ok(match, `${name} must be defined`);
    return match[0];
  });
  return runInNewContext(`${functions.join("\n")}; ({ canStartSystem, renderSystemStart, startSystem })`, context);
}

function fixture() {
  const health = { tool: { compatibility: "supported" }, serviceState: "unregistered" };
  const button = { setAttribute(name, value) { this[name] = value; } };
  const context = {
    state: { systemHealth: health, startingSystem: false },
    elements: { startSystemButton: button, systemStartHint: {}, systemOperationStatus: {} },
    ENDPOINTS: { systemStart: "/api/v1/system/start" },
    crypto: { randomUUID: () => "test-key" },
    showOperationStatus: () => {},
    formatProblem: (error) => error.message,
    refreshDashboard: async () => {},
  };
  return { context, api: loadFunctions(context), button, health };
}

test("start is offered only for a supported, stopped or unregistered system", () => {
  const { api, health } = fixture();
  for (const serviceState of ["stopped", "unregistered"]) {
    assert.equal(api.canStartSystem({ ...health, serviceState }), true);
  }
  for (const serviceState of ["healthy", "unknown", "unavailable", "degraded"]) {
    assert.equal(api.canStartSystem({ ...health, serviceState }), false);
  }
  assert.equal(api.canStartSystem(null), false);
  assert.equal(api.canStartSystem({ ...health, tool: { compatibility: "missing" } }), false);
});

test("button is visible when stopped, busy during start, and hidden after healthy readback", () => {
  const { api, context, button } = fixture();
  api.renderSystemStart();
  assert.equal(button.hidden, false);
  assert.equal(button.disabled, false);
  context.state.startingSystem = true;
  context.state.systemHealth.serviceState = "healthy";
  api.renderSystemStart();
  assert.equal(button.hidden, false);
  assert.equal(button.disabled, true);
  assert.equal(button["aria-busy"], "true");
  assert.equal(button.textContent, "正在启动 container…");
  context.state.startingSystem = false;
  api.renderSystemStart();
  assert.equal(button.hidden, true);
});

test("click uses a fixed POST, blocks double clicks, polls and refreshes", async () => {
  const { api, context, button } = fixture();
  let release;
  const pending = new Promise((resolve) => { release = resolve; });
  const requests = [];
  let refreshed = 0;
  context.fetchJSON = async (url, options) => { requests.push({ url, options }); return pending; };
  context.pollOperation = async (id, target) => {
    assert.equal(id, "operation-id");
    assert.equal(target, context.elements.systemOperationStatus);
    context.state.systemHealth.serviceState = "healthy";
  };
  context.refreshDashboard = async () => { refreshed += 1; };
  const first = api.startSystem();
  await api.startSystem();
  assert.equal(requests.length, 1);
  assert.equal(button.disabled, true);
  assert.equal(requests[0].url, "/api/v1/system/start");
  assert.equal(requests[0].options.method, "POST");
  assert.equal(requests[0].options.body, "{}");
  assert.equal(requests[0].options.headers["Idempotency-Key"], "test-key");
  release({ id: "operation-id" });
  await first;
  assert.equal(refreshed, 1);
  assert.equal(button.hidden, true);
  assert.equal(context.state.startingSystem, false);
});

test("a failed start reports the error and allows retry without auto-starting", async () => {
  const { api, context, button } = fixture();
  const messages = [];
  context.showOperationStatus = (message, isError) => messages.push({ message, isError });
  context.fetchJSON = async () => { throw new Error("start failed"); };
  await api.startSystem();
  assert.ok(messages.some((entry) => entry.message === "start failed" && entry.isError));
  assert.equal(button.disabled, false);
  assert.equal(button.hidden, false);
  assert.equal(context.state.startingSystem, false);
});
