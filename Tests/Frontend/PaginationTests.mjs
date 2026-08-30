import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";
import test from "node:test";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const script = readFileSync(
  resolve(testDirectory, "../../Sources/ContainerGUI/Resources/Public/pagination.js"),
  "utf8"
);
const api = runInNewContext(`${script}; ContainerGUIPagination`);

test("pagination shows pages 1 through 9 then the last page at the beginning", () => {
  assert.deepEqual(
    [...api.visiblePages(1, 20)],
    [1, 2, 3, 4, 5, 6, 7, 8, 9, "ellipsis", 20]
  );
});

test("pagination window follows the current page and keeps both boundaries", () => {
  assert.deepEqual(
    [...api.visiblePages(10, 20)],
    [1, "ellipsis", 7, 8, 9, 10, 11, 12, 13, "ellipsis", 20]
  );
  assert.deepEqual(
    [...api.visiblePages(20, 20)],
    [1, "ellipsis", 12, 13, 14, 15, 16, 17, 18, 19, 20]
  );
});

test("pagination shows every page when the result is short", () => {
  assert.deepEqual([...api.visiblePages(3, 6)], [1, 2, 3, 4, 5, 6]);
});

test("page count never exposes pages rejected by the API", () => {
  assert.equal(api.pageCount(200, 10), 20);
  assert.equal(api.pageCount(221_586, 10), 500);
});
