"use strict";

globalThis.ContainerGUIDiskHealth = (() => {
  const INTERVAL_MS = 5000;
  const labels = { passed: "健康检查通过", failing: "硬件故障预警", warning: "需要关注", unavailable: "无法检测" };
  const tones = { passed: "running", failing: "error", warning: "stopping", unavailable: "unknown" };

  function validSnapshot(value) {
    return value && Array.isArray(value.disks) && !value.error &&
      Number.isFinite(Date.parse(value.observedAt)) && value.disks.every((disk) =>
        typeof disk.id === "string" && typeof disk.model === "string" &&
        Object.hasOwn(labels, disk.health) && Array.isArray(disk.spaces));
  }

  function lowSpace(space) {
    return Number.isFinite(space.totalBytes) && space.totalBytes > 0 &&
      Number.isFinite(space.freeBytes) && space.freeBytes >= 0 && space.freeBytes / space.totalBytes < 0.1;
  }

  function formatPowerOnTime(hours) {
    if (!Number.isSafeInteger(hours) || hours < 0) return "无法获取";
    const days = Math.floor(hours / 24);
    return `${Math.floor(days / 365)}年/${Math.floor((days % 365) / 30)}月/${days % 365 % 30}天`;
  }

  function start(request, formatBytes) {
    const section = document.getElementById("diskHealthSection");
    const cards = document.getElementById("diskHealthCards");
    const status = document.getElementById("diskHealthStatus");
    const error = document.getElementById("diskHealthError");
    const empty = document.getElementById("diskHealthEmpty");
    const button = document.getElementById("refreshDisksButton");
    const counts = ["diskTotalCount", "diskPassedCount", "diskAttentionCount", "diskUnknownCount"].map((id) => document.getElementById(id));
    let active = false;
    let controller = null;
    let snapshot = null;
    let lastSuccess = null;

    function node(tag, text, className = "") {
      const element = document.createElement(tag);
      if (text !== undefined) element.textContent = text;
      element.className = className;
      return element;
    }

    function render() {
      cards.replaceChildren();
      empty.hidden = !snapshot || snapshot.disks.length !== 0;
      const disks = snapshot?.disks ?? [];
      const values = [disks.length, disks.filter((d) => d.health === "passed").length,
        disks.filter((d) => ["failing", "warning"].includes(d.health)).length,
        disks.filter((d) => d.health === "unavailable").length];
      counts.forEach((element, index) => { element.textContent = snapshot ? String(values[index]) : "—"; });
      for (const disk of disks) {
        const card = node("article", undefined, "disk-card");
        card.dataset.diskId = disk.id;
        const header = node("div", undefined, "disk-card-heading");
        const title = node("h2", disk.spaces.flatMap((space) => space.names).join(" / ") || disk.model);
        title.setAttribute("translate", "no");
        header.append(title, node("span", labels[disk.health], `pill ${tones[disk.health]}`));
        const model = node("p", `${disk.model} · ${disk.id}`, "quiet");
        model.setAttribute("translate", "no");
        const facts = node("div", undefined, "disk-facts");
        facts.append(node("span", disk.internalDisk === true ? "内置硬盘" : disk.internalDisk === false ? "外置硬盘" : "位置未知"),
          node("span", disk.solidState === true ? "固态硬盘" : disk.solidState === false ? "机械硬盘" : "介质未知"),
          node("span", disk.connection || "连接方式未知"));
        const capacity = node("p", undefined, "disk-capacity");
        capacity.append(node("span", "硬盘容量"), node("strong", formatBytes(disk.capacityBytes)));
        const usage = node("p", undefined, "disk-usage");
        const duration = formatPowerOnTime(disk.powerOnHours);
        usage.append(node("span", "累计使用时间"), node("strong", duration));
        card.append(header, model, facts, capacity, usage,
          node("small", duration === "无法获取" ? "无法读取累计通电时间" : `累计通电 ${disk.powerOnHours} 小时`, "quiet"));
        for (const space of disk.spaces) {
          const row = node("div", undefined, "disk-space");
          const name = node("span", space.names.join(" / "));
          name.setAttribute("translate", "no");
          const amount = node("p");
          amount.append(node("span", "可用空间"), node("strong", `${formatBytes(space.freeBytes)} / ${formatBytes(space.totalBytes)}`));
          row.append(name, amount);
          if (space.shared) row.append(node("small", "APFS 共享空间，不重复累加", "quiet"));
          if (lowSpace(space)) row.append(node("p", "可用空间不足 10%", "disk-space-warning"));
          card.append(row);
        }
        if (!disk.spaces.length) card.append(node("p", "空间信息无法读取或磁盘未格式化", "quiet"));
        if (disk.health === "failing") card.append(node("p", "请尽快备份并检查或更换硬盘。", "disk-failure"));
        if (disk.health === "warning") card.append(node("p", "检测到健康告警，请检查硬盘并确认备份。", "disk-space-warning"));
        if (disk.health === "unavailable") {
          card.append(node("p", disk.reason === "tool_unavailable" ?
            "系统未提供健康结果；安装 smartmontools 可扩展部分外置硬盘的检测支持。" :
            "无法读取健康结果；请检查连接、设备支持或访问权限。", "quiet"));
        }
        if (disk.source) card.append(node("small", disk.source === "macos" ? "S.M.A.R.T. · macOS" : "S.M.A.R.T. · smartmontools", "quiet"));
        cards.append(card);
      }
      globalThis.ContainerGUII18n?.apply(section);
    }

    function renderStatus(text) {
      status.replaceChildren(node("span", text));
      if (lastSuccess) {
        status.append(node("span", "上次成功检测"), node("time", new Date(lastSuccess).toLocaleTimeString(globalThis.ContainerGUII18n?.locale())));
      }
      globalThis.ContainerGUII18n?.apply(status);
    }

    async function refresh() {
      if (!active || document.visibilityState !== "visible" || controller) return;
      const pending = new AbortController();
      controller = pending;
      button.disabled = true;
      section.setAttribute("aria-busy", "true");
      renderStatus("正在检测硬盘…");
      const timeout = window.setTimeout(() => pending.abort(), 25000);
      try {
        const result = await request("/api/v1/system/disks", { signal: pending.signal });
        if (!active || controller !== pending) return;
        if (pending.signal.aborted) throw new Error("Disk reading timed out");
        if (!validSnapshot(result)) throw new Error("Disk readings unavailable");
        snapshot = result;
        lastSuccess = result.observedAt;
        error.hidden = true;
        renderStatus("每 5 秒自动更新");
        render();
      } catch {
        if (!active || controller !== pending || document.visibilityState !== "visible") return;
        snapshot = null;
        error.hidden = false;
        renderStatus("本次检测失败");
        render();
      } finally {
        window.clearTimeout(timeout);
        if (controller === pending) {
          controller = null;
          button.disabled = false;
          section.setAttribute("aria-busy", "false");
        }
      }
    }

    function setActive(value) {
      const changed = active !== value;
      active = value;
      if (!active) stop();
      else if (changed) void refresh();
    }

    function stop() {
      controller?.abort();
      controller = null;
      button.disabled = false;
      section.setAttribute("aria-busy", "false");
    }

    button.addEventListener("click", refresh);
    document.addEventListener("container-gui-language-change", () => {
      if (active) renderStatus(controller ? "正在检测硬盘…" : snapshot ? "每 5 秒自动更新" : "本次检测失败");
    });
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") void refresh();
      else stop();
    });
    window.addEventListener("pagehide", stop);
    window.setInterval(refresh, INTERVAL_MS);
    return { setActive, refresh };
  }

  return Object.freeze({ start, validSnapshot, lowSpace, formatPowerOnTime, INTERVAL_MS });
})();
