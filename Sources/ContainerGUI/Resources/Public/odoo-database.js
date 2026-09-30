"use strict";

globalThis.ContainerGUIOdooDatabase = (() => {
  const restrictions = {
    stoppedInternal: "配置保存在已停止容器内部，官方 CLI 无法直接编辑。只有容器运行时才能修改；本工具不会自动启动、迁移或重建容器。",
    unsupportedLocation: "未找到唯一可安全编辑的已挂载连接配置，或使用模板、自定义位置、命令行覆盖。暂不支持安全编辑。",
    singleFileMount: "单文件挂载暂不支持安全替换；仅支持挂载整个 /etc/odoo 目录。",
    configUnavailable: "配置文件不可安全编辑，请检查位置、权限和容器状态。",
    invalidConfig: "配置格式不受支持，无法安全编辑数据库地址。",
    notOdoo: "此功能仅适用于 Odoo 容器。",
    unsupported: "未识别到此容器可编辑的连接配置，不会添加未经应用支持的参数。",
    runningSingleFile: "此配置是单文件挂载。请先自行停止容器后再编辑；本工具不会自动停止或重建容器。",
    invalidConnectionConfig: "配置包含不支持或不明确的连接格式。动态地址、上游组、模板及额外 include 暂不支持安全编辑。"
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

  function createSession({ request, onChange, unified = false, wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)) }) {
    let state = { containerId: null, view: null, endpointId: "", host: "", port: "5432", busy: false, error: "", saved: false };
    let generation = 0;
    let controller = null;
    let retry = null;
    const notify = () => onChange({ ...state });
    const endpointURL = (id) => `/api/v1/containers/${encodeURIComponent(id)}/${unified ? "connections" : "odoo/database-config"}`;
    const adaptOdoo = (view) => view && ({ containerId: view.containerId, kind: "database", editable: view.editable, revision: view.revision, storage: view.storage, restriction: view.restriction, endpoints: view.host == null ? [] : [{ id: "database", label: "Odoo", host: view.host, port: view.port }] });
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
        if (view.containerId !== id) throw new Error(unified ? "连接配置目标不一致，请重新读取。" : "数据库配置目标不一致，请重新读取。");
        const endpoint = unified ? view.endpoints?.find((item) => item.id === state.endpointId) || view.endpoints?.[0] : view;
        state = { ...state, view, endpointId: unified ? endpoint?.id || "" : "", host: endpoint?.host || "", port: String(endpoint?.port || 5432) };
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
      state = { containerId: id, view: null, endpointId: "", host: "", port: "5432", busy: false, error: "", saved: false };
      await reload();
    }

    function close() {
      controller?.abort();
      generation++;
      retry = null;
      state = { containerId: null, view: null, endpointId: "", host: "", port: "5432", busy: false, error: "", saved: false };
      notify();
    }

    function edit(fields) {
      if (!state.containerId || state.busy) return;
      state = { ...state, ...fields, error: "", saved: false };
      notify();
    }

    function selectEndpoint(id) {
      if (state.busy) return;
      const endpoint = state.view?.endpoints?.find((item) => item.id === id);
      if (!endpoint) return;
      retry = null;
      edit({ endpointId: id, host: endpoint.host, port: String(endpoint.port) });
    }

    async function save() {
      if (state.busy || !state.view?.editable || (unified && !state.view.endpoints?.some((item) => item.id === state.endpointId))) return;
      const id = state.containerId;
      const captured = { ...(unified ? { endpointId: state.endpointId } : {}), host: state.host.trim(), port: Number(state.port), confirmationTarget: id, expectedRevision: state.view.revision };
      const body = JSON.stringify(captured);
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
        if (operation.state !== "succeeded") throw new Error(operation.error?.message || (unified ? "连接配置保存失败，请重新读取后重试。" : "数据库配置保存失败，请重新读取后重试。"));
        const observed = unified ? operation.readback?.observedConnections || adaptOdoo(operation.readback?.observedOdooDatabase) : operation.readback?.observedOdooDatabase;
        const endpoint = unified ? observed?.endpoints?.find((item) => item.id === captured.endpointId) : observed;
        if (!operation.readback?.matchedExpectation || observed?.containerId !== id || endpoint?.host !== captured.host || endpoint?.port !== captured.port) {
          throw new Error("保存尚未确认，请重新读取配置核对，不要重复创建操作。");
        }
        state = { ...state, view: observed, host: endpoint.host, port: String(endpoint.port), saved: true };
        retry = null;
      } catch (error) {
        if (current(token, id)) state.error = error.message;
      } finally {
        if (current(token, id)) { state.busy = false; notify(); }
      }
    }

    return { get snapshot() { return { ...state }; }, open, close, edit, selectEndpoint, save, reload };
  }

  function attach({ request, openDialog, closeDialog, getContainers }) {
    const element = (id) => document.getElementById(id);
    const dialog = element("odooDatabaseDialog");
    const form = element("odooDatabaseForm");
    const host = element("odooDatabaseHost");
    const port = element("odooDatabasePort");
    const select = element("odooDatabasePostgres");
    const endpoints = element("odooDatabaseEndpoint");
    const status = element("odooDatabaseStatus");
    let renderedView = null;
    const session = createSession({ request, unified: true, onChange: (state) => {
      if (!state.containerId) return;
      element("odooDatabaseTarget").textContent = state.containerId;
      if (host.value !== state.host) host.value = state.host;
      if (port.value !== state.port) port.value = state.port;
      if (renderedView !== state.view) {
        renderedView = state.view;
        endpoints.replaceChildren();
        for (const endpoint of state.view?.endpoints || []) {
          const option = document.createElement("option");
          option.value = endpoint.id;
          option.textContent = `${endpoint.label} · ${endpoint.host}:${endpoint.port}`;
          endpoints.append(option);
        }
      }
      endpoints.value = state.endpointId;
      element("odooDatabaseEndpointField").hidden = (state.view?.endpoints?.length || 0) < 2;
      const database = state.view?.kind === "database";
      element("odooDatabaseType").textContent = database ? "数据库连接" : state.view?.kind === "backend" ? "后端服务" : "连接配置";
      element("odooDatabasePostgresField").hidden = !database;
      const editable = state.view?.editable === true && !state.busy;
      host.disabled = port.disabled = select.disabled = endpoints.disabled = !editable;
      element("saveOdooDatabaseButton").disabled = !editable;
      element("reloadOdooDatabaseButton").disabled = state.busy;
      status.className = state.error ? "inline-error" : "quiet";
      status.textContent = state.error || (state.busy ? "正在读取或保存连接配置…" : state.saved ? "配置已保存并回读验证，私有备份已创建。请自行启动或重启容器使其生效。" : state.view?.restriction ? restrictions[state.view.restriction] || restrictions.unsupportedLocation : "只修改选中连接的地址和端口，保留密码、协议、路径及其他配置。保存不会自动启动、重启或检测连接。");
    } });
    host.addEventListener("input", () => session.edit({ host: host.value }));
    port.addEventListener("input", () => session.edit({ port: port.value }));
    endpoints.addEventListener("change", () => session.selectEndpoint(endpoints.value));
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
