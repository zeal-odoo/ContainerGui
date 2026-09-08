# GET /api/v1/system/ane

No body or options. Existing exact Host/Origin policy and no-store headers apply. Does not depend on container CLI, AI state or selected container. Always 200 for a known metric state; unauthorized requests remain rejected by safety middleware.

```json
{"state":"ready","watts":2.5,"observedAt":"2026-09-08T00:00:00Z","sampleSeconds":5,"reason":null,"scope":"host","estimated":true,"utilizationPercent":null,"utilizationState":"unavailable"}
```

Sampling/unavailable: watts and sampleSeconds are explicitly null; unavailable has reason unsupported/read_failed/invalid_sample. UI translates only these finite known reasons and treats HTTP/invalid response as unavailable, clears old value. Rendering is plain text, no HTML interpolation. The page shows `整机 ANE` / `Host ANE`, `估算功耗` / `Estimated power`, and an unavailable utilization label. Never draw a utilization meter from watts.
