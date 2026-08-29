# Feature Specification: Material 3 渐进响应动效

**Feature Branch**: `main`

**Created**: 2026-08-30

**Status**: Implemented

**Input**: User description: "根据 Material 3 的风格，所有的按钮展示的窗体都是有动画，那种渐进响应式的动画效果，使窗体显示不那么生硬"

## User Scenarios & Testing

### User Story 1 - 平滑打开和关闭操作窗体 (Priority: P1)

用户点击“创建容器”“拉取镜像”或需要二次确认的操作后，窗体和背景遮罩以连贯的缩放、位移和淡入效果出现；取消、确认或按 Escape 时以更短的反向效果退出。

**Independent Test**: 分别打开三个现有 dialog，确认进入、退出及遮罩均有动画，退出结束后 dialog 才真正关闭，原焦点能恢复。

**Acceptance Scenarios**:

1. **Given** dialog 未打开，**When** 用户点击对应按钮，**Then** dialog 从轻微缩小和下移状态渐进到稳定位置，遮罩同步淡入。
2. **Given** dialog 已打开，**When** 用户取消、确认或按 Escape，**Then** dialog 与遮罩先执行短退出动画，再完成关闭。
3. **Given** 用户快速重复操作，**When** 上一次关闭动画尚未结束，**Then** 界面不会留下错误 class、重复 dialog 或不可操作遮罩。

### User Story 2 - 平滑展示按钮触发的内容 (Priority: P2)

用户查看或关闭容器详情、展开或收起本机镜像以及看到操作提示时，内容以与 Material 3 一致的渐进效果变化，而不是瞬间跳变。

**Independent Test**: 点击详情、关闭详情、折叠/展开本机镜像并触发一个只读提示，确认内容连续变化且布局结束状态正确。

**Acceptance Scenarios**:

1. **Given** 用户点击“查看详情”，**When** 详情被加载，**Then** 支持面板从右侧柔和进入并轻微回稳，内部区块分段显现；关闭时先淡出再显示占位内容。
2. **Given** 本机镜像区域已展开，**When** 用户点击横向/向下箭头，**Then** 内容高度与透明度连续收起或展开，箭头语义保持不变。
3. **Given** 操作产生 toast 或状态消息，**When** 消息显示或消失，**Then** 其进入和退出均有短效果动画。

### User Story 3 - 保持快速与无障碍 (Priority: P3)

偏好减少动态效果的用户仍可立即完成所有操作；动效不延迟提交、不改变现有 API、安全确认或键盘行为。

**Independent Test**: 模拟 `prefers-reduced-motion: reduce`，确认窗体和内容仍能正确开关，非必要动画缩短到近乎即时。

## Edge Cases

- Escape、取消按钮和 `method=dialog` 确认按钮必须走同一个关闭流程。
- 动画期间再次打开或关闭同一 dialog，不得遗留不可见遮罩或错误的 `open` 状态。
- 长表单和窄屏 dialog 必须从当前视口中心进入，不得溢出屏幕。
- 自动刷新不得让容器表格每五秒整体闪烁或重复播放装饰动画。
- `prefers-reduced-motion: reduce` 下仍必须完成状态切换和焦点恢复。

## Requirements

- **FR-001**: 系统 MUST 为全部现有 dialog 提供进入和退出动效，并同步动画化 backdrop。
- **FR-002**: 空间变化 MUST 使用独立的进入减速与退出加速曲线；遮罩和颜色等效果变化 MUST 使用较短时长。
- **FR-003**: dialog MUST 在退出动效完成后才调用原生 `close()`，并保留正确 `returnValue`。
- **FR-004**: Escape、取消、确认、创建成功和拉取成功 MUST 复用统一 dialog 关闭机制。
- **FR-005**: 容器详情 MUST 支持进入与退出动效；本机镜像 MUST 支持连续高度、透明度及轻微位移动效。
- **FR-006**: toast 与操作状态 MUST 有克制的进入反馈，按钮 MUST 保持清晰的按下响应。
- **FR-007**: 所有动效 MUST 尊重 `prefers-reduced-motion`，且不得依赖远程库或新增前端构建链。
- **FR-008**: 实现 MUST 保留现有 DOM 标识、中文文案、API 契约、危险确认、焦点与容器操作逻辑。
- **FR-009**: 自动化测试 MUST 覆盖动效令牌、dialog 双向动画、内容展示动效和减少动态效果契约。
- **FR-010**: 应用版本 MUST 递增，并与规格、测试和实现一起提交 Git。
- **FR-011**: 详情进入动效 MUST 只在首次打开或切换容器时播放；五秒自动刷新不得重复触发进入动效。

## Success Criteria

- **SC-001**: 三个现有 dialog 的打开、取消、Escape 和适用的确认路径均完成可见双向动效。
- **SC-002**: 详情与本机镜像的最终可见/隐藏状态和 `aria-expanded` 在动画后 100% 一致。
- **SC-003**: 正常模式下 dialog 进入不超过 360ms，详情支持面板进入不超过 420ms，退出不超过 200ms，且不阻塞后台操作。
- **SC-004**: 减少动态效果模式下所有开关动作近乎即时，且功能测试无回归。
- **SC-005**: 完整 Swift、Node 测试及真实浏览器交互验收全部通过，console 无新增 warning/error。

## Assumptions

- “所有按钮展示的窗体”包括三个原生 dialog，并扩展到同样由按钮显示的详情、折叠内容和 toast。
- 本次只增加前端表现层动效，不改变容器、镜像或后端操作。
- 管理控制台以清晰和响应速度优先，采用克制的 expressive motion，不加入循环动画、弹跳或大幅形变。

## Validation Evidence

- 2026-08-30：测试先行的 `Material3MotionAssetTests` 在实现前执行 3 个测试并产生 21 个预期失败；初版通过后又为 Escape 兜底增加 1 个预期失败，完成实现后 3/3 通过。
- 2026-08-30：完整 Swift 测试执行 172 个测试，0 失败；2 个需显式开启的外部只读检查按设计跳过。Node 前端测试 6/6 通过，JavaScript 语法检查和 `git diff --check` 通过。
- 2026-08-30：仅重启 Container GUI 后，`GET /api/v1` 回读 GUI `2.12.0`，Apple container CLI 与 apiserver 仍为健康的 `1.3.1`；容器 API 仍回读原有 3 个运行中容器，未执行生命周期或资源写操作。
- 2026-08-30：真实浏览器回读 dialog 进入动画 `md-dialog-enter`、时长 320ms，backdrop 为 `md-scrim-enter`；创建、拉取和正常停止确认窗体均只打开并取消，最终全部 `open=false`。
- 2026-08-30：真实浏览器回读详情 `md-pane-enter` 为 280ms；关闭后详情隐藏并显示带进入动画的占位内容。本机镜像过渡为 `grid-template-rows / opacity / transform`，收起后 `aria-expanded=false` 且隐藏，展开后恢复可见与 `aria-expanded=true`。
- 2026-08-30：创建窗体连续打开/取消 3 次后无 `is-closing` 或 backdrop 残留，焦点恢复到 `openCreateContainerButton`；页面宽 1280px 时 `scrollWidth=1265`，无整体横向溢出。自动化键盘接口未生成可观察的原生 Escape 事件，因此 Escape 由显式 keydown 兜底和静态契约覆盖，取消按钮的真实退出路径已验证。
- 2026-08-30：针对“查看详情动画仍太生硬”的反馈，先增加详情支持面板、分段内容与自动刷新不重播契约，定向测试产生 8 个预期失败；实现后版本递增至 `2.12.1`，定向 5/5、完整 Swift 173 个测试（2 跳过、0 失败）、Node 6/6、JavaScript 语法与 diff 检查通过。
- 2026-08-30：真实浏览器点击回读支持面板动画为 `md-detail-surface-enter / 420ms`，详情内容为 `md-detail-content-enter / 340ms`，首区块为 `md-detail-section-enter / 260ms / 65ms delay`；420ms 后 class 清理，等待超过一次五秒自动刷新后未重播。连续切换 `odoo19`、`Ubuntu26.04` 最终标题与状态正确，关闭后正文隐藏、占位内容恢复。
