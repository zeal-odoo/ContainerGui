"use strict";

globalThis.ContainerGUIAILogHistory = (() => {
  const endpoint = "/api/v1/ai/logs/history";
  const ids = ["Panel", "Title", "Note", "Refresh", "Message", "List", "Pages", "Previous", "Page", "Next"];
  const elements = Object.fromEntries(ids.map((id) => [id, document.getElementById(`aiHistory${id}`)]));
  let containerId = null, payload = null, page = 1, sequence = 0, controller = null;
  let pending = false, error = "", lastRecordId = null;
  const expanded = new Set();
  const language = () => globalThis.ContainerGUII18n?.language() || "zh";
  const t = (value) => globalThis.ContainerGUII18n?.translate(value) || value;
  const format = (value, replacements) => Object.entries(replacements).reduce((text, [key, replacement]) => text.replaceAll(`{${key}}`, replacement), t(value));
  const time = (value) => new Date(value).toLocaleString(language() === "en" ? "en-US" : "zh-CN", { hour12: false });
  const uuid = (value) => typeof value === "string" && /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value);
  const text = (value, limit) => typeof value === "string" && value.length <= limit;

  function valid(value) {
    return value && Number.isInteger(value.total) && value.total >= 0 && value.total <= 1000
      && Number.isInteger(value.page) && value.page >= 1 && value.page <= Math.max(1, Math.ceil(value.total / 10))
      && value.pageSize === 10 && value.retentionLimit === 1000 && Array.isArray(value.items) && value.items.length <= 10
      && value.items.length === Math.min(10, Math.max(0, value.total - (value.page - 1) * 10))
      && new Set(value.items.map((record) => record.id)).size === value.items.length
      && value.items.every((record) => record.schemaVersion === 1 && uuid(record.id) && record.containerId === containerId
        && ["zh", "en"].includes(record.language) && Number.isFinite(Date.parse(record.createdAt))
        && text(record.model, 300) && text(record.modelRevision, 128) && text(record.appVersion, 32)
        && record.result && text(record.result.text, 6144) && text(record.result.evidence, 6144)
        && Number.isFinite(Date.parse(record.result.observedAt)) && Number.isFinite(record.result.elapsedSeconds)
        && record.result.elapsedSeconds >= 0 && Number.isInteger(record.result.inputTokens) && record.result.inputTokens >= 0
        && Number.isInteger(record.result.outputTokens) && record.result.outputTokens >= 0);
  }

  function node(tag, value, className) {
    const element = document.createElement(tag);
    if (value !== undefined) element.textContent = value;
    if (className) element.className = className;
    return element;
  }

  function exportRecord(record) {
    const blob = new Blob([JSON.stringify(record, null, 2)], { type: "application/json;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = node("a");
    link.href = url;
    link.download = `container-gui-analysis-${record.id}.json`;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }

  function render() {
    elements.Panel.hidden = !containerId;
    elements.Title.textContent = t("分析历史");
    elements.Note.textContent = t("自动保存结果和脱敏日志；关闭 AI 后仍可查看。所有容器合计保留最近 1,000 条，超出清理最旧记录。脱敏可能遗漏，请在导出分享前检查。");
    elements.Refresh.textContent = t("刷新历史");
    elements.Refresh.disabled = pending || !containerId;
    elements.Message.textContent = t(error || (pending ? "正在读取分析历史…" : payload?.total === 0 ? "暂无分析历史。完成 AI 分析后会自动保存。" : ""));
    elements.Message.hidden = !elements.Message.textContent;
    elements.Message.setAttribute("role", error ? "alert" : "status");
    elements.Previous.textContent = t("上一页");
    elements.Next.textContent = t("下一页");
    elements.Previous.disabled = pending || !payload || page <= 1;
    elements.Next.disabled = pending || !payload || page * 10 >= payload.total;
    elements.Pages.hidden = !payload?.total;
    elements.Pages.setAttribute("aria-label", t("分析历史分页"));
    elements.Page.textContent = payload ? format("第 {page} / {pages} 页 · 共 {total} 条", { page, pages: Math.max(1, Math.ceil(payload.total / 10)), total: payload.total }) : "";
    elements.List.replaceChildren();
    for (const record of payload?.items || []) {
      const item = node("details", undefined, "ai-history-record");
      item.open = expanded.has(record.id);
      item.addEventListener("toggle", () => { if (item.open) expanded.add(record.id); else expanded.delete(record.id); });
      item.append(node("summary", `${time(record.createdAt)} · ${record.language === "en" ? "English" : "中文"}`));
      item.append(node("p", `${record.model} · GUI ${record.appVersion}`, "quiet"));
      item.append(node("p", t("AI 的判断可能有误，请结合日志核实；建议不会自动执行。"), "quiet"));
      const answer = node("pre", record.result.text);
      answer.tabIndex = 0;
      item.append(answer);
      const evidence = node("details");
      evidence.append(node("summary", t("本次分析的日志（已脱敏）")));
      const logs = node("pre", record.result.evidence);
      logs.tabIndex = 0;
      evidence.append(logs);
      item.append(evidence, node("p", format("日志采样：{time}", { time: time(record.result.observedAt) }), "quiet"));
      const actions = node("div", undefined, "ai-history-actions");
      const download = node("button", t("导出 JSON"), "button secondary small");
      download.type = "button";
      download.addEventListener("click", () => exportRecord(record));
      const remove = node("button", t("删除记录"), "button danger small");
      remove.type = "button";
      remove.disabled = pending;
      remove.addEventListener("click", () => { void deleteRecord(record); });
      actions.append(download, remove);
      item.append(actions);
      elements.List.append(item);
    }
  }

  async function request(url, body) {
    const token = ++sequence;
    controller?.abort();
    controller = new AbortController();
    const current = controller;
    const timeout = setTimeout(() => current.abort(), 10_000);
    try {
      const response = await fetch(url, { method: body ? "POST" : "GET", cache: "no-store", signal: current.signal,
        ...(body ? { headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) } : {}) });
      if (!response.ok) throw new Error("history_unavailable");
      return { token, data: await response.json() };
    } finally { clearTimeout(timeout); }
  }

  async function refresh(targetPage = page) {
    if (!containerId || !elements.Panel.open || pending) return;
    pending = true;
    error = "";
    const selected = containerId;
    const operation = request(`${endpoint}?containerId=${encodeURIComponent(selected)}&page=${targetPage}`);
    const token = sequence;
    render();
    try {
      const response = await operation;
      if (token !== sequence || selected !== containerId) return;
      if (!valid(response.data)) throw new Error("invalid_history");
      payload = response.data;
      page = payload.page;
    } catch {
      if (token !== sequence) return;
      payload = null;
      error = "无法读取分析历史，请检查本机历史目录后重试。";
    } finally {
      if (token === sequence) { pending = false; render(); }
    }
  }

  async function deleteRecord(record) {
    if (pending || !confirm(format("删除 {container} 在 {time} 的分析记录？此操作无法撤销。", { container: record.containerId, time: time(record.createdAt) }))) return;
    pending = true;
    error = "";
    const operation = request(`${endpoint}/delete`, { id: record.id, confirmationId: record.id });
    const token = sequence;
    render();
    try {
      const response = await operation;
      if (token !== sequence) return;
      if (response.data?.deletedId !== record.id) throw new Error("invalid_delete");
      expanded.delete(record.id);
      pending = false;
      await refresh();
    } catch {
      if (token !== sequence) return;
      error = "删除记录失败，请刷新历史确认后重试。";
    } finally {
      if (token === sequence) { pending = false; render(); }
    }
  }

  function setContainer(id) {
    if (id === containerId) return;
    sequence += 1;
    controller?.abort();
    containerId = id;
    pending = false;
    payload = null;
    page = 1;
    error = "";
    lastRecordId = null;
    expanded.clear();
    elements.Panel.open = false;
    render();
  }

  function notify(id) {
    if (!id || id === lastRecordId) return;
    lastRecordId = id;
    if (elements.Panel.open && !pending) void refresh();
  }

  elements.Panel.addEventListener("toggle", () => { if (elements.Panel.open) void refresh(); });
  elements.Refresh.addEventListener("click", () => { void refresh(); });
  elements.Previous.addEventListener("click", () => { if (page > 1) void refresh(page - 1); });
  elements.Next.addEventListener("click", () => { if (payload && page * 10 < payload.total) void refresh(page + 1); });
  function cancel() { sequence += 1; controller?.abort(); pending = false; }
  globalThis.addEventListener("pagehide", cancel);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible") cancel();
    else void refresh();
  });
  render();
  return Object.freeze({ setContainer, refresh, notify, languageChanged: render });
})();
