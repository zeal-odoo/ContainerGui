# Implementation Plan: Material 3 渐进响应动效

## Summary

在现有静态 HTML/CSS/JavaScript 中增加一套轻量 Material Motion 令牌和状态类。dialog 使用统一的 `openDialog` / `closeDialog` 流程保证双向动画和原生返回值；详情、镜像折叠及 toast 使用局部状态类。后端、API 和容器行为保持不变。

## Technical Context

- **Language**: Swift 6.3.3 后端；原生 HTML/CSS/JavaScript 前端
- **Dependencies**: 现有 Hummingbird 2；无新增前端依赖
- **Testing**: XCTest 静态资源契约、现有 Node 测试、真实浏览器只读交互验收
- **Target**: macOS 本机 `127.0.0.1:8787`
- **Constraints**: loopback、安全确认不变、无真实资源变更、支持减少动态效果

## Constitution Check

- 测试先行：先添加缺失动效令牌和状态的失败测试。
- 最小改动：只修改 `app.css`、`app.js`、必要 HTML 包装、版本和规格。
- 安全边界：浏览器验收只打开/取消窗体、查看详情和折叠，不提交容器操作。
- 自包含：使用 CSS keyframes/transition 和少量原生 JavaScript，不添加库。

## Project Structure

```text
Sources/ContainerGUI/App/AppVersion.swift
Sources/ContainerGUI/Resources/Public/app.css
Sources/ContainerGUI/Resources/Public/app.js
Sources/ContainerGUI/Resources/Public/index.html
Tests/ContainerGUITests/Browser/Material3MotionAssetTests.swift
Tests/ContainerGUITests/Unit/AppVersionTests.swift
specs/010-material-3-motion/
```

## Design

1. 定义 dialog enter/exit、pane enter/exit 和 emphasized easing 令牌。
2. `openDialog` 取消遗留退出计时器，打开后安排焦点；`closeDialog` 在正常模式播放退出后调用原生 `close(returnValue)`，减少动态效果时立即关闭。
3. 拦截 dialog `cancel` 和确认表单 `submit`，让所有关闭入口统一。
4. 详情内容用进入/退出 class；镜像区域用 grid row + inner wrapper 连续折叠；toast 使用显示/隐藏 class。
5. 版本递增为 2.12.0，回归并重启 GUI 服务验收。
6. 后续精调将详情支持面板改为 420ms 定向进入与轻微回稳，正文区块错峰显现；只在首次打开或切换容器时播放，并将版本递增为 2.12.1。
