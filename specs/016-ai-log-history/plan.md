# Implementation Plan: 本机 AI 分析历史

**Branch**: `codex/local-ai-logs` | **Date**: 2026-09-08 | **Spec**: [spec.md](spec.md)

## Summary

成功分析时保存脱敏的有限结果和证据快照。独立的历史存储和只读列表不依赖模型或 CLI 状态。详情面板提供折叠的历史列表、每页 10 条、单条 JSON 导出和确认删除。

## Technical Context

**Language/Version**: Swift 6、原生 JavaScript。
**Primary Dependencies**: 现有 Hummingbird 2、Foundation/Darwin，无新增依赖。
**Storage**: 当前用户 Application Support/ContainerGUI/AILogHistory 下每记录一个 JSON 文件；0700 目录、0600 文件，1000 条上限，原子提交。
**Testing**: XCTest、HummingbirdTesting、Node test、Playwright CLI。
**Target Platform**: Apple Silicon macOS 26、现有 container 1.3.1。
**Project Type**: 单进程本机 HTTP 服务和静态 UI。
**Performance Goals**: 保存只写一条有限记录；历史按需读取，不做后台扫描或模型加载。
**Constraints**: 结果/日志各 6144 UTF-8 字节；每文件最多 96 KiB（JSON 转义开销），目录扫描有上限；历史不是影子容器状态。
**Scale/Scope**: 全局最近1000条；同名容器按标识归组；v2.23.0 本地提交，不发布。

## Constitution Check

- CLI 仍为容器当前状态唯一事实来源；历史明确为带时间戳的分析证据，不用于运行状态判断。
- 保持 loopback、Host/Origin、no-store、严格参数校验；接口不接收路径、提示词或日志正文。
- 先失败测试，再最小实现；真实容器不变更，浏览器用合成记录验证。
- 不引入数据库或前端构建链；每条私有 JSON 仅由本功能维护。
- 计划前/设计后均通过；无宪章例外。

## Project Structure

- `Sources/ContainerGUI/AI/AILogHistoryStore.swift`：记录、页面、私有安全文件读写和上限。
- `Sources/ContainerGUI/AI/AILogService.swift`：成功分析接入保存，保存失败不丢失当前结果。
- `Sources/ContainerGUI/Web/AILogRoutes.swift`：被动列表及确认删除。
- `Sources/ContainerGUI/Resources/Public/ai-log-history.js`：独立历史控制器；现有 HTML/CSS/i18n 和 AI 控制器少量接入。
- `Tests/ContainerGUITests/Unit/AILogHistoryTests.swift`、服务测试、HTTP 契约测试、`Tests/Frontend/AILogHistoryTests.mjs`。

## Complexity Tracking

不创建通用存储框架。目录句柄相对的 openat/fstat/unlinkat 操作只在历史 store 内，避免符号链接路径竞态。

## v2.23.1 responsiveness follow-up

大量日志回归使用合成数据，不修改真实容器。测量日志预处理与控制状态响应，避免对最终会丢弃的旧行重复运行脱敏表达式；准备工作不得占用 AI 控制 actor。页面日志采用有限内存窗口和合并重绘，单次最近日志也受显示上限约束。验收为大批量处理低于1秒、处理期间状态响应低于300毫秒、模拟关闭低于1秒，以及日志洪峰中仍可切换界面和操作 AI 开关。低级密钥边界检测、结果保存、单模型和关闭释放保持不变。无新增依赖，不发布。
