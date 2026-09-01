import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";
import test from "node:test";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const script = readFileSync(
  resolve(testDirectory, "../../Sources/ContainerGUI/Resources/Public/update-check.js"),
  "utf8"
);
const api = runInNewContext(`${script}; ContainerGUIUpdate`, { URL });

test("the helper is exposed on globalThis for the application runtime", () => {
  const exposed = runInNewContext(`${script}; globalThis.ContainerGUIUpdate`, { URL });
  assert.equal(typeof exposed?.validatedReleaseURL, "function");
});

test("automatic checks run only when the 24-hour record is absent or expired", () => {
  const day = 24 * 60 * 60 * 1000;
  const now = 2_000_000_000_000;
  assert.equal(api.shouldRunAutomaticCheck(null, now), true);
  assert.equal(api.shouldRunAutomaticCheck("bad", now), true);
  assert.equal(api.shouldRunAutomaticCheck(now - day + 1, now), false);
  assert.equal(api.shouldRunAutomaticCheck(now - day, now), true);
  assert.equal(api.shouldRunAutomaticCheck(now + 1, now), true);
});

test("only the official ContainerGui GitHub release path is accepted", () => {
  assert.equal(
    api.validatedReleaseURL("https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0"),
    "https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0"
  );
  for (const value of [
    "http://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0",
    "https://example.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0",
    "https://github.com/another/repository/releases/tag/v2.18.0",
    "not a url",
  ]) {
    assert.equal(api.validatedReleaseURL(value), null);
  }
});
