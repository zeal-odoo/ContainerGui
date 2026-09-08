# HTTP contract

所有接口沿用 Host/Origin/no-store；不下载/加载模型，不向CLI发起请求。

- `GET /api/v1/ai/logs/history?containerId=<id>&page=1`：参数可选，page在1...100，返回AILogHistoryPage，每页10条，越界到最后一页。没有记录返回空页，损坏/不安全文件返回503安全错误，不伪装为空。
- `POST /api/v1/ai/logs/history/delete`：严格JSON `{ "id": "<UUID>", "confirmationId": "<相同UUID>" }`。缺失确认/额外参数422；目标不存在404；成功200 `{ "deletedId": "<UUID>" }`，前端重新读取列表。页面取消确认时不发请求。
- `GET /api/v1/ai/logs/status`：增加可选historyError(`history_save_failed`)和historyRecordId。保存失败不把AI状态改成关闭，不暴露文件路径/原始异常。
- 导出在浏览器把已取得的一条记录转为JSON下载，不另起模型请求或执行其中建议。
