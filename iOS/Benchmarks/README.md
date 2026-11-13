# Offline contextual-model pilot

This is a **synthetic Windows x64 CPU pilot**, not an iPhone performance or translation-quality certification. It uses four authored cases (river-bank ambiguity, negation, number, idiom) and context capacities 1/5/10/20. No user gameplay text, credentials or history is collected. A larger reviewed corpus of actual game dialogue is still needed; the user tests multiple games and has not supplied such a corpus.

## Reproduction

Use a separate Python 3.11+ environment; do not alter the working desktop application's environment. Install `ctranslate2==4.9.0`, `sentencepiece==0.2.3`, `psutil==7.2.2`. From the repository root:

```powershell
python iOS/Scripts/fetch-test-model.py
python iOS/Benchmarks/prepare.py
python iOS/Benchmarks/benchmark-context.py
```

The optional GGUF is approximately 469 MiB. `assets.json` pins the official Qwen revision and llama.cpp release by SHA-256. Executables, model weights and outputs stay under ignored `iOS/.build/context-benchmark`. The server binds only loopback and is terminated in `finally`. These assets are never packaged into the IPA. `windows-cpu-results.json` preserves the measured pilot, including all outputs; reruns write a separate ignored `results.json`.

## Measured decision

Argos/CTranslate2: median approximately **47 ms**, maximum sampled process RSS approximately **141 MiB**, load 0.43 s. Qwen2.5-0.5B-Instruct Q4_K_M CPU: median approximately **761 ms**, maximum sampled server RSS approximately **500 MiB**, load 1.56 s. Each uses two inference threads. RSS includes runtime overhead, and process arrangements differ. Four cases without statistical repetitions are insufficient for general performance ranking. No battery, energy or iPhone thermal measurements were made.

The small Qwen model lost negation, replaced coins with feathers and produced unrelated repeated text in some cases. Larger context did not consistently improve results. It is **rejected for this preview**. Argos also remains literal for the idiom and ambiguous bank; we do not claim those problems are generally solved. No LLM model, automatic late rewrite or fictitious engine selector is included in the application.

App context assistance is a different, explicit mechanism: bounded RAM history plus manually configured whole-sentence terminology rules, optionally scoped by a recent English word or confirmed speaker. The native Apple integration benchmark separately compares Argos against these authored rules using the actual bundled CTranslate2 bridge. Hand-authored correct outputs prove rule selection, not general neural translation quality.

## Platform review

- [Official Qwen model](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF): multilingual candidate including Arabic; official quantized artifacts. Apache-2.0 model license.
- [llama.cpp builds](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md): native deployment candidates exist; this pilot runs Windows CPU only. No iOS integration or Metal cost has been validated.
- [mlx-swift-lm package](https://github.com/ml-explore/mlx-swift-lm/blob/main/Package.swift): current package reviewed during development requires Swift 6.2; optional/default Foundation Models integration has newer SDK requirements. It cannot simply be dropped into the preserved Xcode 16.4 pipeline. This is a toolchain assessment, not a claim MLX is inherently macOS-only.
- Core ML requires a verified Arabic model conversion, tokenizer, memory/latency evaluation and compatible license; no such artifact was validated in this round.
- Apple Foundation Models requires checking actual device, OS, language and runtime availability. Base iPhone 15 support and Arabic translation cannot be assumed. It is not used.
