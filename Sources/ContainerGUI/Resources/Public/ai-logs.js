"use strict";

globalThis.ContainerGUIAILogs = (() => {
  const endpoint = "/api/v1/ai/logs";
  const errorMessages = Object.freeze({
    no_recent_logs: "暂无最近日志可供分析。",
    insufficient_memory: "可用内存不足，请关闭部分应用后重试。",
    worker_stop_failed: "关闭失败，尚未确认释放；请重试关闭。",
    worker_busy: "模型正在处理另一项请求，请稍后重试。",
    worker_protocol_invalid: "模型返回了无效响应，请关闭 AI 后重试。",
    worker_exited: "模型进程已退出，请重新启用 AI。",
    worker_timeout: "模型响应超时，请关闭 AI 后重试。",
    model_runtime_failed: "模型运行失败，请关闭 AI 后重试。",
    model_unavailable: "模型文件不可用，请检查安装状态。",
    model_incompatible: "此模型与当前运行环境不兼容。",
    inference_failed: "未能生成有效分析，请稍后重试。",
    inference_timeout: "模型分析超时，请稍后重试。",
    tokenizer_invalid: "模型分词文件无效，请重新下载。",
    analysis_unavailable: "无法分析日志，请检查容器状态后重试。",
    cancelled: "AI 操作已取消。",
    ai_model_invalid_manifest: "模型清单无效，请更新应用后重试。",
    ai_model_unsafe_directory: "模型目录不符合安全要求，请检查本机模型目录。",
    ai_model_insufficient_disk_space: "磁盘空间不足，无法下载模型。",
    ai_model_not_installed: "模型尚未安装，请确认下载后重试。",
    ai_model_verification_failed: "模型文件校验失败，请重新下载。",
    ai_model_download_failed: "模型下载失败，请检查网络后重试。"
  });
  const ids = ["Panel", "Title", "Model", "Toggle", "ToggleLabel", "Status", "Target", "Error", "RetryStatus", "Consent", "DownloadSize", "ConfirmDownload", "CancelDownload", "Progress", "ProgressText", "Privacy", "LimitsTitle", "Limits", "Result", "Advice", "Answer", "EvidenceTitle", "Evidence", "ResultMeta", "HistoryError"];
  const elements = Object.fromEntries(ids.map((id) => [id, document.getElementById(`aiLogs${id}`)]));
  let containerId = null;
  let snapshot = null;
  let version = 0;
  let sequence = 0;
  let appliedSequence = 0;
  let desired = false;
  let owned = false;
  let consent = false;
  let awaitingInstall = false;
  let stopping = false;
  let pending = null;
  let message = "";
  let pollTimer = null;
  let lastHeartbeat = 0;
  let lastAnalysis = -Infinity;
  let tickingVersion = null;

  const language = () => globalThis.ContainerGUII18n?.language() || "zh";
  const t = (value) => globalThis.ContainerGUII18n?.translate(value) || value;
  const format = (value, replacements) => Object.entries(replacements).reduce((text, [key, replacement]) => text.replaceAll(`{${key}}`, replacement), t(value));
  const active = () => Boolean(desired || stopping || snapshot?.enabled || snapshot?.workerPID || snapshot?.model?.downloading || ["downloading", "loading", "analysing", "stopping"].includes(snapshot?.phase));
  const released = (value) => value.phase === "off" && !value.enabled && !value.workerPID && !value.model?.downloading;

  function errorText(value) {
    if (typeof value !== "string" || !value) return "";
    return t(Object.hasOwn(errorMessages, value) ? errorMessages[value] : value);
  }

  function size(bytes) {
    if (!Number.isFinite(bytes) || bytes < 0) return t("正在核对下载大小…");
    if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2)} GB`;
    if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`;
    return `${Math.round(bytes)} B`;
  }

  function render() {
    const model = snapshot?.model;
    const isActive = active();
    elements.Panel.hidden = !containerId;
    elements.Title.textContent = t("本地 AI 分析");
    elements.Model.textContent = `${model?.name || "Qwen3-1.7B"} · ${t(model?.installed ? "模型已安装" : "按需下载")}`;
    elements.Toggle.setAttribute("aria-checked", String(isActive));
    elements.Toggle.setAttribute("aria-label", t(isActive ? "关闭 AI" : "启用 AI"));
    elements.ToggleLabel.textContent = t(isActive ? "关闭 AI" : "启用 AI");
    elements.Toggle.disabled = pending === "disable" || (!isActive && (!containerId || !snapshot));
    const phase = stopping ? "stopping" : pending === "enable" ? "loading" : pending === "install" ? "downloading" : snapshot?.phase;
    const phases = {
      off: "已关闭 · 模型未运行", downloading: "正在下载模型…", loading: "正在加载模型…",
      ready: "已就绪 · 新日志将自动分析", analysing: "正在分析最近日志…", stopping: "正在关闭 · 等待确认模型退出…", error: "AI 暂不可用"
    };
    elements.Status.textContent = consent ? t("请确认首次模型下载") : t(phases[phase] || "正在读取 AI 状态…");
    elements.Panel.dataset.phase = phase || "unknown";
    const otherTarget = snapshot?.containerId && snapshot.containerId !== containerId && active();
    elements.Target.hidden = !otherTarget;
    elements.Target.textContent = otherTarget ? format("AI 当前用于 {container}。关闭后可为此容器启用。", { container: snapshot.containerId }) : "";
    const detail = errorText(message || snapshot?.error);
    const stopFailure = errorText("worker_stop_failed");
    const error = stopping && detail && detail !== stopFailure ? `${stopFailure} ${detail}` : detail;
    elements.Error.hidden = !error;
    elements.Error.textContent = error;
    elements.RetryStatus.hidden = !error || Boolean(snapshot);
    elements.RetryStatus.textContent = t("重试");
    elements.Consent.hidden = !consent;
    elements.DownloadSize.textContent = model?.totalBytes > 0
      ? format("首次使用需下载 {size}（{bytes} 字节）。模型文件保留在本机。", { size: size(model.totalBytes), bytes: model.totalBytes.toLocaleString(language() === "en" ? "en" : "zh-Hans") })
      : t("正在核对下载大小…");
    elements.ConfirmDownload.textContent = t("确认下载并启用");
    elements.ConfirmDownload.disabled = !model?.totalBytes || Boolean(pending);
    elements.CancelDownload.textContent = t("取消");
    elements.Progress.hidden = !model?.downloading;
    elements.ProgressText.hidden = !model?.downloading;
    elements.Progress.setAttribute("aria-label", t("AI 模型下载进度"));
    if (model?.totalBytes > 0) {
      elements.Progress.max = model.totalBytes;
      elements.Progress.value = Math.max(0, Math.min(model.downloadedBytes || 0, model.totalBytes));
    } else elements.Progress.removeAttribute("value");
    elements.ProgressText.textContent = model?.downloading ? `${size(model.downloadedBytes || 0)} / ${size(model.totalBytes)}` : "";
    elements.Privacy.textContent = t("日志仅在本机分析，不上传；会遮盖可识别的秘密，但可能有遗漏。");
    elements.LimitsTitle.textContent = t("资源与兼容性");
    elements.Limits.textContent = t("关闭会结束模型进程，保留下载文件。系统缓存可能稍后回收。计算设备配置为 CPU + ANE；实际 ANE 执行及未测试机型尚未验证。");
    const result = snapshot?.containerId === containerId && !stopping ? snapshot?.result : null;
    elements.Result.hidden = !result;
    elements.Advice.textContent = t("AI 的判断可能有误，请结合日志核实；建议不会自动执行。");
    elements.Answer.textContent = result?.text || "";
    elements.EvidenceTitle.textContent = t("本次分析的日志（已脱敏）");
    elements.Evidence.textContent = result?.evidence || "";
    elements.ResultMeta.textContent = result?.observedAt ? format("分析时间：{time}", { time: result.observedAt }) : "";
    elements.HistoryError.hidden = !snapshot?.historyError;
    elements.HistoryError.textContent = t("分析结果未能保存到本机历史，请检查目录权限或磁盘空间；当前结果仍可查看。");
  }

  async function request(path, body, { keepalive = false } = {}) {
    const requestSequence = ++sequence;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    try {
      const response = await fetch(`${endpoint}/${path}`, {
        method: body === undefined ? "GET" : "POST",
        ...(body === undefined ? {} : { headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }),
        signal: controller.signal, cache: "no-store", keepalive
      });
      const data = await response.json();
      if (!response.ok) {
        const fallback = response.status === 409 ? "另一项 AI 操作正在进行，请核对当前状态。" : response.status === 503 ? "本地 AI 暂不可用，请稍后重试。" : "AI 请求失败，请重试。";
        throw new Error(typeof data.message === "string" && data.message ? data.message : fallback);
      }
      return { data, sequence: requestSequence };
    } finally {
      clearTimeout(timeout);
    }
  }

  function accept(response, token) {
    if (token !== version || response.sequence < appliedSequence) return false;
    appliedSequence = response.sequence;
    snapshot = response.data;
    if (snapshot.containerId === containerId) globalThis.ContainerGUIAILogHistory?.notify(snapshot.historyRecordId);
    if (stopping && released(snapshot)) {
      stopping = false;
      message = "";
    }
    if (snapshot.phase === "error" && !snapshot.enabled && !snapshot.workerPID && owned) {
      desired = false;
      owned = false;
      consent = !snapshot.model.installed;
      awaitingInstall = false;
    }
    if (released(snapshot) && owned && !pending && (!awaitingInstall || !snapshot.model.installed)) {
      desired = false;
      owned = false;
      awaitingInstall = false;
    }
    render();
    schedule();
    return true;
  }

  function schedule() {
    clearTimeout(pollTimer);
    pollTimer = null;
    if (document.visibilityState === "visible" && (snapshot?.enabled || snapshot?.model?.downloading || snapshot?.workerPID || pending || stopping || ["downloading", "loading", "analysing", "stopping"].includes(snapshot?.phase))) {
      pollTimer = setTimeout(() => { void tick(); }, 1500);
    }
  }

  async function refresh() {
    const token = version;
    try {
      const response = await request("status");
      accept(response, token);
    } catch (error) {
      if (token !== version) return;
      message = error.message;
      render();
      schedule();
    }
  }

  async function enable(token = version) {
    if (token !== version || !desired || !owned || !containerId) return;
    pending = "enable";
    awaitingInstall = false;
    lastHeartbeat = Date.now();
    lastAnalysis = -Infinity;
    render();
    try {
      accept(await request("enable", { containerId, language: language() }), token);
    } catch (error) {
      if (token !== version) return;
      desired = false;
      owned = false;
      message = error.message;
      void refresh();
    } finally {
      if (token === version) {
        pending = null;
        render();
        schedule();
      }
    }
  }

  async function install() {
    if (!consent || pending || !snapshot?.model?.totalBytes || !containerId) return;
    const token = ++version;
    consent = false;
    desired = true;
    owned = true;
    awaitingInstall = true;
    lastHeartbeat = Date.now();
    pending = "install";
    message = "";
    render();
    try {
      accept(await request("install", { confirmed: true }), token);
    } catch (error) {
      if (token !== version) return;
      desired = false;
      owned = false;
      awaitingInstall = false;
      consent = true;
      message = error.message;
    } finally {
      if (token === version) {
        pending = null;
        render();
        schedule();
        if (snapshot?.model?.installed && desired) void enable(token);
      }
    }
  }

  async function disable({ keepalive = false } = {}) {
    const onlyConsent = consent && !owned && !snapshot?.enabled && !snapshot?.model?.downloading && !snapshot?.workerPID;
    const token = ++version;
    desired = false;
    owned = false;
    consent = false;
    awaitingInstall = false;
    message = "";
    clearTimeout(pollTimer);
    if (onlyConsent) { render(); return; }
    stopping = true;
    pending = "disable";
    render();
    try {
      accept(await request("disable", {}, { keepalive }), token);
    } catch (error) {
      if (token !== version) return;
      message = error.message;
    } finally {
      if (token === version) {
        pending = null;
        render();
        schedule();
      }
    }
  }

  async function tick() {
    const token = version;
    if (tickingVersion === token) return;
    tickingVersion = token;
    try {
      await refresh();
      if (token !== version || pending || !owned || !desired || document.visibilityState !== "visible") return;
      if ((snapshot?.enabled || snapshot?.phase === "downloading") && Date.now() - lastHeartbeat >= 10_000) {
        lastHeartbeat = Date.now();
        accept(await request("heartbeat", {}), token);
      }
      if (token !== version || !desired) return;
      if (awaitingInstall && snapshot?.model?.installed && !snapshot.enabled && snapshot.phase === "off") {
        await enable(token);
        return;
      }
      if (!snapshot?.enabled || snapshot.containerId !== containerId) return;
      if (snapshot.phase === "ready" && Date.now() - lastAnalysis >= 10_000) {
        lastAnalysis = Date.now();
        accept(await request("analyse", {}), token);
      }
    } catch (error) {
      if (token === version) { message = error.message; render(); }
    } finally {
      if (tickingVersion === token) tickingVersion = null;
      if (token === version) schedule();
    }
  }

  function toggle() {
    if (active()) return disable();
    if (!containerId || !snapshot || pending) return;
    version += 1;
    message = "";
    desired = true;
    if (!snapshot.model.installed) { consent = true; render(); return; }
    owned = true;
    return enable();
  }

  async function setContainer(id) {
    if (id === containerId) return;
    const mustStop = owned || desired;
    containerId = id;
    globalThis.ContainerGUIAILogHistory?.setContainer(id);
    version += 1;
    message = "";
    if (mustStop) await disable();
    else {
      consent = false;
      desired = false;
      snapshot = null;
      render();
    }
    if (containerId) await refresh();
  }

  function releaseOnLeave() {
    if (owned || desired) void disable({ keepalive: true });
    clearTimeout(pollTimer);
  }

  elements.Toggle.addEventListener("click", () => { void toggle(); });
  elements.ConfirmDownload.addEventListener("click", () => { void install(); });
  elements.CancelDownload.addEventListener("click", () => { void disable(); });
  elements.RetryStatus.addEventListener("click", () => { message = ""; void refresh(); });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible") releaseOnLeave();
    else if (containerId) void refresh();
  });
  globalThis.addEventListener("pagehide", releaseOnLeave);
  render();
  return Object.freeze({ setContainer, refresh, languageChanged() { render(); globalThis.ContainerGUIAILogHistory?.languageChanged(); } });
})();
