import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";
import test from "node:test";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const script = readFileSync(
  resolve(testDirectory, "../../Sources/ContainerGUI/Resources/Public/app.js"),
  "utf8"
);

function loadFunction(name) {
  const match = script.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
  assert.ok(match, `${name} must be defined in app.js`);
  return runInNewContext(`${match[0]}; ${name}`);
}

test("CPU percentage treats all allocated cores as 100 percent", () => {
  const normalizeCPUPercent = loadFunction("normalizeCPUPercent");

  assert.equal(normalizeCPUPercent(300, 3), 100);
  assert.ok(Math.abs(normalizeCPUPercent(100, 3) - (100 / 3)) < 0.000001);
  assert.equal(normalizeCPUPercent(160, 4), 40);
  assert.equal(normalizeCPUPercent(400, 4), 100);
  assert.equal(normalizeCPUPercent(50, undefined), 50);
});
