# Data model

- Model status: name, installed, downloading, downloadedBytes, totalBytes.
- Session status: enabled; phase off/downloading/loading/ready/analysing/stopping/error; containerId; language; workerPID; error; result.
- Result: text, redacted evidence, observedAt, inputTokens, outputTokens, elapsedSeconds.
- Generation increments on enable/disable; stale tasks cannot start a worker or publish results. No persisted enabled flag.
- Only explicit heartbeat renews lease; passive status does not. Disable global; files retained, logs/results transient.
