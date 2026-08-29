# Implementation Plan: Material Design 3 界面视觉升级

**Branch**: `main` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-material-3-ui/spec.md`

## Summary

以 Material Design 3 的语义色彩、类型比例、形状、表面层级和交互状态重构 Container GUI 全部静态界面。实现保持原生 HTML/CSS/JavaScript、现有 DOM 标识和 API 契约不变，主要通过集中设计令牌和组件样式升级顶部栏、统计卡、列表/详情支持面板、表格、状态标签、表单、进度、日志与弹窗；同时完善浅色/深色、自适应和减少动态效果规则。

## Technical Context

**Language/Version**: Swift 6.3.3（Package 使用 Swift tools 6.1）；原生 HTML、CSS、JavaScript

**Primary Dependencies**: Hummingbird 2.26；现有静态资源服务；Apple Container CLI 1.3.1（本次不改 CLI 集成）

**Storage**: 无新增持久化；主题继续跟随系统偏好

**Testing**: XCTest 静态资源断言、现有 Node 前端行为测试、完整 Swift 回归、真实浏览器桌面/紧凑与浅色/深色验收

**Target Platform**: Apple Silicon，macOS 15+ 的 Safari/Chrome/内嵌 Chromium；当前环境 macOS 26

**Project Type**: 单 Swift B/S 服务与无构建步骤静态浏览器界面

**Performance Goals**: 首屏不增加网络依赖或构建产物；视觉动画仅使用合成友好的短时属性；现有五秒自动刷新不受影响

**Constraints**: 仅精准修改静态界面、版本与测试；保留所有 DOM ID、中文文案、API、安全确认和折叠箭头语义；不引入 Material Web、远程字体、远程图标或 CDN

**Scale/Scope**: 单用户本机控制台，首页及三个现有弹窗；覆盖扩展、中等、紧凑窗口与系统浅/深主题，不增加手动主题开关或新业务功能

## Constitution Check

*GATE: Phase 0 前检查，并在 Phase 1 设计完成后复查。*

| 原则 | 设计证据 | 结果 |
|---|---|---|
| 官方 CLI 是唯一事实来源 | 仅改视觉静态资源，不新增或缓存容器状态 | PASS |
| 本机优先与安全变更 | 不改变监听、命令或 API；危险按钮和二次确认继续使用原流程 | PASS |
| 测试先行和可替换命令适配器 | 先增加 Material 3 静态资源失败测试，再改 CSS/HTML；完整服务回归验证行为未变 | PASS |
| 可独立验收的增量交付 | 三个用户故事分别覆盖主界面、交互状态和自适应主题，可独立浏览验收 | PASS |
| 简洁、可观察、可兼容 | 使用现有 CSS/HTML，不新增框架、构建链、服务或数据库 | PASS |
| 版本与 Git 门禁 | 向后兼容的完整视觉功能递增 MINOR 至 2.11.0，验证后单一 Git 提交并推送 | PASS |

Phase 1 复查：设计仅增加静态设计令牌和组件视觉契约；没有 API、数据存储或运行时依赖变化。浅/深主题、键盘焦点、自适应和无外部资源均有自动化与浏览器验收。全部门禁继续通过，无宪章例外。

## Project Structure

### Documentation (this feature)

```text
specs/009-material-3-ui/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── ui-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/ContainerGUI/
├── App/AppVersion.swift
└── Resources/Public/
    ├── index.html
    ├── app.css
    ├── app.js
    └── icons/

Tests/ContainerGUITests/
├── Browser/
│   └── Material3AssetTests.swift
└── Unit/
    └── AppVersionTests.swift

Tests/Frontend/
└── *.mjs
```

**Structure Decision**: 保留现有单 Swift Package 与静态前端；将视觉系统集中在 `app.css`，仅在 `index.html` 增加必要的页面元数据或无行为语义标记，避免触碰 1,600 多行的既有行为脚本。

## Complexity Tracking

无宪章违规，不需要复杂度例外。
