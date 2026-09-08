# Data model

- `AILogHistoryRecord`: schemaVersion=1, id(UUID), containerId(现有标识格式), createdAt, model/name and revision, language(zh/en), appVersion, result(AILogResult: 脱敏 text/evidence、observedAt、token数和耗时)。验证有限长度、有限数字、固定schema；文件名含createdAt秒和id，同秒UUID稳定排序。
- `AILogHistoryPage`: items、page、pageSize=10、total、retentionLimit=1000。过滤可选：无容器标识读取全部历史；UI 默认当前容器。
- `AILogStatus`: 添加可选historyError和historyRecordId；关闭仍清空临时result，但不删除文件。
- 状态：推理完成→校验generation→脱敏记录原子保存→可回读；失败→当前result可读并显示未保存；删除需确认后移除精确记录；保留上限仅淘汰最旧记录。
