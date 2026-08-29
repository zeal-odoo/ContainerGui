# Tasks: Material 3 渐进响应动效

## Phase 1: Research and contract

- [x] T001 核对 Material 3 Motion、easing/duration、dialog 和 interaction state 官方指导
- [x] T002 明确 dialog、详情、镜像折叠、toast、按钮与减少动态效果边界
- [x] T003 创建 `specs/010-material-3-motion/` 规格、计划、研究、状态模型、UI 契约和验收说明

## Phase 2: Tests first

- [x] T004 在 `Material3MotionAssetTests.swift` 添加动效令牌、dialog 双向动画和展示内容契约
- [x] T005 运行定向测试并记录实现前 3 个测试、21 个预期失败

## Phase 3: Implementation

- [x] T006 在 `app.css` 增加空间/效果动效令牌、dialog/backdrop 双向 keyframes 和按钮按下反馈
- [x] T007 在 `app.js` 增加统一 dialog 打开/关闭流程并覆盖取消、Escape、确认及成功关闭路径
- [x] T008 在 `app.css`、`app.js`、`index.html` 增加详情、镜像折叠和 toast 渐进动效
- [x] T009 将 GUI 版本递增至 2.12.0

## Phase 4: Verification and delivery

- [x] T010 运行定向测试、完整 Swift/Node 测试和 `git diff --check`
- [x] T011 重启 Container GUI 并回读 2.12.0，不触发真实容器变更
- [x] T012 在真实浏览器验收三类 dialog、详情、折叠、快速点击和减少动态效果契约
- [x] T013 回填验证证据并将规格状态改为 Implemented
- [x] T014 创建单一 Git 提交、推送 `origin/main`，验证本地与远端一致

## Execution order

T001–T005 阻塞实现；T006–T008 按共享 CSS/JS 顺序完成；T009 后执行全量与浏览器验证；T014 最后完成。

## Phase 5: Detail motion refinement

- [x] T015 将“查看详情”生硬反馈转化为支持面板、分段内容与自动刷新不重播契约
- [x] T016 运行定向测试并记录新增测试的 8 个预期失败
- [x] T017 实现 420ms 支持面板进入、340ms 正文进入和 260ms 分段显现，并处理快速切换计时器
- [x] T018 将 GUI 版本递增至 2.12.1，运行完整 Swift/Node、语法与 diff 检查
- [x] T019 重启本机 GUI，浏览器验收点击、自动刷新、快速切换和关闭状态
- [x] T020 创建单一 Git 提交、推送 `origin/main` 并核对远端提交
