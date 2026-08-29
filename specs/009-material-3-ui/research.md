# Phase 0 Research: Material Design 3 界面视觉升级

## 1. 参考版本与采用范围

**Decision**: 以当前官方 Material Design 3 / M3 Expressive 为方向，采用语义颜色、灵活排版、对比形状、有限层级、状态层与自适应布局；不复制官网素材和高装饰性动画。

**Rationale**:

- 官方首页将 M3 描述为开放设计系统，并在当前更新中强调更鲜明的色彩、直观动效、自适应组件、灵活排版和对比形状。
- Container GUI 是桌面管理工具，主要目标是快速读取大量运行状态；克制使用表达性元素能改善层级而不牺牲信息密度。
- 视觉参考必须服从现有任务路径和危险操作边界，不能因追求官网效果改变控制含义。

**Alternatives considered**:

- 直接复制 Material 官网布局与素材：拒绝；官网是内容站点，任务结构与本地容器控制台不同。
- 引入完整 Material Web 组件库：拒绝；官方组件页面仍标示部分 Web Expressive 实现不可用，且会引入构建/运行依赖。
- 只把主题色改为紫色：拒绝；无法形成可验证的颜色角色、表面层级和组件状态体系。

**Official reference**: https://m3.material.io/

## 2. 语义色彩与主题

**Decision**: CSS 使用 `--md-sys-color-*` 语义令牌，覆盖 primary、secondary、tertiary、error、surface、surface-container、outline 及成对的 `on-*` 前景色；浅色和深色分别完整映射。

**Rationale**:

- 官方色彩角色页面将标准角色分为 primary、secondary、tertiary、error、surface 和 outline 六组，并要求按成对角色组合以维持可访问对比。
- 主要操作使用 primary；次要操作和选中状态使用 secondary/primary container；危险行为固定使用 error；大面积背景使用 surface 系列。
- 状态仍保留文字，避免只靠颜色表达运行、停止或失败。

**Alternative considered**: 保留现有 `--accent/--panel/--bad` 别名作为主体系：拒绝；角色数量不足，组件容易重新出现硬编码颜色。

**Official reference**: https://m3.material.io/styles/color/roles

## 3. 排版、形状与信息密度

**Decision**: 使用系统字体栈，建立 display/headline/title/body/label 令牌；大标题和主要操作使用强调字重，正文与表格优先可读；采用 12、16、20、28px 及 full 圆角层级。

**Rationale**:

- 官方 M3 类型比例从 Display Large 到 Label Small，基础与强调样式共同表达层级；产品不需要使用全部类型样式。
- 使用本机系统字体可覆盖中文并保持离线，不依赖 Google Fonts。
- 控制台表格继续紧凑，只有英雄标题、面板标题和重要操作加强表现，避免所有文字同时加粗。

**Alternative considered**: 下载或远程加载 Roboto/Google Sans：拒绝；增加外部依赖且中文覆盖不完整。

**Official reference**: https://m3.material.io/styles/typography/type-scale-tokens

## 4. 表面层级与动效

**Decision**: 静态页面主要通过 surface container 的色调差与细轮廓表达层级，仅顶部栏、健康卡、弹窗和 toast 使用有限阴影；悬停/按下使用短时状态层，减少动态效果偏好下禁用非必要过渡。

**Rationale**:

- 官方 elevation 页面限定少量层级，并优先通过表面色调差表达分离；阴影应少用，较高层级留给交互与模态内容。
- 现有页面大量同强度阴影会让层级失焦；调整为色调表面可提升主次关系。
- 现有折叠箭头保留横向收起、向下展开语义，只调整速度与焦点样式。

**Official reference**: https://m3.material.io/styles/elevation/applying-elevation

## 5. 状态与可访问性

**Decision**: 所有按钮、输入、行、折叠控件和链接具有启用、悬停、焦点、按下、禁用状态；焦点使用高对比轮廓与外移，不依赖背景色变化。

**Rationale**:

- 官方状态规范要求一致表达 enabled、disabled、hover、focused、pressed 等状态，并建议使用不止一个视觉指标。
- 危险操作、状态标签和错误消息保留明确文字；键盘焦点覆盖 button、input、select、textarea、summary 和可聚焦日志。
- 不新增动画依赖，CSS 状态层即可满足桌面指针与键盘反馈。

**Official reference**: https://m3.material.io/foundations/interaction/states/overview

## 6. 自适应布局

**Decision**: 继续采用“主列表 + 支持详情面板”的扩展布局；中等和紧凑宽度转为单列，表格在自身容器内滚动，面板操作区按空间换行。

**Rationale**:

- 官方 canonical layout 将 supporting pane 用于主内容与辅助内容组合，并建议针对不同断点调整配置。
- 现有 HTML 已具备该结构，只需强化断点、最小宽度与溢出规则，不需要重排 DOM 或增加导航栏。

**Official reference**: https://m3.material.io/foundations/layout/canonical-examples/overview

## 7. 实现边界

**Decision**: 主要重写 `app.css`，`index.html` 只增加主题元数据或无行为标记；`app.js` 不修改，后端/API 不修改。

**Rationale**:

- 现有 DOM 类名覆盖所有需要升级的组件，CSS 已包含深色和三个宽度断点。
- 保留脚本可最大限度降低容器操作、镜像操作、SSH、Odoo 表单和折叠行为回归风险。
- 静态资源断言可先行失败并验证设计令牌、组件状态、主题和无远程资源约束。
