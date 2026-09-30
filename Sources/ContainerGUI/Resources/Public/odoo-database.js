"use strict";

globalThis.ContainerGUIOdooDatabase = (() => {
  const restrictions = {
    stoppedInternal: "配置保存在已停止容器内部，官方 CLI 无法直接编辑。只有容器运行时才能修改；本工具不会自动启动、迁移或重建容器。",
    unsupportedLocation: "此容器使用自定义配置位置或命令行覆盖，暂不支持安全编辑。",
    singleFileMount: "单文件挂载暂不支持安全替换；仅支持挂载整个 /etc/odoo 目录。",
    configUnavailable: "配置文件不可安全编辑，请检查位置、权限和容器状态。",
    invalidConfig: "配置格式不受支持，无法安全编辑数据库地址。",
    notOdoo: "此功能仅适用于 Odoo 容器。"
  };

  function isOdoo(detail) {
    const summary = detail?.summary || detail;
    const image = summary?.imageReference?.split("/").pop()?.split(/[:@]/)[0];
    const process = detail?.configuration?.initProcess;
    return image === "odoo" || [process?.executable, process?.arguments?.[0]].some((value) => value?.split("/").pop() === "odoo");
  }

  function postgresOptions(items) {
    return items.filter((item) => item.state === "running" && item.imageReference?.split("/").pop()?.split(/[:@]/)[0] === "postgres" && item.ipv4Address)
      .map((item) => ({ id: item.id, name: item.displayName || item.id, host: item.ipv4Address.split("/")[0], port: 5432 }));
  }

  function createSession({ request, onChange, wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)) }) {
    let state = { containerId: null, view: null, host: "", port: "5432", busy: false, error: "", saved: false };
    let generation = 0;
    let controller = null;
    let retry = null;
    const notify = () => onChange({ ...state });
    const endpointURL = (id) => `/api/v1/containers/${encodeURIComponent(id)}/odoo/database-config`;
    const current = (token, id) => generation === token && state.containerId === id;
    const begin = () => { controller?.abort(); controller = new AbortController(); return ++generation; };

    async function reload() {
      const id = state.containerId;
      if (!id) return;
      const token = begin();
      state = { ...state, busy: true, error: "", saved: false };
      notify();
      try {
        const view = await request(endpointURL(id), { signal: controller.signal });
        if (!current(token, id)) return;
        if (view.containerId !== id) throw new Error("数据库配置目标不一致，请重新读取。");
        state = { ...state, view, host: view.host || "", port: String(view.port || 5432) };
        retry = null;
      } catch (error) {
        if (current(token, id)) state.error = error.message;
      } finally {
        if (current(token, id)) { state.busy = false; notify(); }
      }
    }

    async function open(id) {
      controller?.abort();
      generation++;
      retry = null;
      state = { containerId: id, view: null, host: "", port: "5432", busy: false, error: "", saved: false };
      await reload();
    }

    function close() {
      controller?.abort();
      generation++;
      retry = null;
      state = { containerId: null, view: null, host: "", port: "5432", busy: false, error: "", saved: false };
      notify();
    }

    function edit(fields) {
      if (!state.containerId || state.busy) return;
      state = { ...state, ...fields, error: "", saved: false };
      notify();
    }

    async function save() {
      if (state.busy || !state.view?.editable) return;
      const id = state.containerId;
      const body = JSON.stringify({ host: state.host.trim(), port: Number(state.port), confirmationTarget: id, expectedRevision: state.view.revision });
      if (!retry || retry.body !== body) retry = { body, key: crypto.randomUUID() };
      const key = retry.key;
      const token = begin();
      const signal = controller.signal;
      state = { ...state, busy: true, error: "", saved: false };
      notify();
      try {
        let operation = await request(endpointURL(id), { method: "POST", headers: { "Content-Type": "application/json", "Idempotency-Key": key }, body, signal });
        for (let count = 0; !["succeeded", "failed", "cancelled"].includes(operation.state); count++) {
          if (!current(token, id)) return;
          if (count >= 120) throw new Error("保存尚未确认，请重新读取配置核对，不要重复创建操作。");
          await wait(500);
          if (!current(token, id)) return;
          operation = await request(`/api/v1/operations/${encodeURIComponent(operation.id)}`, { signal });
        }
        if (!current(token, id)) return;
        if (operation.state !== "succeeded") throw new Error(operation.error?.message || "数据库配置保存失败，请重新读取后重试。");
        const observed = operation.readback?.observedOdooDatabase;
        if (!operation.readback?.matchedExpectation || observed?.containerId !== id || observed.host !== JSON.parse(body).host || observed.port !== JSON.parse(body).port) {
          throw new Error("保存尚未确认，请重新读取配置核对，不要重复创建操作。");
        }
        state = { ...state, view: observed, host: observed.host, port: String(observed.port), saved: true };
        retry = null;
      } catch (error) {
        if (current(token, id)) state.error = error.message;
      } finally {
        if (current(token, id)) { state.busy = false; notify(); }
      }
    }

    return { get snapshot() { return { ...state }; }, open, close, edit, save, reload };
  }

  function attach({ request, openDialog, closeDialog, getContainers }) {
    const element = (id) => document.getElementById(id);
    const dialog = element("odooDatabaseDialog");
    const form = element("odooDatabaseForm");
    const host = element("odooDatabaseHost");
    const port = element("odooDatabasePort");
    const select = element("odooDatabasePostgres");
    const status = element("odooDatabaseStatus");
    const session = createSession({ request, onChange: (state) => {
      if (!state.containerId) return;
      element("odooDatabaseTarget").textContent = state.containerId;
      if (host.value !== state.host) host.value = state.host;
      if (port.value !== state.port) port.value = state.port;
      const editable = state.view?.editable === true && !state.busy;
      host.disabled = port.disabled = select.disabled = !editable;
      element("saveOdooDatabaseButton").disabled = !editable;
      element("reloadOdooDatabaseButton").disabled = state.busy;
      status.className = state.error ? "inline-error" : "quiet";
      status.textContent = state.error || (state.busy ? "正在读取或保存数据库配置…" : state.saved ? "配置已保存并回读验证，私有备份已创建。请自行启动或重启容器使其生效。" : state.view?.restriction ? restrictions[state.view.restriction] || restrictions.configUnavailable : "只修改数据库地址和端口，保留密码等其他配置。保存不会自动启动或重启容器。");
    } });
    host.addEventListener("input", () => session.edit({ host: host.value }));
    port.addEventListener("input", () => session.edit({ port: port.value }));
    select.addEventListener("change", () => {
      const chosen = postgresOptions(getContainers()).find((item) => item.id === select.value);
      if (chosen) session.edit({ host: chosen.host, port: String(chosen.port) });
    });
    form.addEventListener("submit", (event) => { event.preventDefault(); if (form.reportValidity()) void session.save(); });
    element("reloadOdooDatabaseButton").addEventListener("click", () => { select.value = ""; void session.reload(); });
    const close = () => { session.close(); closeDialog(dialog, "cancel"); };
    element("cancelOdooDatabaseButton").addEventListener("click", close);
    dialog.addEventListener("cancel", (event) => { event.preventDefault(); close(); });
    dialog.addEventListener("close", () => session.close());
    return {
      open(id) {
        select.replaceChildren();
        const placeholder = document.createElement("option");
        placeholder.value = "";
        placeholder.textContent = "手动输入或选择运行中的 PostgreSQL";
        select.append(placeholder);
        for (const item of postgresOptions(getContainers())) {
          const option = document.createElement("option");
          option.value = item.id;
          option.textContent = `${item.name} · ${item.host}:5432`;
          select.append(option);
        }
        openDialog(dialog);
        void session.open(id);
      },
      syncTarget(id) { if (session.snapshot.containerId && session.snapshot.containerId !== id) close(); },
      close
    };
  }

  return Object.freeze({ createSession, postgresOptions, isOdoo, attach });
})();
