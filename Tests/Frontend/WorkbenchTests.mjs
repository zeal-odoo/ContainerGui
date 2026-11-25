import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const script = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/app.js", import.meta.url), "utf8");

function loadFunction(name, context = {}) {
  const match = script.match(new RegExp(`(?:async )?function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
  assert.ok(match, `${name} must be defined`);
  return runInNewContext(`${match[0]}; ${name}`, context);
}

test("workspace navigation shows exactly one view and retains a safe fallback", () => {
  const links = ["containers", "images", "registry", "disks"].map((view) => ({
    dataset: { view },
    setAttribute(name, value) { this[name] = value; },
    removeAttribute(name) { delete this[name]; }
  }));
  const context = {
    state: {},
    elements: { containersSection: {}, imagesSection: {}, remoteRegistrySection: {}, diskHealthSection: {}, pageTitle: {}, openCreateContainerButton: {} },
    document: { querySelectorAll: () => links },
    window: { location: { hash: "#images" } },
    stopFollowingLogs: () => {},
  };
  const renderWorkspace = loadFunction("renderWorkspace", context);
  for (const [hash, view, title] of [["#images", "images", "本机镜像"], ["#registry", "registry", "镜像仓库"], ["#disks", "disks", "硬盘健康"], ["#containers", "containers", "容器"], ["#main", "containers", "容器"], ["#__proto__", "containers", "容器"]]) {
    context.window.location.hash = hash;
    renderWorkspace();
    assert.equal(context.state.activeView, view);
    assert.equal(context.elements.pageTitle.textContent, title);
    assert.equal(context.elements.containersSection.hidden, view !== "containers");
    assert.equal(context.elements.imagesSection.hidden, view !== "images");
    assert.equal(context.elements.remoteRegistrySection.hidden, view !== "registry");
    assert.equal(context.elements.diskHealthSection.hidden, view !== "disks");
    assert.equal(context.elements.openCreateContainerButton.hidden, view === "registry" || view === "disks");
    assert.equal(links.filter((link) => link["aria-current"] === "page").length, 1);
  }
});

test("image display shortens only the Docker Hub prefix without losing tag or digest", () => {
  const shortImageReference = loadFunction("shortImageReference");
  assert.equal(shortImageReference("docker.io/library/odoo:19.0-20260817"), "odoo:19.0-20260817");
  assert.equal(shortImageReference("docker.io/pgvector/pgvector:pg18"), "pgvector/pgvector:pg18");
  assert.equal(shortImageReference("ghcr.io/apple/vminit@sha256:abc"), "ghcr.io/apple/vminit@sha256:abc");
  assert.equal(shortImageReference(null), "—");
});

test("published ports show host bindings, protocols and ranges without implying reachability", () => {
  const display = loadFunction("portMappingsText");
  const ports = [
    { hostAddress: "127.0.0.1", hostPort: 18080, containerPort: 8069, count: 1, protocol: "tcp" },
    { hostAddress: "0.0.0.0", hostPort: 110, containerPort: 5432, count: 1, protocol: "tcp" },
    { hostAddress: "::1", hostPort: 5300, containerPort: 53, count: 3, protocol: "udp" }
  ];
  const expected = "127.0.0.1:18080 → 8069/TCP\n0.0.0.0:110 → 5432/TCP\n[::1]:5300-5302 → 53-55/UDP";
  for (const state of ["running", "stopped", "created"]) {
    assert.equal(display({ state, publishedPorts: ports }), expected);
  }
  assert.equal(display({ publishedPorts: [] }), "未映射");
  assert.equal(display({}), "端口信息不可用");
  assert.equal(display({ publishedPorts: null }), "端口信息不可用");
});

test("the selected row and accessible toggle state stay in sync", () => {
  const buttons = ["odoo19", "postgres"].map((id) => ({
    dataset: { detailId: id, detailName: id },
    setAttribute(name, value) { this[name] = value; },
    row: { classList: { toggle(name, value) { this[name] = value; } } },
    closest() { return this.row; }
  }));
  const context = { state: { selectedID: "odoo19" }, elements: { containerRows: { querySelectorAll: () => buttons }, detailContent: { hidden: false } } };
  const syncDetailButtons = loadFunction("syncDetailButtons", context);
  syncDetailButtons();
  assert.equal(buttons[0]["aria-expanded"], "true");
  assert.equal(buttons[0].row.classList["is-selected"], true);
  assert.equal(buttons[1].row.classList["is-selected"], false);
  context.state.selectedID = null;
  syncDetailButtons();
  assert.equal(buttons[0]["aria-expanded"], "false");
  assert.equal(buttons[0].row.classList["is-selected"], false);
});

function containerListContext(containers) {
  const document = { activeElement: null };
  const node = (tagName) => ({
    tagName, children: [], dataset: {}, attributes: {}, listeners: {},
    append(...children) { this.children.push(...children); },
    replaceChildren() { this.children = []; },
    contains(target) { return this.children.some((child) => child === target || child.contains(target)); },
    setAttribute(name, value) { this.attributes[name] = String(value); },
    addEventListener(name, handler) { this.listeners[name] = handler; },
    focus() { document.activeElement = this; },
  });
  document.createElement = node;
  document.createElementNS = (_, tagName) => node(tagName);
  const elements = Object.fromEntries([
    "containerRows", "runningContainerRows", "inactiveContainerRows", "runningContainerGroup", "inactiveContainerGroup",
    "runningContainerCount", "inactiveContainerCount", "loadingState", "errorState", "emptyState", "tableWrap", "workspaceOperationStatus"
  ].map((id) => [id, node()]));
  elements.containerRows.append(elements.runningContainerRows, elements.inactiveContainerRows);
  elements.searchInput = { value: "" };
  return {
    elements, state: { containers, submitting: false }, document,
    stateLabels: { running: "运行中", stopped: "已停止", created: "已创建", unknown: "未知" },
    shortImageReference: (value) => value || "—", cpuDisplay: () => ({ value: "—" }),
    memoryDisplay: () => ({ value: "—" }), renderMetricCell() {}, syncDetailButtons() {},
    portMappingsText: loadFunction("portMappingsText"),
  };
}

test("port mappings remain visible in both groups and in the selected container details", () => {
  const containers = [
    { id: "running", state: "running", publishedPorts: [{ hostAddress: "127.0.0.1", hostPort: 18080, containerPort: 8069, protocol: "tcp", count: 1 }] },
    { id: "stopped", state: "stopped", publishedPorts: [{ hostAddress: "::1", hostPort: 5353, containerPort: 53, protocol: "udp", count: 1 }] },
    { id: "unmapped", state: "created", publishedPorts: [] },
    { id: "unknown", state: "running" }
  ].map((item) => ({ ...item, displayName: item.id }));
  const context = containerListContext(containers);
  loadFunction("renderContainers", context)();
  const rows = [...context.elements.runningContainerRows.children, ...context.elements.inactiveContainerRows.children];
  const expected = {
    running: "127.0.0.1:18080 → 8069/TCP", stopped: "[::1]:5353 → 53/UDP",
    unmapped: "未映射", unknown: "端口信息不可用"
  };
  for (const row of rows) {
    assert.equal(row.children[2].textContent, expected[row.dataset.containerId]);
    assert.equal(row.children[2].className, "container-ports");
    assert.equal(row.children[2].children.length, 0);
  }
  for (const id of ["detailFacts", "detailExtraFacts", "detailState"]) context.elements[id] = context.document.createElement("div");
  context.storageDisplay = () => ({ value: "—" });
  context.formatTime = () => "00:00";
  const renderFacts = loadFunction("renderFacts", context);
  for (const container of containers) {
    renderFacts(container);
    const facts = context.elements.detailFacts.children;
    const label = facts.findIndex((node) => node.textContent === "端口映射（本机 → 容器）");
    assert.ok(label >= 0);
    assert.equal(facts[label + 1].textContent, expected[container.id]);
    assert.equal(facts[label + 1].className, "container-ports");
  }
});

test("row icons offer only valid start or stop actions and route feedback to the list", () => {
  const containers = ["running", "stopped", "created", "stopping", "error", "unknown"].map((state) => ({ id: state, displayName: state, state }));
  const context = containerListContext(containers);
  const calls = [];
  context.startContainer = (summary, target) => calls.push({ action: "start", summary, target });
  context.stopContainer = (summary, target) => calls.push({ action: "stop", summary, target });
  const render = loadFunction("renderContainers", context);
  render();
  const rows = [...context.elements.runningContainerRows.children, ...context.elements.inactiveContainerRows.children];
  for (const row of rows) {
    const action = row.dataset.containerId === "running" ? "stop" : ["stopped", "created"].includes(row.dataset.containerId) ? "start" : null;
    const controls = row.children[5].children[0].children;
    const button = controls.find((item) => item.dataset.containerAction);
    if (!action) { assert.equal(button, undefined); continue; }
    assert.equal(button.dataset.containerAction, action);
    assert.equal(button.disabled, false);
    assert.equal(button.attributes["aria-label"], `${action === "start" ? "启动" : "停止"}容器 ${row.dataset.containerId}`);
    assert.equal(button.children[0].tagName, "svg");
    assert.equal(button.children[0].attributes["aria-hidden"], "true");
    button.listeners.click();
    assert.equal(calls.at(-1).summary.id, row.dataset.containerId);
    assert.equal(calls.at(-1).target, context.elements.workspaceOperationStatus);
  }
  assert.deepEqual(calls.map((call) => call.action), ["stop", "start", "start"]);
  context.state.submitting = true;
  render();
  for (const row of [...context.elements.runningContainerRows.children, ...context.elements.inactiveContainerRows.children]) {
    const button = row.children[5].children[0].children.find((item) => item.dataset.containerAction);
    if (button) assert.equal(button.disabled, true);
  }
});

test("row controls retain keyboard focus across refreshes without focusing the opposite action", () => {
  const container = { id: "demo", displayName: "Demo", state: "stopped" };
  const context = containerListContext([container]);
  const render = loadFunction("renderContainers", context);
  render();
  const previous = context.elements.inactiveContainerRows.children[0].children[5].children[0].children[0];
  context.document.activeElement = previous;
  render();
  assert.notEqual(context.document.activeElement, previous);
  assert.equal(context.document.activeElement.dataset.containerAction, "start");
  container.state = "running";
  render();
  assert.equal(context.document.activeElement.dataset.detailId, "demo");
  assert.equal(context.document.activeElement.dataset.containerAction, undefined);
});

test("start and stop still require confirmation and preserve the exact target and feedback location", async () => {
  const summary = { id: "demo", displayName: "Demo" };
  const target = {};
  const calls = [];
  let confirmed = false;
  const context = {
    elements: { operationStatus: {} }, requestConfirmation: async () => confirmed,
    submitContainerOperation: (action, id, body, statusElement) => calls.push({ action, id, body, statusElement })
  };
  const start = loadFunction("startContainer", context);
  const stop = loadFunction("stopContainer", context);
  await start(summary, target);
  await stop(summary, target);
  assert.equal(calls.length, 0);
  confirmed = true;
  await start(summary, target);
  await stop(summary, target);
  assert.deepEqual(calls.map(({ action, id, body }) => [action, id, JSON.stringify(body)]), [
    ["start", "demo", "{}"], ["stop", "demo", '{"confirmationTarget":"demo"}']
  ]);
  assert.ok(calls.every((call) => call.statusElement === target));
});

test("list operations block duplicate submissions and show errors without opening details", async () => {
  const target = {};
  const messages = [];
  const buttons = [{ disabled: false }, { disabled: false }];
  let release;
  const pending = new Promise((resolve) => { release = resolve; });
  const requests = [];
  const context = {
    state: { submitting: false, selectedDetail: null },
    elements: { operationStatus: {}, containerRows: { querySelectorAll: () => buttons } },
    ENDPOINTS: { containers: "/api/v1/containers" }, crypto: { randomUUID: () => "test-key" },
    showOperationStatus: (message, isError, statusElement) => messages.push({ message, isError, statusElement }),
    fetchJSON: async (url, options) => { requests.push({ url, options }); return pending; },
    pollOperation: async (id, statusElement) => { assert.equal(statusElement, target); return { readback: {} }; },
    formatProblem: (error) => error.message
  };
  const submit = loadFunction("submitContainerOperation", context);
  const first = submit("start", "demo", {}, target);
  await submit("start", "demo", {}, target);
  assert.equal(requests.length, 1);
  assert.ok(buttons.every((button) => button.disabled));
  assert.equal(requests[0].url, "/api/v1/containers/demo/start");
  assert.equal(requests[0].options.headers["Idempotency-Key"], "test-key");
  release({ id: "operation-id" });
  await first;
  assert.ok(buttons.every((button) => !button.disabled));
  context.fetchJSON = async () => { throw new Error("operation failed"); };
  await submit("stop", "demo", { confirmationTarget: "demo" }, target);
  assert.equal(context.state.submitting, false);
  assert.ok(buttons.every((button) => !button.disabled));
  assert.ok(messages.some((item) => item.message === "operation failed" && item.isError && item.statusElement === target));
});

test("containers are grouped by running state while retaining their order and exact status", () => {
  const containers = ["stopped", "running", "created", "running", "error", "unknown"].map((state, index) => ({
    id: `container-${index}`, displayName: `Container ${index}`, state
  }));
  const context = containerListContext(containers);
  loadFunction("renderContainers", context)();
  const { elements } = context;
  assert.deepEqual(elements.runningContainerRows.children.map((row) => row.dataset.containerId), ["container-1", "container-3"]);
  assert.deepEqual(elements.inactiveContainerRows.children.map((row) => row.dataset.containerId), ["container-0", "container-2", "container-4", "container-5"]);
  assert.equal(elements.runningContainerCount.textContent, "2");
  assert.equal(elements.inactiveContainerCount.textContent, "4");
  assert.equal(elements.inactiveContainerRows.children[1].children[1].children[0].textContent, "已创建");
  assert.equal(elements.runningContainerGroup.hidden, false);
  assert.equal(elements.inactiveContainerGroup.hidden, false);
});

test("groups appear and disappear as containers change state and disappear entirely when empty", () => {
  const container = { id: "demo", displayName: "demo", state: "stopped" };
  const context = containerListContext([container]);
  const render = loadFunction("renderContainers", context);
  render();
  assert.equal(context.elements.runningContainerGroup.hidden, true);
  assert.equal(context.elements.inactiveContainerGroup.hidden, false);
  container.state = "running";
  render();
  assert.equal(context.elements.runningContainerGroup.hidden, false);
  assert.equal(context.elements.inactiveContainerGroup.hidden, true);
  assert.equal(context.elements.inactiveContainerRows.children.length, 0);
  context.state.containers = [];
  render();
  assert.equal(context.elements.runningContainerGroup.hidden, true);
  assert.equal(context.elements.inactiveContainerGroup.hidden, true);
  assert.equal(context.elements.tableWrap.hidden, true);
  assert.equal(context.elements.emptyState.hidden, false);
});

test("one search filters both groups and hides groups without matches", () => {
  const context = containerListContext([
    { id: "database", displayName: "Database", imageReference: "postgres:latest", state: "running" },
    { id: "app", displayName: "App", imageReference: "odoo:19", state: "stopped" }
  ]);
  const render = loadFunction("renderContainers", context);
  context.elements.searchInput.value = "ODOO";
  render();
  assert.equal(context.elements.runningContainerGroup.hidden, true);
  assert.equal(context.elements.inactiveContainerGroup.hidden, false);
  assert.equal(context.elements.inactiveContainerCount.textContent, "1");
  context.elements.searchInput.value = "no match";
  render();
  assert.equal(context.elements.runningContainerGroup.hidden, true);
  assert.equal(context.elements.inactiveContainerGroup.hidden, true);
  assert.equal(context.elements.tableWrap.hidden, true);
  assert.equal(context.elements.errorState.textContent, "没有符合筛选条件的容器。");
  context.elements.searchInput.value = "";
  render();
  assert.equal(context.elements.runningContainerGroup.hidden, false);
  assert.equal(context.elements.inactiveContainerGroup.hidden, false);
  assert.equal(context.state.containers.length, 2);
});

test("late log responses cannot overwrite the newly selected container", async () => {
  for (const fail of [false, true]) {
    let resolve;
    let reject;
    const pending = new Promise((yes, no) => { resolve = yes; reject = no; });
    const context = {
      state: { selectedID: "first" },
      elements: { loadLogsButton: {}, logOutput: { textContent: "second logs" }, logStatus: {} },
      ENDPOINTS: { containers: "/api/v1/containers" },
      fetchJSON: () => pending,
      formatProblem: (error) => error.message,
      formatTime: () => "00:00:00"
    };
    const request = loadFunction("loadRecentLogs", context)();
    context.state.selectedID = "second";
    context.elements.logStatus.textContent = "second status";
    if (fail) reject(new Error("first failed"));
    else resolve({ text: "first logs" });
    await request;
    assert.equal(context.elements.logOutput.textContent, "second logs");
    assert.equal(context.elements.logStatus.textContent, "second status");
  }
});

test("a failed health request clears the previous healthy sidebar state", async () => {
  const context = {
    state: { containers: [], selectedID: null },
    document: { documentElement: { dataset: {} } },
    elements: {
      loadingState: {}, healthCard: { dataset: { state: "healthy" }, setAttribute() {}, querySelector: () => dot },
      healthLabel: {}, healthDetail: {}
    },
    ENDPOINTS: { metrics: "metrics", health: "health", containers: "containers" },
    fetchJSON: async (url) => { if (url === "health") throw new Error("Connection lost"); return { items: [] }; },
    loadImages: async () => {}, setBusy: () => {}, renderSystemStart: () => {},
    updateStatistics: () => {}, renderContainers: () => {}, renderFacts: () => {},
    renderMetrics: () => {}, renderHostUsage: () => {}
  };
  const dot = { className: "status-dot healthy" };
  await loadFunction("refreshDashboard", context)();
  assert.equal(context.elements.healthCard.dataset.state, "unavailable");
  assert.equal(dot.className, "status-dot unavailable");
  assert.equal(context.elements.healthDetail.textContent, "Connection lost");
});
