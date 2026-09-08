import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const script = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/ai-log-history.js", import.meta.url), "utf8");
const i18nScript = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/i18n.js", import.meta.url), "utf8");
const record = (number = 1) => ({ schemaVersion: 1, id: `12345678-1234-1234-1234-${String(number).padStart(12, "0")}`, containerId: "demo", createdAt: "2026-09-08T10:00:00Z", language: "zh", model: "Qwen3-1.7B", modelRevision: "test", appVersion: "2.23.0", result: { text: "<img src=x onerror=alert(1)> Analysis", evidence: "<script>secret()</script> [REDACTED]", observedAt: "2026-09-08T09:59:59Z", inputTokens: 50, outputTokens: 8, elapsedSeconds: 0.1 } });
const page = (items = [record()], overrides = {}) => ({ items, page: 1, pageSize: 10, total: items.length, retentionLimit: 1000, ...overrides });
const settle = async () => { for (let index = 0; index < 30; index += 1) await Promise.resolve(); };

function fixture() {
  const nodes = new Map(), requests = [], downloads = [], listeners = new Map();
  let responder = async () => page(), confirmed = true;
  function element(tag = "div") {
    return { tag, textContent: "", children: [], hidden: false, disabled: false, open: false, handlers: {}, attributes: {}, dataset: {},
      append(...children) { this.children.push(...children); },
      replaceChildren(...children) { this.children = children; },
      setAttribute(key, value) { this.attributes[key] = value; },
      addEventListener(key, action) { this.handlers[key] = action; },
      click() { if (this.tag === "a") downloads.push({ filename: this.download, href: this.href }); else this.handlers.click?.(); },
      remove() {},
      set innerHTML(_) { throw Error("Untrusted history must not use HTML"); }
    };
  }
  const document = { visibilityState: "visible", body: element(), createElement: element,
    getElementById(id) { if (!nodes.has(id)) nodes.set(id, element()); return nodes.get(id); },
    addEventListener(key, action) { listeners.set(key, action); }
  };
  const i18n = runInNewContext(`${i18nScript}; ContainerGUII18n`);
  const blobs = [];
  const context = { document, ContainerGUII18n: i18n, AbortController, Date, JSON, Blob, encodeURIComponent,
    URL: { createObjectURL(blob) { blobs.push(blob); return "blob:local-history"; }, revokeObjectURL() {} },
    setTimeout() { return 1; }, clearTimeout() {}, confirm() { return confirmed; },
    addEventListener(key, action) { listeners.set(key, action); },
    async fetch(url, options) {
      const request = { url, ...options }; requests.push(request);
      const data = await responder(request);
      return { ok: !data.problem, status: data.problem ? 503 : 200, json: async () => data.problem || data };
    }
  };
  const api = runInNewContext(`${script}; ContainerGUIAILogHistory`, context);
  const node = (id) => document.getElementById(`aiHistory${id}`);
  const descendants = (root) => [root, ...root.children.flatMap(descendants)];
  return { api, requests, node, nodes, i18n, blobs, downloads, document,
    respond(fn) { responder = fn; }, confirm(value) { confirmed = value; },
    async open() { node("Panel").open = true; node("Panel").handlers.toggle(); await settle(); },
    async click(label) {
      const button = [...nodes.values()].flatMap(descendants).find((item) => item.tag === "button" && item.textContent === label);
      assert.ok(button, `Missing ${label}`); button.handlers.click(); await settle();
    },
    async control(id) { node(id).handlers.click(); await settle(); },
    async event(name) { listeners.get(name)?.(); await settle(); },
    content() { return [...nodes.values()].flatMap(descendants).map((item) => item.textContent).join("\n"); }
  };
}

test("history is lazy, passive and preserves literal analysis/evidence", async () => {
  const f = fixture(); f.api.setContainer("demo");
  assert.equal(f.requests.length, 0);
  await f.open();
  assert.match(f.requests[0].url, /history\?containerId=demo&page=1$/);
  assert.equal(f.requests[0].method, "GET");
  assert.match(f.content(), /<img src=x onerror=alert\(1\)> Analysis/);
  assert.match(f.content(), /<script>secret\(\)<\/script>/);
  assert.equal(f.requests.some((value) => /enable|analyse|heartbeat/.test(value.url)), false);
});

test("pagination and export use the selected complete record without invoking AI", async () => {
  const f = fixture(); f.api.setContainer("demo");
  f.respond((request) => request.url.endsWith("page=2") ? page([record(11)], { page: 2, total: 11 }) : page(Array.from({ length: 10 }, (_, i) => record(i + 1)), { total: 11 }));
  await f.open(); await f.control("Next");
  assert.match(f.requests.at(-1).url, /page=2$/);
  const count = f.requests.length;
  await f.click("导出 JSON");
  assert.equal(f.requests.length, count);
  assert.equal(f.downloads.length, 1);
  assert.match(f.downloads[0].filename, /000000000011\.json$/);
  const data = JSON.parse(await f.blobs[0].text());
  assert.equal(data.id, record(11).id);
  assert.equal(data.result.evidence, record().result.evidence);
});

test("changing containers discards a late response and old entries", async () => {
  const f = fixture(); let resolve;
  f.api.setContainer("first");
  f.respond(() => new Promise((done) => { resolve = done; }));
  await f.open();
  f.api.setContainer("second");
  resolve(page()); await settle();
  assert.doesNotMatch(f.content(), /onerror/);
  assert.equal(f.node("Panel").open, false);
  f.respond(() => page([])); await f.open();
  assert.match(f.requests.at(-1).url, /containerId=second/);
  assert.match(f.content(), /暂无分析历史/);
});

test("failed fetch is not an empty success and retry recovers with English labels", async () => {
  const f = fixture(); f.api.setContainer("demo");
  f.i18n.setLanguage("en"); f.api.languageChanged();
  f.respond(() => ({ problem: { message: "/private/should-not-be-shown" } }));
  await f.open();
  assert.match(f.node("Message").textContent, /could not be loaded/i);
  assert.doesNotMatch(f.content(), /private\/should/);
  f.respond(() => page()); await f.control("Refresh");
  assert.match(f.content(), /Export JSON/);
  assert.match(f.node("Note").textContent, /1,000/);
});

test("delete requires confirmation and refreshes only after exact target success", async () => {
  const f = fixture(); f.api.setContainer("demo"); await f.open();
  f.confirm(false); await f.click("删除记录");
  assert.equal(f.requests.length, 1);
  f.confirm(true);
  f.respond((request) => request.method === "POST" ? { deletedId: record().id } : page([]));
  await f.click("删除记录");
  const mutation = f.requests.find((request) => request.method === "POST");
  assert.deepEqual(JSON.parse(mutation.body), { id: record().id, confirmationId: record().id });
  assert.match(f.node("Message").textContent, /暂无分析历史/);
});

test("new result refreshes open history once, not closed history", async () => {
  const f = fixture(); f.api.setContainer("demo");
  f.api.notify("one"); await settle(); assert.equal(f.requests.length, 0);
  await f.open(); f.api.notify("two"); await settle();
  const count = f.requests.length; f.api.notify("two"); await settle();
  assert.equal(f.requests.length, count);
  assert.equal(count, 2);
});

test("invalid history payload and oversized entries never render", async () => {
  const f = fixture(); f.api.setContainer("demo");
  f.respond(() => page([record()], { total: -1 })); await f.open();
  assert.match(f.node("Message").textContent, /无法读取分析历史/);
  f.respond(() => page([{ ...record(), result: { ...record().result, text: "X".repeat(100000) } }]));
  await f.control("Refresh"); assert.doesNotMatch(f.content(), /XXXXX/);
});
