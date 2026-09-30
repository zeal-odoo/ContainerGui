import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";
import { webcrypto } from "node:crypto";

const source = await readFile(new URL("../../Sources/ContainerGUI/Resources/Public/odoo-database.js", import.meta.url), "utf8");
const context = vm.createContext({ AbortController, crypto: webcrypto, setTimeout });
vm.runInContext(source, context);
const api = context.ContainerGUIOdooDatabase;
const view = (id, editable = true) => ({ containerId: id, kind: "backend", editable, revision: "a".repeat(64), endpoints: [{ id: "proxy-1", label: "/query/", host: "old.local", port: 8503 }, { id: "proxy-2", label: "/", host: "old.local", port: 5000 }] });

test("all container actions expose connection configuration without Odoo filtering", async () => {
  const app = await readFile(new URL("../../Sources/ContainerGUI/Resources/Public/app.js", import.meta.url), "utf8");
  const actions = app.slice(app.indexOf("function renderActions("), app.indexOf("function renderActions(") + 4200);
  assert.ok(actions.includes('databaseButton.textContent = "连接配置"'));
  assert.ok(!actions.includes("ContainerGUIOdooDatabase?.isOdoo"));
});

test("unified reads select a backend and retain draft through failed captured save", async () => {
  const calls = [];
  const session = api.createSession({ unified: true, request: async (url, options) => { calls.push({ url, options }); if (options?.method === "POST") throw new Error("stale"); return view("gateway"); }, onChange: () => {} });
  await session.open("gateway");
  assert.equal(calls[0].url, "/api/v1/containers/gateway/connections");
  assert.equal(session.snapshot.endpointId, "proxy-1");
  session.selectEndpoint("proxy-2");
  assert.equal(session.snapshot.port, "5000");
  session.edit({ host: "new.local", port: "5001" });
  await session.save();
  assert.equal(session.snapshot.host, "new.local");
  assert.deepEqual(JSON.parse(calls[1].options.body), { endpointId: "proxy-2", host: "new.local", port: 5001, confirmationTarget: "gateway", expectedRevision: "a".repeat(64) });
  assert.equal(session.snapshot.error, "stale");
});

test("backend success must match selected endpoint and target, not another route", async () => {
  for (const matching of [true, false]) {
    const observed = view("gateway");
    observed.revision = "b".repeat(64);
    observed.endpoints[matching ? 1 : 0] = { ...observed.endpoints[matching ? 1 : 0], host: "new.local", port: 5001 };
    const session = api.createSession({ unified: true, request: async (_, options) => options?.method === "POST" ? { id: "op", state: "succeeded", readback: { matchedExpectation: true, observedConnections: observed } } : view("gateway"), onChange: () => {} });
    await session.open("gateway");
    session.selectEndpoint("proxy-2");
    session.edit({ host: "new.local", port: "5001" });
    await session.save();
    assert.equal(session.snapshot.saved, matching);
    assert.equal(session.snapshot.endpointId, "proxy-2");
  }
});

test("Odoo readback adapts into unified view without changing legacy API", async () => {
  const initial = { containerId: "odoo", kind: "database", editable: true, revision: "a".repeat(64), endpoints: [{ id: "database", label: "Odoo", host: "old.local", port: 5432 }] };
  const session = api.createSession({ unified: true, request: async (_, options) => options?.method === "POST" ? { state: "succeeded", readback: { matchedExpectation: true, observedOdooDatabase: { containerId: "odoo", isOdoo: true, editable: true, host: "db.local", port: 5433, revision: "b".repeat(64) } } } : initial, onChange: () => {} });
  await session.open("odoo");
  session.edit({ host: "db.local", port: "5433" });
  await session.save();
  assert.equal(session.snapshot.saved, true);
  assert.equal(session.snapshot.view.kind, "database");
});

test("unsupported views cannot POST; late reads and target changes discard old selection", async () => {
  let resolve, posts = 0;
  const delayed = new Promise((r) => { resolve = r; });
  const session = api.createSession({ unified: true, request: async (url, options) => { if (options?.method === "POST") posts++; return url.includes("/A/") ? delayed : { ...view("B", false), kind: "unsupported", endpoints: [], restriction: "unsupported" }; }, onChange: () => {} });
  const first = session.open("A");
  await session.open("B");
  resolve(view("A"));
  await first;
  await session.save();
  assert.equal(posts, 0);
  assert.equal(session.snapshot.containerId, "B");
  assert.equal(session.snapshot.endpointId, "");
});

test("unified retry keeps its captured key and late save cannot overwrite another container", async () => {
  let resolve, attempts = 0;
  const keys = [];
  const pending = new Promise((r) => { resolve = r; });
  const session = api.createSession({ unified: true, request: async (url, options) => {
    if (options?.method === "POST") { keys.push(options.headers["Idempotency-Key"]); if (++attempts === 1) throw new Error("network"); return pending; }
    return view(url.includes("/A/") ? "A" : "B");
  }, onChange: () => {} });
  await session.open("A");
  session.selectEndpoint("proxy-2");
  session.edit({ host: "draft.local", port: "5001" });
  await session.save();
  const retry = session.save();
  await session.open("B");
  resolve({ state: "succeeded", readback: { matchedExpectation: true, observedConnections: view("A") } });
  await retry;
  assert.equal(keys[0], keys[1]);
  assert.equal(session.snapshot.containerId, "B");
  assert.equal(session.snapshot.endpointId, "proxy-1");
  assert.equal(session.snapshot.host, "old.local");
});

test("connection controls and restrictions translate in both directions", async () => {
  const script = await readFile(new URL("../../Sources/ContainerGUI/Resources/Public/i18n.js", import.meta.url), "utf8");
  const i18n = vm.runInNewContext(`${script}; ContainerGUII18n`);
  for (const text of ["连接配置", "数据库连接", "后端服务", "选择连接", "保存连接配置", "此配置是单文件挂载。请先自行停止容器后再编辑；本工具不会自动停止或重建容器。", "未识别到此容器可编辑的连接配置，不会添加未经应用支持的参数。", "每次保存只修改选中的连接；切换连接会重新填入已保存值。"] ) {
    const english = i18n.translate(text, "en");
    assert.notEqual(english, text);
    assert.equal(i18n.translate(english, "zh"), text);
  }
});
