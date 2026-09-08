# Research

## Model decision

- Fixed `anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5`, revision `0977a61d00e39118aab5ed1e510f1d228df5eefd`.
- https://huggingface.co/anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5
- Four compiled models: embeddings, two FFN chunks (infer/prefill), LM head. FFN/head LUT6, embeddings FP16; approximately1.95GB plus runtime state. Original Qwen Apache2.0; converted card MIT. Retain notices; never execute downloaded Python.
- Native interface: context2048, prefill64, shared fp16 KV [56,8,2048,128]224MiB. Independent Foundation BPE; fixed non-thinking framing. Upstream metadata and ANEMLL Swift inference are references, not copied runtime dependency.
- https://github.com/Anemll/Anemll ; https://huggingface.co/Qwen/Qwen3-1.7B

## Lifecycle decision

- Same binary private worker, bounded JSON-lines over pipes; `.cpuAndNeuralEngine` excludes GPU but does not certify ANE use.
- Parent cancels, invalidates generation, terminates, waits, escalates then verifies exit. Worker checks parent existence. OS reclaimable caches not promised to instantly disappear.
- Reject main-process model retention (release hard to verify), cloud (privacy), implicit MLX/GGUF fallback (different compute route).

## Resource and safety decision

- One model/generation globally; bounded redacted/deduplicated snapshots; browser heartbeat lease expires60s.
- Fixed immutable HTTPS artifact list, lengths/hashes, symlink rejection, staged readiness. No remote-provided paths/commands/prompts accepted.
- No persistent logs/history or tool execution; pure text output. Available memory gate is a safety heuristic, not all-Mac certification.
