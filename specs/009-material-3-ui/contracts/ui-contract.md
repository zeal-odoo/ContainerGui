# UI Contract: Material Design 3 视觉系统

## 静态资源契约

1. `index.html` 继续加载本机 `/app.css`、`/app.js`、`/ssh-key-generator.js`、`/odoo-create-form.js` 和本机图标。
2. HTML/CSS 不得引用 `http://`、`https://`、`//cdn`、Google Fonts 或远程 Material Symbols。
3. 现有 DOM `id`、表单字段名、dialog、状态区域和脚本入口保持不变。
4. `app.css` 必须定义完整的浅色 `--md-sys-color-*` 令牌，并在 `prefers-color-scheme: dark` 下覆盖主题角色。
5. `app.css` 必须定义 `--md-sys-typescale-*`、`--md-sys-shape-corner-*` 与 `--md-sys-elevation-level-*` 令牌。

## 组件状态契约

- 所有 button、input、select、textarea、summary 和可聚焦 pre 在 `:focus-visible` 时具有清楚轮廓。
- `.button`、`.button.secondary`、`.button.danger`、`.icon-button` 和 `.disclosure-button` 分别保留原行为与语义。
- `.pill.running`、`.pill.stopped`、`.operation-status.error` 和系统健康状态同时呈现文字与语义色彩。
- `:disabled` 组件不得看起来可点击；现有执行中逻辑继续控制 disabled 属性。
- 折叠箭头保持 `aria-expanded=false` 横向、`aria-expanded=true` 向下。

## 布局契约

- 扩展宽度保持 `.workspace` 的主列表 + `.detail-panel` 支持面板。
- 900px 及以下改为单列；600px 及以下的面板操作和表单栅格不得溢出。
- `.table-wrap` 是表格横向滚动边界；`body` 不应产生横向滚动。
- `prefers-reduced-motion: reduce` 下关闭非必要 transition、animation 和 smooth scrolling。

## 行为兼容契约

- 本功能不新增、删除或修改 HTTP API。
- 本功能不改变自动刷新、容器/镜像操作、日志、SSH、Odoo 创建预设和确认流程。
- 应用版本从 2.10.0 递增至 2.11.0；首页版本徽标由既有 API 回读显示。
