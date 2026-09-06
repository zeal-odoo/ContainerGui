// Isolated browser QA: serves the real frontend with in-memory API fixtures.
// Never executes the container CLI or connects to the production service.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";

const publicRoot = new URL("../../../Sources/ContainerGUI/Resources/Public/", import.meta.url);
const versionSource = await readFile(new URL("../../../Sources/ContainerGUI/App/AppVersion.swift", import.meta.url), "utf8");
const version = versionSource.match(/current = "([\d.]+)"/)[1];
const observedAt = "2026-09-06T15:38:00Z";
const GiB = 1024 ** 3;
let scenario = "reference";
let theme = "system";
let containers;
let images;
let operationNumber = 0;
const operations = new Map();
const mutations = [];

function reset() {
  containers = [
    { id: "odoo19", displayName: "odoo19", imageReference: "docker.io/library/odoo:19.0-20260817", cpuCount: 3, ipv4Address: "192.168.64.2" },
    { id: "postgres-odoo-apple", displayName: "postgres-odoo-apple", imageReference: "docker.io/library/postgres:latest", cpuCount: 4, ipv4Address: "192.168.64.3" }
  ].map((item) => ({ ...item, state: "running", rawState: "running", createdAt: observedAt, observedAt }));
  images = Array.from({ length: 23 }, (_, index) => ({
    id: `fixture-${index}`, name: index === 0 ? containers[0].imageReference : index === 1 ? containers[1].imageReference : `docker.io/library/ubuntu:fixture-${index}`,
    digest: `sha256:${String(index).padStart(64, "0")}`, platforms: [{ os: "linux", architecture: "arm64", variant: "v8" }], sizeBytes: 661 * 1024 ** 2, observedAt
  }));
  if (scenario === "empty" || scenario === "stopped") containers = [];
  if (scenario === "empty") images = [];
  if (scenario === "long") containers[0].displayName = "development-odoo-enterprise-production-like-long-container-name";
  operations.clear();
  mutations.length = 0;
}
reset();

const staticFiles = new Set(["index.html", "app.js", "app.css", "i18n.js", "pagination.js", "update-check.js", "ssh-key-generator.js", "odoo-create-form.js", ...["cube", "window", "square-3-stack-3d", "magnifying-glass", "x-mark", "chevron-right"].map((name) => `icons/${name}.svg`)]);
const types = { html: "text/html", js: "text/javascript", css: "text/css", svg: "image/svg+xml" };
const server = createServer(async (request, response) => {
  const url = new URL(request.url, "http://127.0.0.1");
  const path = url.pathname;
  const json = (payload, status = 200) => { response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" }); response.end(JSON.stringify(payload)); };
  try {
    if (request.method === "POST") {
      let body = "";
      for await (const chunk of request) { body += chunk; if (body.length > 65536) return json({ message: "Body too large" }, 413); }
      const data = JSON.parse(body || "{}");
      if (path === "/__test/scenario") { scenario = data.name; theme = data.theme || "system"; reset(); return json({ scenario, theme }); }
      mutations.push({ path, data });
      const id = `operation-${++operationNumber}`;
      const kind = path.includes("images/pull") ? "pullImage" : "control";
      if (path === "/api/v1/containers") containers.push({ id: data.name, displayName: data.name, imageReference: data.image, cpuCount: data.cpus || 2, state: "stopped", rawState: "stopped", observedAt });
      if (path === "/api/v1/system/start") scenario = "reference";
      const action = path.match(/^\/api\/v1\/containers\/([^/]+)\/(start|stop|restart|delete)$/);
      if (action) {
        const target = containers.find((item) => item.id === decodeURIComponent(action[1]));
        if (action[2] === "delete") containers = containers.filter((item) => item !== target);
        else if (target) target.state = target.rawState = action[2] === "stop" ? "stopped" : "running";
      }
      operations.set(id, { id, kind, state: "running", reads: 0, readback: { targetAbsent: true } });
      return json({ id }, 202);
    }
    if (path === "/__test/mutations") return json(mutations);
    if (path === "/api/v1") return json({ name: "Container GUI", version });
    if (path === "/api/v1/update-check") return json({ currentVersion: version, latestVersion: version, updateAvailable: false });
    if (path === "/api/v1/system/health") return json({ tool: { compatibility: "supported", semanticVersion: "1.3.1" }, serviceState: scenario === "stopped" ? "stopped" : "healthy", apiServerVersion: "container-apiserver version 1.3.1", observedAt });
    if (path === "/api/v1/containers") return scenario === "error" ? json({ message: "Fixture: CLI temporarily unavailable", code: "CLI_UNAVAILABLE" }, 503) : json({ items: containers, observedAt });
    if (path === "/api/v1/images") return json({ items: images, observedAt });
    if (path === "/api/v1/containers/metrics") return json({ items: containers.map((item, index) => ({ containerId: item.id, cpuState: "ready", cpuPercent: index === 0 ? .09 : 1.68, memoryUsageBytes: (index === 0 ? 1.97 : 1.67) * GiB, memoryLimitBytes: 4 * GiB, memoryPercent: 49.25, rootFilesystem: { state: "ready", usagePercent: .96, usedBytes: 4.86 * GiB, capacityBytes: 503.95 * GiB }, observedAt })), observedAt });
    if (path.startsWith("/api/v1/operations/")) {
      const operation = operations.get(path.split("/").at(-1));
      if (!operation) return json({ message: "No operation" }, 404);
      operation.reads += 1;
      operation.state = operation.reads < 4 ? "running" : "succeeded";
      if (operation.kind === "pullImage") operation.progress = { phase: "fetching", percentComplete: Math.min(operation.reads * 25, 100) };
      return json(operation);
    }
    if (path.endsWith("/logs/follow")) {
      response.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store" });
      response.write('event: log\ndata: {"text":"Fixture: service ready\\n"}\n\n');
      return response.end();
    }
    if (path.endsWith("/logs")) return json({ text: "Fixture: service ready\nListening on port 8069\n", observedAt, truncated: false });
    if (path.startsWith("/api/v1/containers/")) {
      const item = containers.find((entry) => entry.id === decodeURIComponent(path.split("/")[4]));
      return item ? json({ summary: item, raw: { configuration: { resources: { cpus: item.cpuCount } }, status: { state: item.state } } }) : json({ message: "Container not found" }, 404);
    }
    if (path.startsWith("/api/v1/registry-search/")) {
      const page = Number(url.searchParams.get("page")) || 1;
      const tags = path.endsWith("/tags");
      const items = Array.from({ length: 10 }, (_, index) => {
        const number = (page - 1) * 10 + index + 1;
        return tags ? { name: `19.0-${number}`, reference: `docker.io/library/odoo:19.0-${number}`, sizeBytes: 661 * 1024 ** 2 }
          : { name: number === 1 ? "odoo" : `odoo-community-${number}`, reference: number === 1 ? "library/odoo" : `community/odoo-${number}`, repository: number === 1 ? "library/odoo" : `community/odoo-${number}`, registry: "dockerHub", description: "Odoo business applications — container image", isOfficial: number === 1, pullCount: 200000, starCount: 12 };
      });
      return json({ items, page, pageSize: 10, totalCount: 200, hasNextPage: page < 20 });
    }
    const file = path === "/" ? "index.html" : path.slice(1);
    if (!staticFiles.has(file)) return json({ message: "Not found" }, 404);
    response.writeHead(200, { "Content-Type": `${types[file.split(".").at(-1)]}; charset=utf-8`, "Cache-Control": "no-store" });
    let content = await readFile(new URL(file, publicRoot));
    // Only force the media branch for visual QA; use unmodified production tokens.
    if (file === "app.css" && theme !== "system") content = content.toString().replace("@media (prefers-color-scheme: dark)", theme === "dark" ? "@media all" : "@media not all");
    response.end(content);
  } catch { json({ message: "Invalid fixture request" }, 400); }
});
server.listen(8796, "127.0.0.1", () => console.log("Isolated workbench QA: http://127.0.0.1:8796/"));
