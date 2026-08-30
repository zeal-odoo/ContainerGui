import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";
import test from "node:test";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const script = readFileSync(
  resolve(testDirectory, "../../Sources/ContainerGUI/Resources/Public/i18n.js"),
  "utf8"
);
const api = runInNewContext(`${script}; ContainerGUII18n`);

test("preferred language follows a valid saved choice before browser language", () => {
  assert.equal(api.preferredLanguage("zh-CN", "en"), "en");
  assert.equal(api.preferredLanguage("en-US", "zh"), "zh");
  assert.equal(api.preferredLanguage("zh-TW", null), "zh");
  assert.equal(api.preferredLanguage("en-GB", null), "en");
});

test("static interface copy translates in both directions", () => {
  assert.equal(api.translate("容器运行状态", "en"), "Container runtime status");
  assert.equal(api.translate("运行中", "en"), "Running");
  assert.equal(api.translate("Container runtime status", "zh"), "容器运行状态");
});

test("dynamic interface patterns preserve user-owned identifiers and counts", () => {
  assert.equal(api.translate("查看 postgres 的详情", "en"), "View details for postgres");
  assert.equal(api.translate("本页 10 条 · 共 75 条", "en"), "10 on this page · 75 total");
  assert.equal(api.translate("第 3 页", "en"), "Page 3");
  assert.equal(api.translate("100% = 3 核", "en"), "100% = 3 cores");
  assert.equal(api.translate("0.04% · 100% = 3 核", "en"), "0.04% · 100% = 3 cores");
  assert.equal(api.translate("容器命令执行失败。（CLI_EXIT_NONZERO）", "en"), "The container command failed. (CLI_EXIT_NONZERO)");
});

test("unknown runtime values are not modified", () => {
  assert.equal(api.translate("docker.io/library/postgres:latest", "en"), "docker.io/library/postgres:latest");
  assert.equal(api.translate("postgres-odoo-apple", "en"), "postgres-odoo-apple");
});

test("an English rendering keeps its canonical Chinese source when switching back", () => {
  assert.equal(
    api.canonicalSource("Container runtime status", "容器运行状态"),
    "容器运行状态"
  );
  assert.equal(api.canonicalSource("新的动态提示", "旧提示"), "新的动态提示");
});
