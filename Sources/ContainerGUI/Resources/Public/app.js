"use strict";

const ENDPOINTS = {
  health: "/api/v1/system/health",
  containers: "/api/v1/containers",
  metrics: "/api/v1/containers/metrics",
  operations: "/api/v1/operations/"
};
const REFRESH_INTERVAL_MS = 5000;
const LOG_DISPLAY_LIMIT = 512 * 1024;

const elements = Object.fromEntries([
  "versionBadge", "refreshButton", "healthCard", "healthLabel", "healthDetail",
  "totalCount", "runningCount", "stoppedCount", "observedAt", "searchInput",
  "loadingState", "emptyState", "errorState", "tableWrap", "containerRows",
  "detailPanel", "detailPlaceholder", "detailContent", "detailTitle", "detailFacts",
  "containerActions", "operationStatus", "closeDetailButton", "loadLogsButton", "followLogsButton",
  "logStatus", "logOutput", "rawDetail", "confirmDialog", "confirmTitle", "confirmMessage",
  "confirmTarget", "confirmActionButton", "toast"
].map((id) => [id, document.getElementById(id)]));

const state = {
  containers: [], selectedID: null, selectedDetail: null, detailController: null,
  refreshing: false, submitting: false, eventSource: null,
  reconnectAttempts: 0, reconnectTimer: null, metricsByID: new Map(), metricsStatus: "loading"
};

const stateLabels = {
  running: "运行中", stopped: "已停止", created: "已创建", stopping: "正在停止",
  error: "异常", unknown: "未知"
};
const healthLabels = {
  healthy: "系统正常", stopped: "服务已停止", unregistered: "服务未注册",
  degraded: "服务异常", unavailable: "服务不可用", unknown: "状态未知"
};

async function fetchJSON(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { "Accept": "application/json", ...(options.headers || {}) }
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const error = new Error(payload?.message || `请求失败（HTTP ${response.status}）`);
    error.problem = payload;
    throw error;
  }
  return payload;
}

function setBusy(busy) {
  state.refreshing = busy;
  elements.refreshButton.disabled = busy;
  elements.refreshButton.textContent = busy ? "正在刷新…" : "手动刷新";
}

function renderHealth(health) {
  const compatibility = health.tool?.compatibility || "unrecognized";
  const version = health.tool?.semanticVersion || "未知版本";
  elements.versionBadge.textContent = compatibility === "supported" ? `container ${version}` : "CLI 不可用";
  elements.healthLabel.textContent = healthLabels[health.serviceState] || healthLabels.unknown;
  elements.healthDetail.textContent = health.apiServerVersion || health.diagnosticMessage || "未返回服务版本";
  elements.healthCard.setAttribute("aria-busy", "false");
  const dot = elements.healthCard.querySelector(".status-dot");
  dot.className = "status-dot";
  dot.classList.add(health.serviceState === "healthy" ? "healthy" :
    ["stopped", "unregistered", "degraded"].includes(health.serviceState) ? "degraded" : "unavailable");
}

function renderContainers() {
  const query = elements.searchInput.value.trim().toLocaleLowerCase("zh-Hans");
  const visible = state.containers.filter((container) =>
    [container.displayName, container.id, container.imageReference]
      .filter(Boolean)
      .some((value) => value.toLocaleLowerCase("zh-Hans").includes(query))
  );

  elements.containerRows.replaceChildren();
  for (const container of visible) {
    const row = document.createElement("tr");
    row.dataset.containerId = container.id;
    const nameCell = document.createElement("td");
    const name = document.createElement("span");
    name.className = "container-name";
    name.textContent = container.displayName;
    const id = document.createElement("code");
    id.textContent = container.id;
    name.append(id);
    nameCell.append(name);
    const imageCell = document.createElement("td");
    imageCell.textContent = container.imageReference || "—";
    const stateCell = document.createElement("td");
    const pill = document.createElement("span");
    pill.className = `pill ${container.state}`;
    pill.textContent = stateLabels[container.state] || stateLabels.unknown;
    stateCell.append(pill);
    const cpuCell = document.createElement("td");
    renderMetricCell(cpuCell, cpuDisplay(container));
    const memoryCell = document.createElement("td");
    renderMetricCell(memoryCell, memoryDisplay(container));
    const addressCell = document.createElement("td");
    addressCell.textContent = container.ipv4Address || container.ipv6Address || "—";
    const actionCell = document.createElement("td");
    const detailButton = document.createElement("button");
    detailButton.type = "button";
    detailButton.className = "button secondary small";
    detailButton.textContent = "查看详情";
    detailButton.setAttribute("aria-label", `查看 ${container.displayName} 的详情`);
    detailButton.addEventListener("click", () => loadDetail(container.id));
    actionCell.append(detailButton);
    row.append(nameCell, imageCell, stateCell, cpuCell, memoryCell, addressCell, actionCell);
    elements.containerRows.append(row);
  }

  elements.loadingState.hidden = true;
  elements.errorState.hidden = true;
  elements.emptyState.hidden = state.containers.length !== 0;
  elements.tableWrap.hidden = state.containers.length === 0;
  if (state.containers.length !== 0 && visible.length === 0) {
    elements.errorState.hidden = false;
    elements.errorState.textContent = "没有符合筛选条件的容器。";
  }
}

function metricFor(container) {
  if (container.state !== "running") return null;
  return state.metricsByID.get(container.id) || null;
}

function cpuDisplay(container) {
  if (container.state !== "running") return { value: "未运行", detail: "" };
  const metric = metricFor(container);
  if (!metric) {
    return { value: state.metricsStatus === "loading" ? "读取中" : "暂不可用", detail: "" };
  }
  if (metric.cpuState !== "ready" || !Number.isFinite(metric.cpuPercent)) {
    return { value: "采样中", detail: "等待下一样本" };
  }
  return { value: formatPercent(metric.cpuPercent), detail: "100% = 1 核" };
}

function memoryDisplay(container) {
  if (container.state !== "running") return { value: "未运行", detail: "" };
  const metric = metricFor(container);
  if (!metric) {
    return { value: state.metricsStatus === "loading" ? "读取中" : "暂不可用", detail: "" };
  }
  const percentage = Number.isFinite(metric.memoryPercent) ? formatPercent(metric.memoryPercent) : "比例未知";
  return {
    value: percentage,
    detail: `${formatBytes(metric.memoryUsageBytes)} / ${formatBytes(metric.memoryLimitBytes)}`
  };
}

function renderMetricCell(cell, metric) {
  const value = document.createElement("span");
  value.className = "metric-value";
  value.textContent = metric.value;
  cell.append(value);
  if (metric.detail) {
    const detail = document.createElement("span");
    detail.className = "metric-detail";
    detail.textContent = metric.detail;
    cell.append(detail);
  }
}

function updateStatistics(snapshot) {
  elements.totalCount.textContent = String(snapshot.items.length);
  elements.runningCount.textContent = String(snapshot.items.filter((item) => item.state === "running").length);
  elements.stoppedCount.textContent = String(snapshot.items.filter((item) => item.state === "stopped").length);
  elements.observedAt.textContent = formatTime(snapshot.observedAt);
}

function showListError(error) {
  elements.loadingState.hidden = true;
  elements.emptyState.hidden = true;
  elements.tableWrap.hidden = true;
  elements.errorState.hidden = false;
  const code = error.problem?.code ? `（${error.problem.code}）` : "";
  elements.errorState.textContent = `${error.message}${code}`;
}

async function refreshDashboard({ announce = false } = {}) {
  if (state.refreshing) return;
  state.metricsStatus = "loading";
  setBusy(true);
  if (state.containers.length === 0) elements.loadingState.hidden = false;
  const metricsResultPromise = Promise.allSettled([
    fetchJSON(ENDPOINTS.metrics)
  ]).then(([result]) => result);
  const [healthResult, listResult] = await Promise.allSettled([
    fetchJSON(ENDPOINTS.health),
    fetchJSON(ENDPOINTS.containers)
  ]);
  if (healthResult.status === "fulfilled") renderHealth(healthResult.value);
  else {
    elements.healthCard.setAttribute("aria-busy", "false");
    elements.healthLabel.textContent = "连接失败";
    elements.healthDetail.textContent = healthResult.reason.message;
  }
  if (listResult.status === "fulfilled") {
    state.containers = listResult.value.items;
    updateStatistics(listResult.value);
    renderContainers();
    if (state.selectedID && state.containers.some((item) => item.id === state.selectedID)) {
      loadDetail(state.selectedID, { quiet: true });
    }
    if (announce) showToast("状态已从 CLI 刷新");
  } else showListError(listResult.reason);
  const metricsResult = await metricsResultPromise;
  if (metricsResult.status === "fulfilled") {
    state.metricsByID = new Map(
      metricsResult.value.items.map((metric) => [metric.containerId, metric])
    );
    state.metricsStatus = "ready";
  } else {
    state.metricsByID = new Map();
    state.metricsStatus = "error";
  }
  if (listResult.status === "fulfilled") renderContainers();
  if (state.selectedDetail) renderFacts(state.selectedDetail.summary);
  setBusy(false);
  document.documentElement.dataset.containerGui = "ready";
}

async function loadDetail(id, { quiet = false } = {}) {
  state.detailController?.abort();
  const controller = new AbortController();
  state.detailController = controller;
  state.selectedID = id;
  elements.detailPlaceholder.hidden = true;
  elements.detailContent.hidden = false;
  if (!quiet) elements.detailTitle.textContent = "正在读取…";
  elements.detailPanel.setAttribute("aria-busy", "true");
  try {
    const detail = await fetchJSON(`${ENDPOINTS.containers}/${encodeURIComponent(id)}`, { signal: controller.signal });
    if (controller.signal.aborted) return;
    elements.detailTitle.textContent = detail.summary.displayName;
    state.selectedDetail = detail;
    renderFacts(detail.summary);
    elements.rawDetail.textContent = JSON.stringify(detail.raw, null, 2);
    renderActions(detail.summary);
    elements.loadLogsButton.disabled = false;
    elements.followLogsButton.disabled = false;
  } catch (error) {
    if (!controller.signal.aborted) {
      elements.detailTitle.textContent = "详情读取失败";
      elements.detailFacts.replaceChildren();
      const message = document.createElement("dd");
      message.textContent = error.message;
      elements.detailFacts.append(message);
    }
  } finally {
    if (!controller.signal.aborted) elements.detailPanel.setAttribute("aria-busy", "false");
  }
}

function renderFacts(summary) {
  elements.detailFacts.replaceChildren();
  const cpu = cpuDisplay(summary);
  const memory = memoryDisplay(summary);
  const facts = [
    ["完整标识", summary.id], ["状态", stateLabels[summary.state] || stateLabels.unknown],
    ["原始状态", summary.rawState || "—"], ["镜像", summary.imageReference || "—"],
    ["CPU 使用率", [cpu.value, cpu.detail].filter(Boolean).join(" · ")],
    ["内存使用", [memory.value, memory.detail].filter(Boolean).join(" · ")],
    ["IPv4", summary.ipv4Address || "—"], ["IPv6", summary.ipv6Address || "—"],
    ["创建时间", summary.createdAt ? formatTime(summary.createdAt) : "—"],
    ["读取时间", formatTime(summary.observedAt)]
  ];
  for (const [label, value] of facts) {
    const term = document.createElement("dt");
    term.textContent = label;
    const description = document.createElement("dd");
    description.textContent = value;
    elements.detailFacts.append(term, description);
  }
}

function renderActions(summary) {
  elements.containerActions.replaceChildren();
  const button = document.createElement("button");
  button.type = "button";
  button.className = summary.state === "running" ? "button danger" : "button";
  button.disabled = state.submitting;
  if (summary.state === "running") {
    button.textContent = "正常停止";
    button.addEventListener("click", () => stopContainer(summary));
  } else if (["stopped", "created"].includes(summary.state)) {
    button.textContent = "启动容器";
    button.addEventListener("click", () => startContainer(summary));
  } else {
    button.textContent = "当前状态不可操作";
    button.disabled = true;
  }
  elements.containerActions.append(button);
}

function closeDetail() {
  state.detailController?.abort();
  stopFollowingLogs("已停止跟随");
  state.selectedID = null;
  state.selectedDetail = null;
  elements.detailContent.hidden = true;
  elements.detailPlaceholder.hidden = false;
}

async function startContainer(summary) {
  const confirmed = await requestConfirmation(
    "启动容器",
    `将启动“${summary.displayName}”，完成后会重新读取 CLI 状态。`,
    summary.id,
    false
  );
  if (confirmed) await submitContainerOperation("start", summary.id, {});
}

async function stopContainer(summary) {
  const confirmed = await requestConfirmation(
    "正常停止容器",
    "将发送正常停止请求并等待最多 10 秒，不会使用 --all 或 --force。",
    summary.id,
    true
  );
  if (confirmed) {
    await submitContainerOperation("stop", summary.id, { confirmationTarget: summary.id });
  }
}

function requestConfirmation(title, message, target, destructive) {
  elements.confirmTitle.textContent = title;
  elements.confirmMessage.textContent = message;
  elements.confirmTarget.textContent = target;
  elements.confirmActionButton.textContent = destructive ? "确认停止" : "确认启动";
  elements.confirmActionButton.className = destructive ? "button danger" : "button";
  elements.confirmDialog.returnValue = "";
  elements.confirmDialog.showModal();
  return new Promise((resolve) => {
    elements.confirmDialog.addEventListener("close", () => {
      resolve(elements.confirmDialog.returnValue === "confirm");
    }, { once: true });
  });
}

async function submitContainerOperation(action, id, body) {
  if (state.submitting) return;
  state.submitting = true;
  if (state.selectedDetail) renderActions(state.selectedDetail.summary);
  showOperationStatus("正在提交操作…");
  try {
    const operation = await fetchJSON(
      `${ENDPOINTS.containers}/${encodeURIComponent(id)}/${action}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": crypto.randomUUID()
        },
        body: JSON.stringify(body)
      }
    );
    await pollOperation(operation.id);
  } catch (error) {
    showOperationStatus(formatProblem(error), true);
  } finally {
    state.submitting = false;
    if (state.selectedDetail) renderActions(state.selectedDetail.summary);
  }
}

async function pollOperation(id) {
  const labels = {
    queued: "已排队", running: "正在执行 CLI 命令", verifying: "正在重新读取状态",
    succeeded: "已验证完成", failed: "操作失败", cancelled: "操作已取消"
  };
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const operation = await fetchJSON(`${ENDPOINTS.operations}${encodeURIComponent(id)}`);
    showOperationStatus(labels[operation.state] || operation.state, operation.state === "failed");
    if (["succeeded", "failed", "cancelled"].includes(operation.state)) {
      if (operation.state !== "succeeded") {
        throw Object.assign(new Error(operation.error?.message || labels[operation.state]), { problem: operation.error });
      }
      showToast("操作已完成并通过 CLI 回读验证");
      await refreshDashboard();
      return operation;
    }
    await new Promise((resolve) => window.setTimeout(resolve, 500));
  }
  throw new Error("操作仍在进行，请稍后刷新查看。");
}

function showOperationStatus(message, isError = false) {
  elements.operationStatus.hidden = false;
  elements.operationStatus.className = `operation-status${isError ? " error" : ""}`;
  elements.operationStatus.textContent = message;
}

function formatProblem(error) {
  const code = error.problem?.code;
  if (code === "OPERATION_IN_PROGRESS") return "该容器已有操作进行中，请等待完成。";
  if (code === "STATE_CONFLICT") return "容器状态已变化，请刷新后重试。";
  if (code === "CLI_TIMEOUT") return "CLI 执行超时，页面将保留当前状态。";
  return code ? `${error.message}（${code}）` : error.message;
}

async function loadRecentLogs() {
  if (!state.selectedID) return;
  elements.loadLogsButton.disabled = true;
  elements.logStatus.textContent = "正在读取最近日志…";
  try {
    const logs = await fetchJSON(`${ENDPOINTS.containers}/${encodeURIComponent(state.selectedID)}/logs?tail=200`);
    elements.logOutput.textContent = logs.text;
    elements.logStatus.textContent = logs.truncated ? "最近日志（已截断）" : `读取于 ${formatTime(logs.observedAt)}`;
  } catch (error) {
    elements.logStatus.textContent = formatProblem(error);
  } finally {
    elements.loadLogsButton.disabled = false;
  }
}

function startFollowingLogs({ reconnect = false } = {}) {
  if (!state.selectedID) return;
  stopFollowingLogs();
  const selectedID = state.selectedID;
  elements.followLogsButton.textContent = "停止跟随";
  elements.logStatus.textContent = reconnect ? "正在重新连接实时日志…" : "正在连接实时日志…";
  const source = new EventSource(`${ENDPOINTS.containers}/${encodeURIComponent(selectedID)}/logs/stream?tail=200`);
  state.eventSource = source;
  source.addEventListener("open", () => {
    state.reconnectAttempts = 0;
    elements.logStatus.textContent = "正在实时跟随";
  });
  source.addEventListener("log", (event) => appendLog(parseEventText(event.data)));
  source.addEventListener("warning", (event) => {
    const message = parseEventMessage(event.data);
    elements.logStatus.textContent = `警告：${message}`;
  });
  source.addEventListener("end", (event) => {
    const payload = safeJSON(event.data);
    stopFollowingLogs(`日志流已结束（退出码 ${payload?.exitCode ?? "未知"}）`);
  });
  source.onerror = () => {
    source.close();
    if (state.eventSource !== source || state.selectedID !== selectedID) return;
    state.eventSource = null;
    elements.logStatus.textContent = "实时日志连接中断，准备重连…";
    scheduleLogReconnect();
  };
}

function scheduleLogReconnect() {
  window.clearTimeout(state.reconnectTimer);
  state.reconnectAttempts += 1;
  if (state.reconnectAttempts > 3) {
    elements.logStatus.textContent = "实时日志已断开，可点击“重新连接”。";
    elements.followLogsButton.textContent = "重新连接";
    return;
  }
  const reconnectDelay = state.reconnectAttempts * 1000;
  state.reconnectTimer = window.setTimeout(() => startFollowingLogs({ reconnect: true }), reconnectDelay);
}

function stopFollowingLogs(message = "尚未跟随") {
  window.clearTimeout(state.reconnectTimer);
  state.eventSource?.close();
  state.eventSource = null;
  elements.followLogsButton.textContent = "实时跟随";
  if (message) elements.logStatus.textContent = message;
}

function appendLog(text) {
  const combined = `${elements.logOutput.textContent}${text}`;
  elements.logOutput.textContent = combined.length > LOG_DISPLAY_LIMIT
    ? `［较早日志已从页面移除］\n${combined.slice(-LOG_DISPLAY_LIMIT)}` : combined;
  elements.logOutput.scrollTop = elements.logOutput.scrollHeight;
}

function safeJSON(value) {
  try { return JSON.parse(value); } catch { return null; }
}

function parseEventText(value) {
  const payload = safeJSON(value);
  return payload?.text ?? value;
}

function parseEventMessage(value) {
  const payload = safeJSON(value);
  return payload?.message ?? value;
}

function formatTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("zh-Hans", { hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(date);
}

function formatPercent(value) {
  return Number.isFinite(value) && value >= 0 ? `${value.toFixed(2)}%` : "—";
}

function formatBytes(value) {
  if (!Number.isFinite(value) || value < 0) return "—";
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let amount = value;
  let unit = 0;
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024;
    unit += 1;
  }
  return unit === 0 ? `${Math.round(amount)} ${units[unit]}` : `${amount.toFixed(2)} ${units[unit]}`;
}

function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.hidden = false;
  window.setTimeout(() => { elements.toast.hidden = true; }, 2200);
}

elements.refreshButton.addEventListener("click", () => refreshDashboard({ announce: true }));
elements.searchInput.addEventListener("input", renderContainers);
elements.closeDetailButton.addEventListener("click", closeDetail);
elements.loadLogsButton.addEventListener("click", loadRecentLogs);
elements.followLogsButton.addEventListener("click", () => {
  if (state.eventSource) stopFollowingLogs("已停止跟随");
  else startFollowingLogs();
});
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") refreshDashboard();
});
window.setInterval(() => {
  if (document.visibilityState === "visible") refreshDashboard();
}, REFRESH_INTERVAL_MS);
refreshDashboard();
