# Research

- Decision: 按记录保存有限 JSON，而非单个大文件或数据库。Rationale: 保存只写本次记录，避免每10秒重写整个历史。Alternatives: localStorage 无法跨浏览器且易清空；数据库增加依赖并违反项目简洁约束。
- Decision: 使用独立 store 和列表接口，不复用 AI status。Rationale: status 会访问模型安装状态，历史必须在 AI 关闭时仍独立工作。
- Decision: 完成推理且 generation 校验通过后才提交历史；取消中的未完成推理不保存，保存错误只报告 historyError。Rationale: 不能破坏已有快速关闭和进程释放边界。
- Decision: 目录逐层 openat(O_DIRECTORY|O_NOFOLLOW)，文件 openat(O_NOFOLLOW)、fstat、euid、nlink及大小检查；临时文件0600后原子renameat。Rationale: AIModelStore 的类似工具为私有且只检查末级路径不足以保护父级；不重构相邻模块。
- Decision: 文件名为受控时间戳和 UUID；扫描有界，保存按文件名清理最旧记录，读取校验记录与文件名一致。Rationale: 不为清理全量解析日志。
- Decision: 浏览器仅 textContent 显示，导出 JSON Blob；删除要求二次确认及严格目标 ID。Rationale: 模型/日志都是不可信文本，不自动执行建议。
- Evidence: 现有 AILogService 的 generation/disable、AILogEvidence.prepare、SafetyMiddleware、AIModelStore 私有文件检查；只读研究 agent 独立核对后建议如上。无新第三方技术依赖或模型变更。
