import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import test from "node:test";

const script = readFileSync(new URL("../../Sources/ContainerGUI/Resources/Public/app.js", import.meta.url), "utf8");

function fixture() {
  let rendered = "", writes = 0, layouts = 0, nextTimer = 0;
  const timers = new Map();
  const context = {
    state: { selectedID: "demo", eventSource: null, logText: "", logTruncated: false, logRenderTimer: null },
    LOG_DISPLAY_LIMIT: 64 * 1024,
    ENDPOINTS: { containers: "/api/v1/containers" },
    elements: { logOutput: {
      get textContent() { return rendered; },
      set textContent(value) { rendered = value; writes += 1; },
      get scrollHeight() { layouts += 1; return 100; }, scrollTop: 0
    }, logStatus: {}, loadLogsButton: {}, followLogsButton: {} },
    window: {
      setTimeout(callback) { const id = ++nextTimer; timers.set(id, callback); return id; },
      clearTimeout(id) { timers.delete(id); }
    },
    formatTime: () => "00:00:00", formatProblem: error => error.message
  };
  for (const name of ["appendLog", "flushLogOutput", "setLogOutput", "stopFollowingLogs", "loadRecentLogs"]) {
    const match = script.match(new RegExp(`(?:async )?function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
    if (match) context[name] = runInNewContext(`${match[0]}; ${name}`, context);
  }
  return { context, timers, output: () => rendered, writes: () => writes, layouts: () => layouts,
    flush() { for (const [id, callback] of [...timers]) { timers.delete(id); callback(); } }
  };
}

test("a burst of log chunks batches DOM updates and bounds its in-memory tail", () => {
  const f = fixture();
  const chunk = "x".repeat(1024) + "\n";
  for (let index = 0; index < 1000; index += 1) f.context.appendLog(chunk);
  assert.equal(f.writes(), 0, "Streaming input must not repaint for each chunk");
  assert.equal(f.layouts(), 0, "Streaming input must not force synchronous layout");
  assert.equal(f.timers.size, 1);
  assert.ok(f.context.state.logText.length <= 64 * 1024);
  f.flush();
  assert.equal(f.writes(), 1);
  assert.equal(f.layouts(), 1);
  assert.match(f.output(), /较早日志已从页面移除/);
  assert.ok(f.output().length <= 64 * 1024 + 100);
  assert.ok(f.output().endsWith(chunk));
});

test("a huge recent-log response is bounded before being inserted into the document", async () => {
  const f = fixture();
  f.context.fetchJSON = async () => ({ text: "old log\n".repeat(1_000_000) + "LATEST", truncated: false, observedAt: "2026-09-08T10:00:00Z" });
  await f.context.loadRecentLogs();
  assert.ok(f.output().length <= 64 * 1024 + 100);
  assert.ok(f.output().endsWith("LATEST"));
  assert.match(f.context.elements.logStatus.textContent, /截断/);
  assert.equal(f.writes(), 1);
});

test("stopping a stream flushes its final bounded batch and cancels the timer", () => {
  const f = fixture();
  f.context.appendLog("final batch\n");
  f.context.stopFollowingLogs();
  assert.equal(f.output(), "final batch\n");
  assert.equal(f.timers.size, 0);
  const writes = f.writes();
  f.flush();
  assert.equal(f.writes(), writes);
});

test("replacing logs cancels a queued old batch without leaking it into a new selection", () => {
  const f = fixture();
  f.context.appendLog("old container logs");
  f.context.setLogOutput("new container logs");
  assert.equal(f.timers.size, 0);
  f.flush();
  assert.equal(f.output(), "new container logs");
  f.context.setLogOutput("");
  assert.equal(f.output(), "");
  assert.equal(f.context.state.logTruncated, false);
});

test("log snippets are literal text and an oversized incoming chunk retains its newest tail", () => {
  const f = fixture();
  f.context.appendLog("a".repeat(1_000_000) + "<script>log only</script>");
  assert.ok(f.context.state.logText.length <= 64 * 1024);
  f.flush();
  assert.ok(f.output().endsWith("<script>log only</script>"));
  assert.equal(f.writes(), 1);
});
