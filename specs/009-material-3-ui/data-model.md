# Phase 1 Data Model: Material Design 3 界面视觉升级

本功能没有业务数据或持久化模型变化。以下模型描述静态视觉系统及其可验证关系。

## Material3Theme

| 字段 | 类型 | 约束/含义 |
|---|---|---|
| `mode` | `light \| dark` | 由系统主题偏好决定，不单独持久化 |
| `colorRoles` | `Material3ColorRoles` | 每个容器色必须有对应可读前景色 |
| `typeScale` | `Material3TypeScale` | 至少覆盖 display、headline、title、body、label |
| `shapeScale` | `Material3ShapeScale` | 统一 small、medium、large、extra-large、full |
| `elevationLevels` | `Material3ElevationLevels` | 静态层级少量使用，模态/浮层更高 |
| `motion` | `standard \| reduced` | 系统减少动态效果时切换为 reduced |

## Material3ColorRoles

必须包含并成对使用：

- `primary` / `on-primary`
- `primary-container` / `on-primary-container`
- `secondary` / `on-secondary`
- `secondary-container` / `on-secondary-container`
- `tertiary-container` / `on-tertiary-container`
- `error` / `on-error`
- `error-container` / `on-error-container`
- `surface` / `on-surface`
- `surface-container-low`、`surface-container`、`surface-container-high`
- `on-surface-variant`
- `outline` / `outline-variant`
- `scrim`、`shadow`

## ComponentVisualState

```text
enabled ──hover──> hovered ──press──> pressed
   │                  │
   ├──focus────────> focused
   └──disable──────> disabled

操作完成后回到 enabled；执行中可用 disabled + 明确状态文字表达。
```

每个状态至少包含容器/文字/轮廓中的两种可辨识变化。危险操作始终使用 error 角色，不能因悬停或禁用变成主要操作语义。

## AdaptiveLayoutState

| 状态 | 视口范围 | 页面行为 |
|---|---|---|
| `expanded` | 大于 1200px | 主列表与支持详情并排；完整表格列 |
| `medium` | 601px–1200px | 表格隐藏低优先级列；900px 以下支持详情转单列 |
| `compact` | 不大于 600px | 单列面板、操作区换行、局部表格滚动、缩小页面边距 |

## VisualComponentMapping

| 组件 | 表面/强调 | 形状 | 主要状态 |
|---|---|---|---|
| 顶部栏 | surface-container | large bottom corners | sticky、轻微层级 |
| 统计卡/面板 | surface-container-low/high | large/extra-large | hover 仅用于可交互元素 |
| 主要按钮 | primary/on-primary | full | hover、focus、pressed、disabled |
| 次要按钮 | secondary-container | full | hover、focus、pressed、disabled |
| 危险按钮 | error/on-error | full | hover、focus、pressed、disabled |
| 状态标签 | 对应 container/on-container | full | 文字 + 颜色 |
| 输入字段 | surface-container-high + outline | medium | focus、invalid、disabled |
| 弹窗 | surface-container-high | extra-large | backdrop + elevation |
| 日志代码区 | inverse surface | medium | focus、overflow |
