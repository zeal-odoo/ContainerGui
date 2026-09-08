# Validation guide

1. 在临时私有目录中运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter AILog`；覆盖持久化、关闭/取消、分页、脱敏、权限、符号链接、大小和删除确认。
2. `node --test Tests/Frontend/*.mjs`；覆盖迟到响应、容器切换、语言、空/错误状态和本地JSON导出，不启用真实模型。
3. 完整 Swift 测试及 release 构建；`git diff --check`。
4. 独立测试 GUI 使用合成分析记录，Playwright 验证中文桌面、英文390px、翻页、展开、导出、删除取消/确认；读取关闭AI状态，避免读取真实容器日志。
5. 仅重启本机 GUI 并回读 v2.23.0 和可见历史入口，既有容器保持运行；本地聚焦提交，不推送或发布。
