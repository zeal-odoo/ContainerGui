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
  const links = ["containers", "images", "registry"].map((view) => ({
    dataset: { view },
    setAttribute(name, value) { this[name] = value; },
    removeAttribute(name) { delete this[name]; }
  }));
  const context = {
    state: {},
    elements: { containersSection: {}, imagesSection: {}, remoteRegistrySection: {}, pageTitle: {}, openCreateContainerButton: {} },
    document: { querySelectorAll: () => links },
    window: { location: { hash: "#images" } },
    stopFollowingLogs: () => {},
  };
  const renderWorkspace = loadFunction("renderWorkspace", context);
  for (const [hash, view, title] of [["#images", "images", "本机镜像"], ["#registry", "registry", "镜像仓库"], ["#containers", "containers", "容器"], ["#main", "containers", "容器"], ["#__proto__", "containers", "容器"]]) {
    context.window.location.hash = hash;
    renderWorkspace();
    assert.equal(context.state.activeView, view);
    assert.equal(context.elements.pageTitle.textContent, title);
    assert.equal(context.elements.containersSection.hidden, view !== "containers");
    assert.equal(context.elements.imagesSection.hidden, view !== "images");
    assert.equal(context.elements.remoteRegistrySection.hidden, view !== "registry");
    assert.equal(context.elements.openCreateContainerButton.hidden, view === "registry");
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
  const node = () => ({
    children: [], dataset: {},
    append(...children) { this.children.push(...children); },
    replaceChildren() { this.children = []; },
    contains(target) { return this.children.some((child) => child === target || child.contains(target)); },
    setAttribute() {}, addEventListener() {},
  });
  const elements = Object.fromEntries([
    "containerRows", "runningContainerRows", "inactiveContainerRows", "runningContainerGroup", "inactiveContainerGroup",
    "runningContainerCount", "inactiveContainerCount", "loadingState", "errorState", "emptyState", "tableWrap"
  ].map((id) => [id, node()]));
  elements.containerRows.append(elements.runningContainerRows, elements.inactiveContainerRows);
  elements.searchInput = { value: "" };
  return {
    elements, state: { containers }, document: { activeElement: null, createElement: node },
    stateLabels: { running: "运行中", stopped: "已停止", created: "已创建", unknown: "未知" },
    shortImageReference: (value) => value || "—", cpuDisplay: () => ({ value: "—" }),
    memoryDisplay: () => ({ value: "—" }), renderMetricCell() {}, syncDetailButtons() {},
  };
}

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
