# Local log model sources and notices

ContainerGUI's optional log analyser downloads the fixed model
`anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5` at revision
`0977a61d00e39118aab5ed1e510f1d228df5eefd` separately. Model weights are not
included in the application source or installer.

- Original model: [Qwen3-1.7B, Qwen Team](https://huggingface.co/Qwen/Qwen3-1.7B),
  licensed under [Apache License 2.0](https://huggingface.co/Qwen/Qwen3-1.7B/blob/main/LICENSE).
- CoreML conversion: [ANEMLL](https://huggingface.co/anemll/anemll-Qwen-Qwen3-1.7B-ctx2048_0.3.5/blob/0977a61d00e39118aab5ed1e510f1d228df5eefd/README.md).
  Its model card declares MIT for ANEMLL and identifies the original model's
  separate licence requirements.
- The native runtime is independently implemented against the pinned model's
  `metadata.json` interfaces. Shared-state and full-batch prefill sequencing were
  checked against [ANEMLL's Swift inference reference](https://github.com/Anemll/Anemll/blob/fb42f60b2e7a7b4709052c7146d37480bf21941e/anemll-swift-cli/Sources/AnemllCore/InferenceManager.swift).
  ANEMLL declares MIT in its repository README; no ANEMLL runtime source is
  bundled as a dependency.
- The Foundation-only tokenizer reads the downloaded vocabulary and BPE merges.
  Its NFC normalization, byte mapping, split expression and non-thinking ChatML
  framing implement the pinned `tokenizer.json` and `tokenizer_config.json` data.

All CoreML model configurations use `cpuAndNeuralEngine`. This excludes GPU
execution, but does not certify that every operation runs on the Neural Engine.
The process has no network API, command-execution tools or persistent log history.
