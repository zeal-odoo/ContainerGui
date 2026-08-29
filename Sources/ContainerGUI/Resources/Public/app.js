"use strict";

const ENDPOINTS = {
  appInfo: "/api/v1",
  health: "/api/v1/system/health",
  containers: "/api/v1/containers",
  metrics: "/api/v1/containers/metrics",
  images: "/api/v1/images",
  imagePull: "/api/v1/images/pull",
  imageDelete: "/api/v1/images/delete",
  registryRepositories: "/api/v1/registry-search/repositories",
  registryTags: "/api/v1/registry-search/tags",
  operations: "/api/v1/operations/"
};
const REFRESH_INTERVAL_MS = 5000;
const LOG_DISPLAY_LIMIT = 512 * 1024;
const KEEP_ALIVE_ARGUMENTS = ["/bin/bash", "-lc", "exec sleep infinity"];

const elements = Object.fromEntries([
  "appVersionBadge", "versionBadge", "healthCard", "healthLabel", "healthDetail",
  "totalCount", "runningCount", "stoppedCount", "observedAt", "searchInput",
  "loadingState", "emptyState", "errorState", "tableWrap", "containerRows",
  "detailPanel", "detailPlaceholder", "detailContent", "detailTitle", "detailFacts",
  "sshConnectionPanel", "sshStatusLabel", "sshConnectionCommand", "copySSHCommandButton",
  "containerActions", "operationStatus", "closeDetailButton", "loadLogsButton", "followLogsButton",
  "logStatus", "logOutput", "rawDetail", "confirmDialog", "confirmTitle", "confirmMessage",
  "confirmTarget", "confirmActionButton", "toast", "imagesSection", "toggleImagesButton",
  "imageSectionBody", "openPullImageButton",
  "imageOperationStatus", "imagePullProgress", "imagePullProgressLabel", "imagePullProgressValue",
  "imagePullProgressBar", "imageLoadingState",
  "imageEmptyState", "imageErrorState", "imageTableWrap", "imageTableBody", "pullImageDialog",
  "pullImageForm", "pullImageRegistry", "pullImageReference", "pullImagePlatform", "pullRegistryError",
  "pullReferenceError", "pullPlatformError", "pullFormStatus", "cancelPullImageButton", "submitPullImageButton",
  "openCreateContainerButton", "localImageOptions", "createContainerDialog", "createContainerForm",
  "createName", "createImage", "createCPUs", "createMemory", "createPorts", "createEnvironment",
  "createArguments", "createStartAfter", "createNameError", "createImageError", "createCPUsError",
  "createMemoryError", "createPortsError", "createEnvironmentError", "createArgumentsError",
  "createSharedDirectorySection", "createSharedDirectoryLabel", "createSharedDirectoryHelp",
  "createSharedHostPath", "createSharedContainerPath", "createSharedHostPathError",
  "createSharedContainerPathError", "createOdooDatabaseFields", "createOdooDatabaseHost",
  "createOdooDatabasePort", "createOdooDatabaseHostError", "createOdooDatabasePortError",
  "createSSHEnabled", "createSSHFields", "createSSHLoginAsRoot", "createSSHHostPort", "createSSHUsername",
  "createSSHPublicKey", "createSSHPublicKeyFile", "createSSHHostPortError",
  "createSSHUsernameError", "createSSHPublicKeyError", "generateSSHKeyPairButton",
  "generatedSSHKeyStatus", "createKeepAlive",
  "createFormStatus", "cancelCreateContainerButton", "submitCreateContainerButton",
  "remoteRegistrySection", "remoteRegistryForm", "remoteSearchQuery",
  "searchRemoteRepositoriesButton", "remoteRepositoryCount", "remoteRepositoryStatus",
  "remoteRepositoryError", "remoteRepositoryResults", "loadMoreRepositoriesButton",
  "remoteTagPanel", "remoteTagCount", "remoteTagStatus", "remoteTagError", "remoteTagResults",
  "loadMoreTagsButton"
].map((id) => [id, document.getElementById(id)]));

const state = {
  containers: [], selectedID: null, selectedDetail: null, selectedSSHStatus: null, detailController: null,
  refreshing: false, submitting: false, eventSource: null,
  reconnectAttempts: 0, reconnectTimer: null, metricsByID: new Map(), metricsStatus: "loading",
  images: [], imagesLoaded: false, containersLoaded: false, imageSubmitting: false, createSubmitting: false,
  remoteRepositories: [], remoteRepositoryPage: 0, remoteRepositoryHasMore: false,
  remoteSearchParameters: null, selectedRemoteRepository: null,
  remoteTags: [], remoteTagPage: 0, remoteTagHasMore: false,
  remoteRepositoryLoading: false, remoteTagLoading: false
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

async function loadApplicationVersion() {
  try {
    const appInfo = await fetchJSON(ENDPOINTS.appInfo);
    elements.appVersionBadge.textContent = appInfo.version ? `GUI v${appInfo.version}` : "GUI 版本未知";
  } catch {
    elements.appVersionBadge.textContent = "GUI 版本未知";
  }
}

function setBusy(busy) {
  state.refreshing = busy;
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
    const storageCell = document.createElement("td");
    renderMetricCell(storageCell, storageDisplay(container));
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
    row.append(nameCell, imageCell, stateCell, cpuCell, memoryCell, storageCell, addressCell, actionCell);
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

function normalizeCPUPercent(cpuPercent, cpuCount) {
  const allocatedCPUCount = Number.isInteger(cpuCount) && cpuCount > 0 ? cpuCount : 1;
  return Math.min(Math.max(cpuPercent / allocatedCPUCount, 0), 100);
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
  const cpuCount = Number.isInteger(container.cpuCount) && container.cpuCount > 0 ? container.cpuCount : 1;
  return {
    value: formatPercent(normalizeCPUPercent(metric.cpuPercent, cpuCount)),
    detail: `100% = ${cpuCount} 核`
  };
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

function storageDisplay(container) {
  if (container.state !== "running") return { value: "未运行", detail: "" };
  const metric = metricFor(container);
  if (!metric) {
    return { value: state.metricsStatus === "loading" ? "读取中" : "暂不可用", detail: "" };
  }
  const filesystem = metric.rootFilesystem;
  if (filesystem?.state !== "ready"
      || !Number.isFinite(filesystem.usagePercent)
      || !Number.isFinite(filesystem.usedBytes)
      || !Number.isFinite(filesystem.capacityBytes)
      || filesystem.capacityBytes <= 0
      || filesystem.usedBytes < 0
      || filesystem.usedBytes > filesystem.capacityBytes) {
    return { value: "暂不可用", detail: "" };
  }
  return {
    value: formatPercent(filesystem.usagePercent),
    detail: `${formatBytes(filesystem.usedBytes)} / ${formatBytes(filesystem.capacityBytes)}`
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

function renderImages(snapshot) {
  state.images = snapshot.items;
  state.imagesLoaded = true;
  elements.imageTableBody.replaceChildren();
  elements.localImageOptions.replaceChildren();
  for (const image of snapshot.items) {
    const option = document.createElement("option");
    option.value = image.name;
    elements.localImageOptions.append(option);
    const row = document.createElement("tr");
    const nameCell = document.createElement("td");
    const name = document.createElement("span");
    name.className = "container-name";
    name.textContent = image.name;
    const identifier = document.createElement("code");
    identifier.textContent = image.id;
    name.append(identifier);
    nameCell.append(name);
    const digestCell = document.createElement("td");
    const digest = document.createElement("code");
    digest.textContent = image.digest;
    digestCell.append(digest);
    const platformsCell = document.createElement("td");
    platformsCell.textContent = image.platforms.length
      ? image.platforms.map((platform) => [platform.os, platform.architecture, platform.variant].filter(Boolean).join("/")).join("、")
      : "—";
    const sizeCell = document.createElement("td");
    sizeCell.textContent = formatBytes(image.sizeBytes);
    const timeCell = document.createElement("td");
    timeCell.textContent = formatTime(image.observedAt);
    const actionCell = document.createElement("td");
    const blockReason = imageDeletionBlockReason(image);
    if (blockReason) {
      const status = document.createElement("span");
      status.className = "quiet";
      status.textContent = blockReason;
      actionCell.append(status);
    } else {
      const deleteButton = document.createElement("button");
      deleteButton.type = "button";
      deleteButton.className = "button danger small";
      deleteButton.textContent = "删除镜像";
      deleteButton.setAttribute("aria-label", `删除镜像 ${image.name}`);
      deleteButton.disabled = state.imageSubmitting;
      deleteButton.addEventListener("click", () => deleteImage(image));
      actionCell.append(deleteButton);
    }
    row.append(nameCell, digestCell, platformsCell, sizeCell, timeCell, actionCell);
    elements.imageTableBody.append(row);
  }
  elements.imageLoadingState.hidden = true;
  elements.imageErrorState.hidden = true;
  elements.imageEmptyState.hidden = snapshot.items.length !== 0;
  elements.imageTableWrap.hidden = snapshot.items.length === 0;
}

function imageDeletionBlockReason(image) {
  if (!state.containersLoaded) return "正在核对";
  if (isProtectedSystemImage(image.name)) return "系统镜像";
  return state.containers.some((container) => imageReferenceMatches(image, container.imageReference))
    ? "正在使用" : null;
}

function isProtectedSystemImage(reference) {
  return reference === "ghcr.io/apple/containerization/vminit"
    || reference.startsWith("ghcr.io/apple/containerization/vminit:")
    || reference.startsWith("ghcr.io/apple/containerization/vminit@");
}

function imageReferenceMatches(image, reference) {
  if (!reference) return false;
  if ([image.name, image.id, image.digest].includes(reference)) return true;
  const digestSeparator = reference.lastIndexOf("@");
  if (digestSeparator >= 0 && reference.slice(digestSeparator + 1) === image.digest) return true;
  return normalizedImageReference(image.name) === normalizedImageReference(reference);
}

function normalizedImageReference(reference) {
  if (reference.startsWith("sha256:")) return reference;
  if (!reference.includes("/")) return `docker.io/library/${reference}`;
  const firstComponent = reference.split("/", 1)[0];
  if (firstComponent.includes(".") || firstComponent.includes(":") || firstComponent === "localhost") {
    return reference;
  }
  return `docker.io/${reference}`;
}

function showImageError(error) {
  elements.imageLoadingState.hidden = true;
  elements.imageEmptyState.hidden = true;
  elements.imageTableWrap.hidden = true;
  elements.imageErrorState.hidden = false;
  elements.imageErrorState.textContent = formatProblem(error);
}

async function loadImages() {
  try {
    renderImages(await fetchJSON(ENDPOINTS.images));
    return true;
  } catch (error) {
    showImageError(error);
    return false;
  }
}

function setImagesExpanded(expanded) {
  const isExpanded = Boolean(expanded);
  const label = isExpanded ? "收起本机镜像" : "展开本机镜像";
  elements.imageSectionBody.hidden = !isExpanded;
  elements.toggleImagesButton.setAttribute("aria-expanded", String(isExpanded));
  elements.toggleImagesButton.setAttribute("aria-label", label);
  elements.toggleImagesButton.title = label;
}

function appendUniqueBy(current, incoming, key) {
  const seen = new Set(current.map((item) => item[key]));
  return current.concat(incoming.filter((item) => {
    if (seen.has(item[key])) return false;
    seen.add(item[key]);
    return true;
  }));
}

function resetRemoteTags(message = "选择一个仓库查看可用标签。") {
  state.selectedRemoteRepository = null;
  state.remoteTags = [];
  state.remoteTagPage = 0;
  state.remoteTagHasMore = false;
  elements.remoteTagResults.replaceChildren();
  elements.remoteTagError.hidden = true;
  elements.remoteTagStatus.hidden = false;
  elements.remoteTagStatus.textContent = message;
  elements.remoteTagCount.textContent = "尚未选择仓库";
  elements.loadMoreTagsButton.hidden = true;
}

function resetRemoteRepositories(message = "输入条件后点击“搜索镜像”。") {
  state.remoteRepositories = [];
  state.remoteRepositoryPage = 0;
  state.remoteRepositoryHasMore = false;
  state.remoteSearchParameters = null;
  elements.remoteRepositoryResults.replaceChildren();
  elements.remoteRepositoryError.hidden = true;
  elements.remoteRepositoryStatus.hidden = false;
  elements.remoteRepositoryStatus.textContent = message;
  elements.remoteRepositoryCount.textContent = "尚未搜索";
  elements.loadMoreRepositoriesButton.hidden = true;
  resetRemoteTags();
}

function renderRemoteRepositories(totalCount = null) {
  elements.remoteRepositoryResults.replaceChildren();
  for (const repository of state.remoteRepositories) {
    const card = document.createElement("article");
    card.className = `remote-result${state.selectedRemoteRepository?.reference === repository.reference ? " selected" : ""}`;
    const header = document.createElement("div");
    header.className = "remote-result-head";
    const title = document.createElement("div");
    title.className = "remote-result-title";
    const name = document.createElement("strong");
    name.textContent = repository.name;
    const reference = document.createElement("code");
    reference.textContent = repository.reference;
    title.append(name, reference);
    const button = document.createElement("button");
    button.type = "button";
    button.className = "button secondary small";
    button.textContent = "查看标签";
    button.setAttribute("aria-label", `查看 ${repository.reference} 的标签`);
    button.addEventListener("click", () => openRemoteRepository(repository));
    header.append(title, button);
    card.append(header);
    if (repository.description) {
      const description = document.createElement("p");
      description.textContent = repository.description;
      card.append(description);
    }
    const metadata = document.createElement("div");
    metadata.className = "remote-result-meta";
    const values = [
      repository.isOfficial ? "官方镜像" : null,
      Number.isFinite(repository.starCount) ? `★ ${repository.starCount.toLocaleString()}` : null,
      Number.isFinite(repository.pullCount) ? `拉取 ${repository.pullCount.toLocaleString()}` : null,
      repository.updatedAt ? `更新 ${formatTime(repository.updatedAt)}` : null
    ].filter(Boolean);
    for (const value of values) {
      const item = document.createElement("span");
      item.textContent = value;
      metadata.append(item);
    }
    if (values.length) card.append(metadata);
    elements.remoteRepositoryResults.append(card);
  }
  const count = state.remoteRepositories.length;
  elements.remoteRepositoryStatus.hidden = count !== 0;
  if (count === 0) elements.remoteRepositoryStatus.textContent = "没有找到匹配的远程镜像。";
  elements.remoteRepositoryCount.textContent = Number.isFinite(totalCount)
    ? `已显示 ${count} / ${totalCount}` : `已显示 ${count}`;
  elements.loadMoreRepositoriesButton.hidden = !state.remoteRepositoryHasMore;
  elements.loadMoreRepositoriesButton.disabled = state.remoteRepositoryLoading;
}

function renderRemoteTags() {
  elements.remoteTagResults.replaceChildren();
  for (const tag of state.remoteTags) {
    const card = document.createElement("article");
    card.className = "remote-result";
    const header = document.createElement("div");
    header.className = "remote-result-head";
    const title = document.createElement("div");
    title.className = "remote-result-title";
    const name = document.createElement("strong");
    name.textContent = tag.name;
    const reference = document.createElement("code");
    reference.textContent = tag.reference;
    title.append(name, reference);
    const button = document.createElement("button");
    button.type = "button";
    button.className = "button small";
    button.textContent = "选择标签";
    button.setAttribute("aria-label", `选择镜像标签 ${tag.name}`);
    button.addEventListener("click", () => selectRemoteTag(tag));
    header.append(title, button);
    card.append(header);
    const metadata = document.createElement("div");
    metadata.className = "remote-result-meta";
    for (const value of [
      tag.digest ? `摘要 ${tag.digest}` : null,
      Number.isFinite(tag.sizeBytes) ? formatBytes(tag.sizeBytes) : null,
      tag.updatedAt ? `更新 ${formatTime(tag.updatedAt)}` : null
    ].filter(Boolean)) {
      const item = document.createElement("span");
      item.textContent = value;
      metadata.append(item);
    }
    if (metadata.childElementCount) card.append(metadata);
    elements.remoteTagResults.append(card);
  }
  const count = state.remoteTags.length;
  elements.remoteTagStatus.hidden = count !== 0;
  if (count === 0) elements.remoteTagStatus.textContent = "该仓库当前没有可选择的标签。";
  elements.remoteTagCount.textContent = `已显示 ${count} 个标签`;
  elements.loadMoreTagsButton.hidden = !state.remoteTagHasMore;
  elements.loadMoreTagsButton.disabled = state.remoteTagLoading;
}

async function loadRemoteRepositoryPage(page) {
  if (!state.remoteSearchParameters || state.remoteRepositoryLoading) return;
  state.remoteRepositoryLoading = true;
  elements.searchRemoteRepositoriesButton.disabled = true;
  elements.loadMoreRepositoriesButton.disabled = true;
  elements.remoteRepositoryError.hidden = true;
  if (page === 1) {
    elements.remoteRepositoryStatus.hidden = false;
    elements.remoteRepositoryStatus.textContent = "正在搜索远程镜像…";
  }
  try {
    const parameters = new URLSearchParams({ ...state.remoteSearchParameters, page: String(page) });
    const result = await fetchJSON(`${ENDPOINTS.registryRepositories}?${parameters}`);
    state.remoteRepositories = appendUniqueBy(state.remoteRepositories, result.items || [], "reference");
    state.remoteRepositoryPage = result.page;
    state.remoteRepositoryHasMore = Boolean(result.hasNextPage) && result.page < 500;
    renderRemoteRepositories(result.totalCount);
  } catch (error) {
    elements.remoteRepositoryStatus.hidden = true;
    elements.remoteRepositoryError.hidden = false;
    elements.remoteRepositoryError.textContent = formatProblem(error);
  } finally {
    state.remoteRepositoryLoading = false;
    elements.searchRemoteRepositoriesButton.disabled = false;
    elements.loadMoreRepositoriesButton.disabled = false;
  }
}

async function loadRemoteTagPage(page) {
  const repository = state.selectedRemoteRepository;
  if (!repository || state.remoteTagLoading) return;
  state.remoteTagLoading = true;
  elements.loadMoreTagsButton.disabled = true;
  elements.remoteTagError.hidden = true;
  if (page === 1) {
    elements.remoteTagStatus.hidden = false;
    elements.remoteTagStatus.textContent = "正在读取镜像标签…";
  }
  try {
    const parameters = new URLSearchParams({
      registry: repository.registry,
      repository: repository.repository,
      page: String(page)
    });
    const result = await fetchJSON(`${ENDPOINTS.registryTags}?${parameters}`);
    state.remoteTags = appendUniqueBy(state.remoteTags, result.items || [], "reference");
    state.remoteTagPage = result.page;
    state.remoteTagHasMore = Boolean(result.hasNextPage) && result.page < 500;
    renderRemoteTags();
  } catch (error) {
    elements.remoteTagStatus.hidden = true;
    elements.remoteTagError.hidden = false;
    elements.remoteTagError.textContent = formatProblem(error);
  } finally {
    state.remoteTagLoading = false;
    elements.loadMoreTagsButton.disabled = false;
  }
}

async function searchRemoteRepositories(event) {
  event.preventDefault();
  if (state.remoteRepositoryLoading) return;
  const query = elements.remoteSearchQuery.value.trim();
  if (!query) {
    elements.remoteRepositoryStatus.textContent = "请输入 Docker Hub 搜索关键词。";
    elements.remoteSearchQuery.focus();
    return;
  }
  const parameters = { registry: "dockerHub", query };
  resetRemoteRepositories("正在搜索远程镜像…");
  state.remoteSearchParameters = parameters;
  await loadRemoteRepositoryPage(1);
}

function loadMoreRemoteRepositories() {
  if (state.remoteRepositoryHasMore) loadRemoteRepositoryPage(state.remoteRepositoryPage + 1);
}

function openRemoteRepository(repository) {
  resetRemoteTags("正在读取镜像标签…");
  state.selectedRemoteRepository = repository;
  renderRemoteRepositories();
  loadRemoteTagPage(1);
}

function loadMoreRemoteTags() {
  if (state.remoteTagHasMore) loadRemoteTagPage(state.remoteTagPage + 1);
}

function selectRemoteTag(tag) {
  elements.pullImageRegistry.value = state.selectedRemoteRepository.registry;
  elements.pullImageReference.value = tag.reference;
  clearPullImageErrors();
  updatePullRegistryHint();
  elements.pullFormStatus.textContent = `已选择标签 ${tag.name}；确认后再开始拉取。`;
  elements.pullImageDialog.showModal();
  elements.pullImageReference.focus();
}

async function refreshDashboard({ announce = false } = {}) {
  if (state.refreshing) return;
  state.metricsStatus = "loading";
  state.containersLoaded = false;
  setBusy(true);
  if (state.containers.length === 0) elements.loadingState.hidden = false;
  const metricsResultPromise = Promise.allSettled([
    fetchJSON(ENDPOINTS.metrics)
  ]).then(([result]) => result);
  const imagesPromise = loadImages();
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
    state.containersLoaded = true;
    updateStatistics(listResult.value);
    renderContainers();
    if (state.selectedID && state.containers.some((item) => item.id === state.selectedID)) {
      loadDetail(state.selectedID, { quiet: true });
    }
    if (announce) showToast("状态已从 CLI 刷新");
  } else {
    showListError(listResult.reason);
  }
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
  const imagesAvailable = await imagesPromise;
  if (imagesAvailable) renderImages({ items: state.images });
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
    renderSSHStatus(null, detail.summary);
    elements.rawDetail.textContent = JSON.stringify(detail.raw, null, 2);
    renderActions(detail.summary);
    elements.loadLogsButton.disabled = false;
    elements.followLogsButton.disabled = false;
    await loadSSHStatus(id, { signal: controller.signal });
  } catch (error) {
    if (!controller.signal.aborted) {
      elements.detailTitle.textContent = "详情读取失败";
      elements.sshConnectionPanel.hidden = true;
      elements.detailFacts.replaceChildren();
      const message = document.createElement("dd");
      message.textContent = error.message;
      elements.detailFacts.append(message);
    }
  } finally {
    if (!controller.signal.aborted) elements.detailPanel.setAttribute("aria-busy", "false");
  }
}

const sshStateLabels = {
  notConfigured: "未配置",
  stopped: "容器已停止",
  initializing: "初始化中",
  ready: "可连接",
  failed: "启动失败"
};

function renderSSHStatus(status, summary = state.selectedDetail?.summary) {
  const connection = status?.connection || summary?.ssh;
  if (!connection) {
    state.selectedSSHStatus = null;
    elements.sshConnectionPanel.hidden = true;
    return;
  }
  const pendingState = summary?.state === "running" ? "initializing"
    : summary?.state === "error" ? "failed" : "stopped";
  const currentState = status?.state || pendingState;
  const command = connection.connectionCommand
    || `ssh -p ${connection.hostPort} ${connection.username}@127.0.0.1`;
  state.selectedSSHStatus = status;
  elements.sshConnectionPanel.hidden = false;
  elements.sshConnectionPanel.dataset.state = currentState;
  elements.sshStatusLabel.textContent = sshStateLabels[currentState] || "状态未知";
  elements.sshConnectionCommand.textContent = command;
  elements.copySSHCommandButton.disabled = !command;
}

async function loadSSHStatus(id, { signal } = {}) {
  const summary = state.selectedDetail?.summary;
  if (!summary?.ssh || state.selectedID !== id) {
    renderSSHStatus(null, summary);
    return;
  }
  try {
    const status = await fetchJSON(
      `${ENDPOINTS.containers}/${encodeURIComponent(id)}/ssh`,
      { signal }
    );
    if (!signal?.aborted && state.selectedID === id) renderSSHStatus(status, summary);
  } catch (error) {
    if (!signal?.aborted && state.selectedID === id) {
      renderSSHStatus({ state: "failed", connection: summary.ssh }, summary);
      elements.sshStatusLabel.textContent = "状态读取失败";
    }
  }
}

async function copySSHCommand() {
  const command = elements.sshConnectionCommand.textContent.trim();
  if (!command) return;
  try {
    await navigator.clipboard.writeText(command);
    showToast("SSH 连接命令已复制");
  } catch {
    showToast("无法自动复制，请手动选择命令");
  }
}

function renderFacts(summary) {
  elements.detailFacts.replaceChildren();
  const cpu = cpuDisplay(summary);
  const memory = memoryDisplay(summary);
  const storage = storageDisplay(summary);
  const facts = [
    ["完整标识", summary.id], ["状态", stateLabels[summary.state] || stateLabels.unknown],
    ["原始状态", summary.rawState || "—"], ["镜像", summary.imageReference || "—"],
    ["CPU 使用率", [cpu.value, cpu.detail].filter(Boolean).join(" · ")],
    ["内存使用", [memory.value, memory.detail].filter(Boolean).join(" · ")],
    ["根文件系统", [storage.value, storage.detail].filter(Boolean).join(" · ")],
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
    const restartButton = document.createElement("button");
    restartButton.type = "button";
    restartButton.className = "button";
    restartButton.textContent = "重启容器";
    restartButton.disabled = state.submitting;
    restartButton.addEventListener("click", () => restartContainer(summary));
    elements.containerActions.append(restartButton);
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
  if (["stopped", "created"].includes(summary.state)) {
    const deleteButton = document.createElement("button");
    deleteButton.type = "button";
    deleteButton.className = "button danger";
    deleteButton.textContent = "删除容器";
    deleteButton.disabled = state.submitting;
    deleteButton.addEventListener("click", () => deleteContainer(summary));
    elements.containerActions.append(deleteButton);
  }
}

function closeDetail() {
  state.detailController?.abort();
  stopFollowingLogs("已停止跟随");
  state.selectedID = null;
  state.selectedDetail = null;
  state.selectedSSHStatus = null;
  elements.sshConnectionPanel.hidden = true;
  elements.detailContent.hidden = true;
  elements.detailPlaceholder.hidden = false;
}

async function startContainer(summary) {
  const confirmed = await requestConfirmation(
    "启动容器",
    `将启动“${summary.displayName}”，完成后会重新读取 CLI 状态。`,
    summary.id,
    "确认启动",
    false
  );
  if (confirmed) await submitContainerOperation("start", summary.id, {});
}

async function stopContainer(summary) {
  const confirmed = await requestConfirmation(
    "正常停止容器",
    "将发送正常停止请求并等待最多 10 秒，不会使用 --all 或 --force。",
    summary.id,
    "确认停止",
    true
  );
  if (confirmed) {
    await submitContainerOperation("stop", summary.id, { confirmationTarget: summary.id });
  }
}

async function restartContainer(summary) {
  const confirmed = await requestConfirmation(
    "重启容器",
    `将正常停止“${summary.displayName}”并重新启动，期间服务会短暂中断。`,
    summary.id,
    "确认重启",
    false
  );
  if (confirmed) {
    await submitContainerOperation("restart", summary.id, { confirmationTarget: summary.id });
  }
}

async function deleteContainer(summary) {
  const confirmed = await requestConfirmation(
    "删除容器",
    "删除后无法恢复；只会删除当前已停止的精确目标，不会使用 --all 或 --force。",
    summary.id,
    "确认删除",
    true
  );
  if (confirmed) {
    await submitContainerOperation("delete", summary.id, { confirmationTarget: summary.id });
  }
}

async function deleteImage(image) {
  const confirmed = await requestConfirmation(
    "删除镜像",
    "删除后无法恢复；只会删除当前精确镜像，不会使用 --all 或 --force。",
    image.name,
    "确认删除镜像",
    true
  );
  if (confirmed) await submitImageDelete(image);
}

async function submitImageDelete(image) {
  if (state.imageSubmitting) return;
  setImagesExpanded(true);
  state.imageSubmitting = true;
  if (state.imagesLoaded) renderImages({ items: state.images });
  showOperationStatus("正在提交镜像删除…", false, elements.imageOperationStatus);
  try {
    const operation = await fetchJSON(ENDPOINTS.imageDelete, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": crypto.randomUUID()
      },
      body: JSON.stringify({ reference: image.name, confirmationTarget: image.name })
    });
    await pollOperation(operation.id, elements.imageOperationStatus);
  } catch (error) {
    showOperationStatus(formatProblem(error), true, elements.imageOperationStatus);
  } finally {
    state.imageSubmitting = false;
    if (state.imagesLoaded) renderImages({ items: state.images });
  }
}

function requestConfirmation(title, message, target, confirmLabel, destructive) {
  elements.confirmTitle.textContent = title;
  elements.confirmMessage.textContent = message;
  elements.confirmTarget.textContent = target;
  elements.confirmActionButton.textContent = confirmLabel;
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
    const completed = await pollOperation(operation.id);
    if (action === "delete" && completed.readback?.targetAbsent === true) closeDetail();
  } catch (error) {
    showOperationStatus(formatProblem(error), true);
    if (action === "restart") await refreshDashboard();
  } finally {
    state.submitting = false;
    if (state.selectedDetail) renderActions(state.selectedDetail.summary);
  }
}

async function pollOperation(id, statusElement = elements.operationStatus) {
  const labels = {
    queued: "已排队", running: "正在执行 CLI 命令", verifying: "正在重新读取状态",
    succeeded: "已验证完成", failed: "操作失败", cancelled: "操作已取消"
  };
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const operation = await fetchJSON(`${ENDPOINTS.operations}${encodeURIComponent(id)}`);
    showOperationStatus(labels[operation.state] || operation.state, operation.state === "failed", statusElement);
    if (statusElement === elements.imageOperationStatus) renderImagePullProgress(operation);
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

function renderImagePullProgress(operation) {
  if (operation.kind !== "pullImage") {
    elements.imagePullProgress.hidden = true;
    return;
  }
  const phaseLabels = {
    fetching: "正在下载镜像层",
    unpacking: "正在解压镜像",
    verifying: "正在验证本机镜像"
  };
  const terminalLabels = {
    succeeded: "镜像拉取完成",
    failed: "镜像拉取失败",
    cancelled: "镜像拉取已取消"
  };
  const progress = operation.progress;
  const percent = Number.isInteger(progress?.percentComplete)
    ? Math.min(Math.max(progress.percentComplete, 0), 100)
    : null;
  elements.imagePullProgress.hidden = false;
  elements.imagePullProgressLabel.textContent = terminalLabels[operation.state]
    || phaseLabels[progress?.phase]
    || (operation.state === "queued" ? "等待开始拉取" : "正在准备镜像拉取");
  if (percent === null) {
    elements.imagePullProgressBar.removeAttribute("value");
    elements.imagePullProgressValue.textContent = "等待进度";
  } else {
    elements.imagePullProgressBar.value = percent;
    elements.imagePullProgressValue.textContent = `${percent}%`;
  }
}

function showOperationStatus(message, isError = false, target = elements.operationStatus) {
  target.hidden = false;
  target.className = `operation-status${target === elements.imageOperationStatus ? " resource-status" : ""}${isError ? " error" : ""}`;
  target.textContent = message;
}

function openPullImageDialog() {
  clearPullImageErrors();
  elements.pullFormStatus.textContent = "";
  updatePullRegistryHint();
  elements.pullImageDialog.showModal();
  elements.pullImageReference.focus();
}

function clearPullImageErrors() {
  elements.pullRegistryError.textContent = "";
  elements.pullReferenceError.textContent = "";
  elements.pullPlatformError.textContent = "";
  elements.pullImageRegistry.removeAttribute("aria-invalid");
  elements.pullImageReference.removeAttribute("aria-invalid");
  elements.pullImagePlatform.removeAttribute("aria-invalid");
}

function renderPullImageErrors(problem) {
  const targets = {
    registry: [elements.pullImageRegistry, elements.pullRegistryError],
    reference: [elements.pullImageReference, elements.pullReferenceError],
    platform: [elements.pullImagePlatform, elements.pullPlatformError]
  };
  for (const error of problem?.fieldErrors || []) {
    const target = targets[error.field];
    if (!target) continue;
    target[0].setAttribute("aria-invalid", "true");
    target[1].textContent = error.message;
  }
}

function isRegistryQualified(reference) {
  const slash = reference.indexOf("/");
  if (slash < 1) return false;
  const firstSegment = reference.slice(0, slash);
  return firstSegment === "localhost" || firstSegment.includes(".") || firstSegment.includes(":");
}

function resolveImageReference(reference, registry) {
  if (!registry) return reference;
  if (registry !== "dockerHub") return null;
  const host = "docker.io/";
  if (reference.startsWith(host)) return reference;
  if (isRegistryQualified(reference)) return null;
  if (registry === "dockerHub" && !reference.includes("/")) {
    return `docker.io/library/${reference}`;
  }
  return `${host}${reference}`;
}

function updatePullRegistryHint() {
  const placeholders = { dockerHub: "postgres:latest 或 owner/image:tag" };
  elements.pullImageReference.placeholder = placeholders[elements.pullImageRegistry.value]
    || "registry.example.com/owner/image:tag";
}

function validateImagePull(reference, platform, registry) {
  const errors = [];
  if (!/^[A-Za-z0-9][A-Za-z0-9._:/@-]{0,511}$/.test(reference)) {
    errors.push({ field: "reference", message: "镜像引用格式无效" });
  }
  if (registry && registry !== "dockerHub") {
    errors.push({ field: "registry", message: "镜像仓库无效" });
  } else if (reference && resolveImageReference(reference, registry) === null) {
    errors.push({ field: "registry", message: "镜像地址与所选仓库不一致" });
  }
  if (platform && !/^linux\/(arm64|amd64)(\/[A-Za-z0-9._-]+)?$/.test(platform)) {
    errors.push({ field: "platform", message: "目标架构必须为 Linux ARM64 或 AMD64" });
  }
  return errors;
}

async function submitImagePull(event) {
  event.preventDefault();
  if (state.imageSubmitting) return;
  clearPullImageErrors();
  const registry = elements.pullImageRegistry.value;
  const platform = elements.pullImagePlatform.value;
  const reference = elements.pullImageReference.value.trim();
  const body = { reference };
  if (platform) body.platform = platform;
  const fieldErrors = validateImagePull(reference, platform, registry);
  if (fieldErrors.length) {
    renderPullImageErrors({ fieldErrors });
    elements.pullFormStatus.textContent = "请修正标出的字段。";
    return;
  }
  const resolvedReference = resolveImageReference(reference, registry);
  body.reference = resolvedReference;
  setImagesExpanded(true);
  state.imageSubmitting = true;
  elements.submitPullImageButton.disabled = true;
  elements.pullFormStatus.textContent = "正在提交拉取操作…";
  renderImagePullProgress({ kind: "pullImage", state: "queued", progress: null });
  try {
    const operation = await fetchJSON(ENDPOINTS.imagePull, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": crypto.randomUUID()
      },
      body: JSON.stringify(body)
    });
    elements.pullImageDialog.close();
    showOperationStatus("镜像拉取已排队", false, elements.imageOperationStatus);
    await pollOperation(operation.id, elements.imageOperationStatus);
  } catch (error) {
    renderPullImageErrors(error.problem);
    elements.pullFormStatus.textContent = formatProblem(error);
    showOperationStatus(formatProblem(error), true, elements.imageOperationStatus);
  } finally {
    state.imageSubmitting = false;
    elements.submitPullImageButton.disabled = false;
  }
}

function openCreateContainerDialog() {
  clearCreateErrors();
  elements.createFormStatus.textContent = "";
  updateImageSpecificCreateFields();
  updateSSHFields();
  elements.createContainerDialog.showModal();
  elements.createName.focus();
}

const createFieldTargets = {
  name: [elements.createName, elements.createNameError],
  image: [elements.createImage, elements.createImageError],
  cpus: [elements.createCPUs, elements.createCPUsError],
  memoryMiB: [elements.createMemory, elements.createMemoryError],
  ports: [elements.createPorts, elements.createPortsError],
  environment: [elements.createEnvironment, elements.createEnvironmentError],
  arguments: [elements.createArguments, elements.createArgumentsError],
  "sharedDirectory.hostPath": [elements.createSharedHostPath, elements.createSharedHostPathError],
  "sharedDirectory.containerPath": [elements.createSharedContainerPath, elements.createSharedContainerPathError],
  odooDatabase: [elements.createOdooDatabaseHost, elements.createOdooDatabaseHostError],
  "odooDatabase.host": [elements.createOdooDatabaseHost, elements.createOdooDatabaseHostError],
  "odooDatabase.port": [elements.createOdooDatabasePort, elements.createOdooDatabasePortError],
  "ssh.hostPort": [elements.createSSHHostPort, elements.createSSHHostPortError],
  "ssh.username": [elements.createSSHUsername, elements.createSSHUsernameError],
  "ssh.publicKey": [elements.createSSHPublicKey, elements.createSSHPublicKeyError]
};

function clearCreateErrors() {
  for (const [input, error] of Object.values(createFieldTargets)) {
    input.removeAttribute("aria-invalid");
    error.textContent = "";
  }
}

function renderCreateErrors(fieldErrors) {
  for (const [field, message] of Object.entries(fieldErrors)) {
    const target = createFieldTargets[field];
    if (!target) continue;
    target[0].setAttribute("aria-invalid", "true");
    target[1].textContent = message;
  }
}

function parsePortLines(value) {
  const mappings = [];
  for (const line of value.split(/\r?\n/).map((item) => item.trim()).filter(Boolean)) {
    const match = /^(\d{1,5}):(\d{1,5})(?:\/(tcp|udp))?$/.exec(line);
    if (!match) throw new Error("端口格式必须为 主机端口:容器端口[/tcp|udp]");
    const hostPort = Number(match[1]);
    const containerPort = Number(match[2]);
    if (hostPort > 0 && hostPort < 1024) {
      throw new Error("主机端口必须使用 1024...65535；1024 以下需要 root 权限");
    }
    if (hostPort < 1 || hostPort > 65535 || containerPort < 1 || containerPort > 65535) {
      throw new Error("端口必须在 1...65535 之间");
    }
    mappings.push({ hostPort, containerPort, protocol: match[3] || "tcp" });
  }
  if (new Set(mappings.map((mapping) => mapping.hostPort)).size !== mappings.length) {
    throw new Error("主机端口不能重复");
  }
  return mappings;
}

function parseEnvironmentLines(value) {
  const entries = [];
  for (const line of value.split(/\r?\n/).filter((item) => item.length > 0)) {
    const separator = line.indexOf("=");
    if (separator < 1) throw new Error("环境变量格式必须为 KEY=value");
    const name = line.slice(0, separator).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error("环境变量名称格式无效");
    entries.push({ name, value: line.slice(separator + 1) });
  }
  if (new Set(entries.map((entry) => entry.name)).size !== entries.length) {
    throw new Error("环境变量名称不能重复");
  }
  return entries;
}

function updateImageSpecificCreateFields() {
  const mode = ContainerGUIOdooCreateForm.createFormMode(elements.createImage.value.trim());
  const wasOdoo = elements.createSharedDirectorySection.dataset.odooMode === "true";
  if (mode.isOdoo && !wasOdoo) {
    elements.createSharedDirectorySection.dataset.genericContainerPath =
      elements.createSharedContainerPath.value.trim() || "/workspace";
  }
  if (mode.isOdoo) {
    elements.createSharedContainerPath.value = mode.containerPath;
  } else if (wasOdoo) {
    elements.createSharedContainerPath.value =
      elements.createSharedDirectorySection.dataset.genericContainerPath || mode.containerPath;
  } else if (!elements.createSharedContainerPath.value.trim()) {
    elements.createSharedContainerPath.value = mode.containerPath;
  }
  elements.createSharedDirectorySection.dataset.odooMode = String(mode.isOdoo);
  elements.createSharedDirectoryLabel.textContent = mode.directoryLabel;
  elements.createSharedDirectoryHelp.textContent = mode.directoryHelp;
  elements.createSharedContainerPath.readOnly = mode.targetReadOnly;
  elements.createOdooDatabaseFields.hidden = !mode.showDatabase;
  elements.createOdooDatabaseHost.disabled = !mode.showDatabase;
  elements.createOdooDatabasePort.disabled = !mode.showDatabase;
}

function isSafeAbsoluteMountPath(path) {
  return path.length <= 4096 && path.startsWith("/") && path !== "/"
    && !/[\0\r\n,]/.test(path)
    && !path.split("/").some((component) => component === "." || component === "..");
}

function isValidOdooDatabaseHost(host) {
  return host.length >= 1 && host.length <= 255
    && /[A-Za-z0-9]/.test(host)
    && /^[A-Za-z0-9._:-]+$/.test(host);
}

function validateSSHPublicKey(value) {
  if (!value || value.length > 4096 || /[\r\n\0]/.test(value)) {
    return "SSH 公钥必须是单行且不超过 4096 个字符";
  }
  const match = /^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[ \t]+([A-Za-z0-9+/]+={0,2})(?:[ \t]+.*)?$/.exec(value);
  if (!match) return "SSH 公钥格式无效，请粘贴单行公钥或选择 .pub 文件";
  try {
    const decoded = atob(match[2]);
    if (decoded.length < 16) throw new Error("short key");
  } catch {
    return "SSH 公钥的 Base64 内容无效";
  }
  return null;
}

function updateSSHFields() {
  const enabled = elements.createSSHEnabled.checked;
  elements.createSSHFields.hidden = !enabled;
  elements.createSSHEnabled.setAttribute("aria-expanded", String(enabled));
  if (!enabled) elements.createSSHLoginAsRoot.checked = false;
  elements.createSSHLoginAsRoot.disabled = !enabled;
  updateSSHRootMode();
  if (enabled) {
    elements.createStartAfter.checked = true;
    elements.createStartAfter.disabled = true;
  } else {
    elements.createStartAfter.disabled = false;
  }
  updateProcessModeFields();
}

function updateSSHRootMode() {
  const sshEnabled = elements.createSSHEnabled.checked;
  const loginAsRoot = sshEnabled && elements.createSSHLoginAsRoot.checked;
  if (loginAsRoot) {
    if (elements.createSSHUsername.value !== "root") {
      elements.createSSHUsername.dataset.standardUsername = elements.createSSHUsername.value || "dev";
    }
    elements.createSSHUsername.value = "root";
  } else if (elements.createSSHUsername.value === "root") {
    elements.createSSHUsername.value = elements.createSSHUsername.dataset.standardUsername || "dev";
  }
  elements.createSSHUsername.disabled = !sshEnabled || loginAsRoot;
}

function updateProcessModeFields() {
  const sshEnabled = elements.createSSHEnabled.checked;
  if (sshEnabled) elements.createKeepAlive.checked = false;
  const keepAlive = elements.createKeepAlive.checked;
  elements.createKeepAlive.disabled = sshEnabled;
  elements.createArguments.disabled = sshEnabled || keepAlive;
  if (sshEnabled || keepAlive) elements.createArguments.value = "";
  if (keepAlive) elements.createStartAfter.checked = true;
}

async function readSSHPublicKeyFile() {
  const file = elements.createSSHPublicKeyFile.files?.[0];
  if (!file) return;
  elements.createSSHPublicKeyError.textContent = "";
  if (file.size > 16 * 1024) {
    elements.createSSHPublicKeyError.textContent = "公钥文件过大";
    elements.createSSHPublicKeyFile.value = "";
    return;
  }
  try {
    elements.createSSHPublicKey.value = (await file.text()).trim();
    elements.generatedSSHKeyStatus.textContent = "";
    const error = validateSSHPublicKey(elements.createSSHPublicKey.value);
    if (error) elements.createSSHPublicKeyError.textContent = error;
  } catch {
    elements.createSSHPublicKeyError.textContent = "无法读取公钥文件";
  }
}

function generatedPrivateKeyFilename() {
  const suffix = elements.createName.value.trim().toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "") || "ssh";
  return `id_container_gui_${suffix}_${Date.now()}`;
}

function downloadPrivateKey(privateKey, filename) {
  const url = URL.createObjectURL(new Blob([privateKey], { type: "application/x-pem-file" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

async function generateAndDownloadSSHKeyPair() {
  elements.generateSSHKeyPairButton.disabled = true;
  elements.generatedSSHKeyStatus.textContent = "正在浏览器中生成密钥…";
  try {
    const { publicKey, privateKey } = await ContainerGUIKeyGenerator.generateOpenSSHKeyPair();
    const filename = generatedPrivateKeyFilename();
    elements.createSSHPublicKey.value = publicKey;
    elements.createSSHPublicKeyFile.value = "";
    elements.createSSHPublicKey.removeAttribute("aria-invalid");
    elements.createSSHPublicKeyError.textContent = "";
    downloadPrivateKey(privateKey, filename);
    elements.generatedSSHKeyStatus.textContent = `公钥已填入，私钥已下载为 ${filename}；使用前请执行 chmod 600。`;
  } catch (error) {
    elements.generatedSSHKeyStatus.textContent = error.message || "密钥生成失败";
  } finally {
    elements.generateSSHKeyPairButton.disabled = false;
  }
}

function buildCreateRequest() {
  const errors = {};
  const name = elements.createName.value.trim();
  const image = elements.createImage.value.trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(name)) errors.name = "容器名称格式无效";
  if (!/^[A-Za-z0-9][A-Za-z0-9._:/@-]{0,511}$/.test(image)) errors.image = "镜像引用格式无效";
  const cpus = elements.createCPUs.value === "" ? null : Number(elements.createCPUs.value);
  if (cpus !== null && (!Number.isInteger(cpus) || cpus < 1 || cpus > 1024)) {
    errors.cpus = "CPU 必须为 1...1024 的整数";
  }
  const memoryMiB = elements.createMemory.value === "" ? null : Number(elements.createMemory.value);
  if (memoryMiB !== null && (!Number.isInteger(memoryMiB) || memoryMiB < 1 || memoryMiB > 1048576)) {
    errors.memoryMiB = "内存必须为 1...1048576 MiB 的整数";
  }
  let ports = [];
  let environment = [];
  try { ports = parsePortLines(elements.createPorts.value); } catch (error) { errors.ports = error.message; }
  try { environment = parseEnvironmentLines(elements.createEnvironment.value); } catch (error) { errors.environment = error.message; }
  const argumentsList = elements.createKeepAlive.checked
    ? [...KEEP_ALIVE_ARGUMENTS]
    : elements.createArguments.value.split(/\r?\n/).filter((item) => item.length > 0);
  if (argumentsList.length > 64 || argumentsList.some((item) => item.length > 4096)) {
    errors.arguments = "进程参数数量或内容无效";
  }
  const mode = ContainerGUIOdooCreateForm.createFormMode(image);
  const hostPath = elements.createSharedHostPath.value.trim();
  const containerPath = elements.createSharedContainerPath.value.trim();
  let sharedDirectory = null;
  if (hostPath) {
    if (!isSafeAbsoluteMountPath(hostPath)) {
      errors["sharedDirectory.hostPath"] = "本机目录必须是安全的非根绝对路径";
    }
    if (!isSafeAbsoluteMountPath(containerPath)) {
      errors["sharedDirectory.containerPath"] = "容器目录必须是安全的非根绝对路径";
    } else if (mode.isOdoo && containerPath !== "/mnt/extra-addons") {
      errors["sharedDirectory.containerPath"] = "Odoo 自定义模块目录必须为 /mnt/extra-addons";
    }
    sharedDirectory = { hostPath, containerPath };
  }
  let odooDatabase = null;
  if (mode.isOdoo) {
    const host = elements.createOdooDatabaseHost.value.trim();
    const port = Number(elements.createOdooDatabasePort.value);
    if (!isValidOdooDatabaseHost(host)) errors["odooDatabase.host"] = "数据库地址格式无效";
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      errors["odooDatabase.port"] = "数据库端口必须在 1...65535 之间";
    }
    if (environment.some((entry) => entry.name === "HOST" || entry.name === "PORT")) {
      errors.environment = "已使用 Odoo 数据库字段，环境变量不能重复定义 HOST 或 PORT";
    }
    odooDatabase = { host, port };
  }
  if (Object.keys(errors).length) {
    renderCreateErrors(errors);
    return null;
  }
  const request = {
    name, image, ports, environment, arguments: argumentsList,
    startAfterCreate: elements.createStartAfter.checked
  };
  if (sharedDirectory) request.sharedDirectory = sharedDirectory;
  if (odooDatabase) request.odooDatabase = odooDatabase;
  if (elements.createSSHEnabled.checked) {
    const hostPort = Number(elements.createSSHHostPort.value);
    const loginAsRoot = elements.createSSHLoginAsRoot.checked;
    const username = elements.createSSHUsername.value.trim();
    const publicKey = elements.createSSHPublicKey.value.trim();
    if (!Number.isInteger(hostPort) || hostPort < 1024 || hostPort > 65535) {
      errors["ssh.hostPort"] = "SSH 主机端口必须在 1024...65535 之间";
    } else if (ports.some((mapping) => mapping.hostPort === hostPort)) {
      errors["ssh.hostPort"] = "SSH 主机端口不能与其他端口映射重复";
    }
    if (loginAsRoot ? username !== "root" : username === "root" || !/^[a-z_][a-z0-9_-]{0,31}$/.test(username)) {
      errors["ssh.username"] = loginAsRoot
        ? "选择 root 登录时，SSH 用户名必须为 root"
        : "SSH 用户名必须为 1...32 位小写安全名称；root 需使用专用选项";
    }
    const publicKeyError = validateSSHPublicKey(publicKey);
    if (publicKeyError) errors["ssh.publicKey"] = publicKeyError;
    const reservedEnvironmentNames = new Set([
      "CONTAINER_GUI_SSH_USER", "CONTAINER_GUI_SSH_AUTHORIZED_KEY"
    ]);
    if (environment.some((entry) => reservedEnvironmentNames.has(entry.name))) {
      errors.environment = "环境变量使用了 SSH 快速配置的保留名称";
    }
    if (argumentsList.length) {
      errors.arguments = "启用 SSH 时不能同时填写进程参数";
    }
    if (Object.keys(errors).length) {
      renderCreateErrors(errors);
      return null;
    }
    request.startAfterCreate = true;
    request.ssh = { hostPort, username, publicKey, loginAsRoot };
  }
  if (cpus !== null) request.cpus = cpus;
  if (memoryMiB !== null) request.memoryMiB = memoryMiB;
  return request;
}

async function createContainer(event) {
  event.preventDefault();
  if (state.createSubmitting) return;
  clearCreateErrors();
  const body = buildCreateRequest();
  if (!body) {
    elements.createFormStatus.textContent = "请修正标出的字段。";
    return;
  }
  setImagesExpanded(true);
  state.createSubmitting = true;
  elements.submitCreateContainerButton.disabled = true;
  elements.createFormStatus.textContent = "正在提交创建操作…";
  elements.imagePullProgress.hidden = true;
  try {
    const operation = await fetchJSON(ENDPOINTS.containers, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": crypto.randomUUID()
      },
      body: JSON.stringify(body)
    });
    elements.createEnvironment.value = "";
    elements.createContainerDialog.close();
    showOperationStatus("容器创建已排队", false, elements.imageOperationStatus);
    await pollOperation(operation.id, elements.imageOperationStatus);
    elements.createContainerForm.reset();
    elements.generatedSSHKeyStatus.textContent = "";
    updateImageSpecificCreateFields();
    updateSSHFields();
  } catch (error) {
    const errors = Object.fromEntries((error.problem?.fieldErrors || []).map((item) => [item.field, item.message]));
    renderCreateErrors(errors);
    elements.createFormStatus.textContent = formatProblem(error);
    showOperationStatus(formatProblem(error), true, elements.imageOperationStatus);
  } finally {
    state.createSubmitting = false;
    elements.submitCreateContainerButton.disabled = false;
  }
}

function formatProblem(error) {
  const code = error.problem?.code;
  if (code === "OPERATION_IN_PROGRESS") return "该容器已有操作进行中，请等待完成。";
  if (code === "STATE_CONFLICT") return "目标状态已变化，请刷新后重试。";
  if (code === "CLI_TIMEOUT") return "CLI 执行超时，页面将保留当前状态。";
  if (code === "REGISTRY_RATE_LIMITED") return "镜像平台请求过于频繁，请稍后重试。";
  if (code === "REGISTRY_UNAVAILABLE") return "镜像平台当前不可用，本机镜像不受影响。";
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

elements.searchInput.addEventListener("input", renderContainers);
elements.closeDetailButton.addEventListener("click", closeDetail);
elements.copySSHCommandButton.addEventListener("click", copySSHCommand);
elements.loadLogsButton.addEventListener("click", loadRecentLogs);
elements.followLogsButton.addEventListener("click", () => {
  if (state.eventSource) stopFollowingLogs("已停止跟随");
  else startFollowingLogs();
});
elements.toggleImagesButton.addEventListener("click", () => {
  setImagesExpanded(elements.toggleImagesButton.getAttribute("aria-expanded") !== "true");
});
elements.openPullImageButton.addEventListener("click", openPullImageDialog);
elements.cancelPullImageButton.addEventListener("click", () => elements.pullImageDialog.close());
elements.pullImageRegistry.addEventListener("change", updatePullRegistryHint);
elements.pullImageForm.addEventListener("submit", submitImagePull);
elements.remoteRegistryForm.addEventListener("submit", searchRemoteRepositories);
elements.loadMoreRepositoriesButton.addEventListener("click", loadMoreRemoteRepositories);
elements.loadMoreTagsButton.addEventListener("click", loadMoreRemoteTags);
elements.openCreateContainerButton.addEventListener("click", openCreateContainerDialog);
elements.cancelCreateContainerButton.addEventListener("click", () => elements.createContainerDialog.close());
elements.createImage.addEventListener("input", updateImageSpecificCreateFields);
elements.createImage.addEventListener("change", updateImageSpecificCreateFields);
elements.createSSHEnabled.addEventListener("change", updateSSHFields);
elements.createSSHLoginAsRoot.addEventListener("change", updateSSHRootMode);
elements.createSSHPublicKeyFile.addEventListener("change", readSSHPublicKeyFile);
elements.generateSSHKeyPairButton.addEventListener("click", generateAndDownloadSSHKeyPair);
elements.createKeepAlive.addEventListener("change", updateProcessModeFields);
elements.createContainerForm.addEventListener("submit", createContainer);
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") refreshDashboard();
});
window.setInterval(() => {
  if (document.visibilityState === "visible") refreshDashboard();
}, REFRESH_INTERVAL_MS);
loadApplicationVersion();
updateImageSpecificCreateFields();
updateSSHFields();
refreshDashboard();
