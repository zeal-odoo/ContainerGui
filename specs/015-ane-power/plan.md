# Implementation Plan: 整机 ANE 估算功耗

**Branch**: `codex/local-ai-logs` | **Date**: 2026-09-08 | **Spec**: [spec.md](spec.md)

## Summary

在容器页独立显示整机 ANE 估算功耗。Swift 只读动态加载系统 IOReport，订阅 Energy Model 的严格匹配 ANE 能量通道，以两次有效读数的能量差除以单调时长。使用率固定 unavailable/null；不采集 CE、电源驻留或归因进程。无新依赖、无 root、无模型启动。

## Technical Context

- Swift 6、Hummingbird 2、Foundation/CoreFoundation/Darwin；静态 JS/HTML/CSS。
- Apple Silicon/macOS 26 基线，其他环境失败关闭此指标。
- 内存仅保留最近两次能量读数与短期快照；无数据库或后台定时进程。
- XCTest + HummingbirdTesting + Node tests + 真实只读接口 + Playwright。
- 页面可见时每 5 秒请求；服务串行化并在 1 秒内复用快照。首次或间隔超过 15 秒显示 sampling；未知单位、负值、重置、异常间隔清除旧数据。

## Constitution Check

通过：CLI 容器状态路径保持不变；只读整机硬件遥测是本次用户确认的新增来源，不冒充 container CLI 状态。唯一来源原则中“系统状态”的此项例外仅限 ANE 能量计数器：CLI 不提供它，powermetrics 要求 root，故独立使用系统只读 IOReport。影响为私有 API 兼容风险；不支持时返回 unavailable，未来稳定公开 API 可替换，不能扩展为 container 私有 XPC 操作。保留 loopback、安全中间件、先测试、固定路径和本地版本提交。设计后复核同样通过。

## Project Structure

- `Sources/ContainerGUI/Domain/ANEPower.swift`: DTO、可替换读取协议、串行采样服务。
- `Sources/ContainerGUI/Infrastructure/IOReportANEEnergyReader.swift`: 动态符号、有限通道、CF 所有权。
- `Sources/ContainerGUI/Web/ANEPowerRoutes.swift` + `App/AppFactory.swift`: 独立被动 GET。
- `Sources/ContainerGUI/Resources/Public/{app.js,app.css,index.html,i18n.js}`: 独立指标、语言和失败清理。
- `Tests/ContainerGUITests/{Unit/ANEPowerTests.swift,Contract/ANEPowerAPITests.swift}`、`Tests/Frontend/ANEPowerTests.mjs`。
- 本目录含 research、data-model、contracts/api、quickstart、tasks 和 validation。

## Complexity Tracking

仅新增一个本机只读 sampler，无通用硬件监控框架、常驻 helper、命令执行或功率归一化模型。
