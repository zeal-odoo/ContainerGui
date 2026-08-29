import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";
import test from "node:test";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const script = readFileSync(
  resolve(testDirectory, "../../Sources/ContainerGUI/Resources/Public/odoo-create-form.js"),
  "utf8"
);
const api = runInNewContext(`${script}; ContainerGUIOdooCreateForm`);

test("only exact Docker Hub official Odoo repositories enable Odoo mode", () => {
  for (const reference of [
    "odoo",
    "odoo:19.0",
    "odoo@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "docker.io/library/odoo:19.0-20260817"
  ]) {
    assert.equal(api.isOfficialOdooImage(reference), true, reference);
  }
  for (const reference of [
    "owner/odoo:19.0",
    "ghcr.io/example/odoo:19.0",
    "docker.io/library/my-odoo:19.0",
    "odoo-helper:latest"
  ]) {
    assert.equal(api.isOfficialOdooImage(reference), false, reference);
  }
});

test("derived form mode fixes Odoo addons path and hides database fields otherwise", () => {
  assert.deepEqual(
    { ...api.createFormMode("docker.io/library/odoo:19.0") },
    {
      isOdoo: true,
      directoryLabel: "Odoo 自定义模块目录",
      directoryHelp: "本机目录会读写映射到 Odoo 官方自定义模块目录 /mnt/extra-addons。",
      containerPath: "/mnt/extra-addons",
      targetReadOnly: true,
      showDatabase: true
    }
  );
  assert.deepEqual(
    { ...api.createFormMode("docker.io/library/ubuntu:26.04") },
    {
      isOdoo: false,
      directoryLabel: "本机共享目录",
      directoryHelp: "用于本机与容器之间读写和传输文件；留空则不挂载。",
      containerPath: "/workspace",
      targetReadOnly: false,
      showDatabase: false
    }
  );
});
