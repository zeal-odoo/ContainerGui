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
