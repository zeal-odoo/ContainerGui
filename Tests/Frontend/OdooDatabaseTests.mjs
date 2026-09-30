import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";
import { webcrypto } from "node:crypto";

const source = await readFile(new URL("../../Sources/ContainerGUI/Resources/Public/odoo-database.js", import.meta.url), "utf8");
const context = vm.createContext({ AbortController, crypto: webcrypto, setTimeout });
vm.runInContext(source, context);
const api = context.ContainerGUIOdooDatabase;
const view = (id, host = "old.local") => ({ containerId: id, isOdoo: true, editable: true, host, port: 5432, revision: "a".repeat(64) });
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };

test("late reads and closed sessions cannot overwrite another target", async () => {
  const a = deferred();
  const session = api.createSession({ request: (url) => url.includes("/A/") ? a.promise : Promise.resolve(view("B")), onChange: () => {} });
  const first = session.open("A");
  await session.open("B");
  a.resolve(view("A"));
  await first;
  assert.equal(session.snapshot.containerId, "B");
  assert.equal(session.snapshot.view.containerId, "B");
  session.edit({ host: "draft.local", port: "5433" });
  assert.equal(session.snapshot.host, "draft.local");
  session.close();
  assert.equal(session.snapshot.containerId, null);
});

test("drafts survive failed saves, use captured target, and never contain passwords", async () => {
  const calls = [];
  const session = api.createSession({ request: async (url, options) => { calls.push({ url, options }); if (options?.method === "POST") throw new Error("stale"); return view("odoo"); }, onChange: () => {} });
  await session.open("odoo");
  session.edit({ host: "new.local", port: "5433" });
  await session.save();
  assert.equal(session.snapshot.host, "new.local");
  assert.equal(session.snapshot.port, "5433");
  assert.equal(session.snapshot.error, "stale");
  const body = JSON.parse(calls[1].options.body);
  assert.equal(calls[1].options.headers["Content-Type"], "application/json");
  assert.deepEqual(body, { host: "new.local", port: 5433, confirmationTarget: "odoo", expectedRevision: "a".repeat(64) });
  assert.equal(session.snapshot.busy, false);
});

test("late save completion cannot fill a new target and exact retry keeps its key", async () => {
  const pending = deferred();
  let attempts = 0;
  const keys = [];
  const session = api.createSession({ request: async (url, options) => {
    if (options?.method === "POST") { keys.push(options.headers["Idempotency-Key"]); if (++attempts === 1) throw new Error("network"); return pending.promise; }
    return view(url.includes("/A/") ? "A" : "B");
  }, onChange: () => {} });
  await session.open("A");
  session.edit({ host: "new.local", port: "5432" });
  await session.save();
  const second = session.save();
  await session.open("B");
  pending.resolve({ id: "op", state: "succeeded", readback: { observedOdooDatabase: view("A", "new.local") } });
  await second;
  assert.equal(keys[0], keys[1]);
  assert.equal(session.snapshot.view.containerId, "B");
  assert.equal(session.snapshot.host, "old.local");
});

test("reload replaces an old draft but an older read cannot restore its revision", async () => {
  const old = deferred();
  let count = 0;
  const session = api.createSession({ request: () => ++count === 1 ? old.promise : Promise.resolve({ ...view("A", "current.local"), revision: "b".repeat(64) }), onChange: () => {} });
  const opening = session.open("A");
  await session.reload();
  old.resolve(view("A"));
  await opening;
  assert.equal(session.snapshot.host, "current.local");
  assert.equal(session.snapshot.view.revision, "b".repeat(64));
});

test("autofill uses running PostgreSQL IP without CIDR, never submits", () => {
  const items = [{ id: "pg", displayName: "pg", imageReference: "docker.io/library/postgres:18", state: "running", ipv4Address: "192.168.66.4/24" }, { id: "stopped", imageReference: "postgres:18", state: "stopped", ipv4Address: "192.168.66.5/24" }, { id: "odoo", imageReference: "odoo:19", state: "running", ipv4Address: "192.168.66.6/24" }];
  const options = api.postgresOptions(items);
  assert.equal(options.length, 1);
  assert.equal(options[0].host, "192.168.66.4");
  assert.equal(options[0].port, 5432);
});

test("non-Odoo and stopped internal configuration cannot submit", async () => {
  let posts = 0;
  const session = api.createSession({ request: async (_, options) => { if (options?.method === "POST") posts++; return { ...view("A"), editable: false, restriction: "stoppedInternal" }; }, onChange: () => {} });
  await session.open("A");
  await session.save();
  assert.equal(posts, 0);
  assert.equal(session.snapshot.busy, false);
});

test("success requires independent matching readback and updates the revision", async () => {
  for (const matched of [true, false]) {
    const session = api.createSession({ request: async (_, options) => options?.method === "POST" ? { id: "op", state: "succeeded", readback: { matchedExpectation: matched, observedOdooDatabase: { ...view("A", "new.local"), port: 5433, revision: "b".repeat(64) } } } : view("A"), onChange: () => {} });
    await session.open("A");
    session.edit({ host: "new.local", port: "5433" });
    await session.save();
    assert.equal(session.snapshot.saved, matched);
    assert.equal(session.snapshot.view.revision, (matched ? "b" : "a").repeat(64));
  }
});
