# API and worker contract

Existing loopback Host/Origin/body limits and no-store JSON apply. No arbitrary text prompts/logs, model URLs or paths accepted from browser.

- GET `/api/v1/ai/logs/status`: state, no lease renewal.
- POST `/api/v1/ai/logs/install` `{confirmed:true}`: explicit fixed install; asynchronous progress/status.
- POST `/api/v1/ai/logs/enable` `{containerId,language:"zh"|"en"}`: validate installed files/target/memory; asynchronous loading; establish lease.
- POST `/api/v1/ai/logs/disable` `{}`: globally cancel download/load/generation, verify worker exit; retain files.
- POST `/api/v1/ai/logs/analyse` `{}`: read recent200 lines of enabled target, bound/redact/deduplicate, asynchronous single inference.
- POST `/api/v1/ai/logs/heartbeat` `{}`: renew enabled lease.

Every success returns status fields `enabled`, `phase`, `containerId` nullable, `language`, `model:{name,installed,downloading,downloadedBytes,totalBytes}`, `workerPID` nullable, `error` nullable, `result` nullable (`text,evidence,observedAt,inputTokens,outputTokens,elapsedSeconds`). Standard problem responses on invalid request.

Worker CLI `ContainerGUI --ai-log-worker <validated-model-dir>` calls `AILogWorker.run(modelDirectory: URL) -> Int32`. stdin bounded32768byte JSON lines `{id,evidence,language}`. stdout JSON ready `{event:"ready"}` then `{id,text,inputTokens,outputTokens,elapsedSeconds,error?}` bounded32768bytes. Fixed prompt in worker, no-thinking, input+output <=2048 tokens, max256 output. Reset KV each request. EOF/parent disappearance ends process. Parent owns bounded termination and stale generation handling.
