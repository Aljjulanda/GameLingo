# iOS source and dependency notices

The iOS application is licensed under GNU AGPL v3 with the additional OpenSSL permission in `LICENSE`. This applies to the new iOS application, not a blanket relicensing of the existing Windows/Android sources. Preserve original notices and supply corresponding source, dependency revisions, and build/patch scripts when conveying the combined application. No warranty is provided. PlayStation is a trademark of its owner; this application is not endorsed by Sony.

## Inspected Remote Play candidates (2026-11-13)

| Candidate | Inspected revision | Findings | Decision |
| --- | --- | --- | --- |
| chiaki-ng | `43728af2e639fecb8a7af1cd68c29820a40de973` | C core has discovery, registration and sessions; root CMake applies macOS-specific Apple deployment settings; no native iOS target in the inspected tree | Foundational upstream, not a drop-in SwiftUI app |
| Pylux | `ca87a49a12bab071948f565ca53ffdad790775d3` | Actual iOS bridge/VideoToolbox files and iOS CMake path; README explicitly calls for iOS hardening; forced mbedTLS 2.28.0 and macOS deployment setting need replacement | Use pinned C protocol core only, with a narrow bridge compiled inside its target; no cloud login/paywall/UI code copied |
| TP Play | `482611539977496cad047560c9bc1ebc5809a566` | README describes an unconnected shell, but inspected tree actually contains native registration/session C bridge and Swift H.264/HEVC decoder; build script is device-only and pins old mbedTLS | Reuse decoder source, not its whole app/build system; do not infer verified functionality from either README or source presence |

All three Chiaki-derived candidates carry `LicenseRef-AGPL-3.0-only-OpenSSL`. The complete license and additional permission are retained in `iOS/LICENSE` and bundled notices.

Source of `GameLingo/VideoProcessing/VideoDecoder.swift`:
[TP Play decoder at pinned commit](https://github.com/mB14ck22/tp-play/blob/482611539977496cad047560c9bc1ebc5809a566/ios/TPPlay/Platform/Streaming/VideoDecoder.swift).
Changes: eight-item compressed queue, synchronous VideoToolbox submission on the private decode worker to bound decoder work, explicit shutdown/draining, exposed Annex-B parser for tests, fewer diagnostic prints, a compiler/availability guard around the iOS 17 hardware-selection key, and direct OCR callback without Metal rendering. Original Chiaki/chiaki-ng/TP Play attribution and license are retained. Native `GLRemotePlay.c` adapts the documented Chiaki API, with key-safe logging disabled and explicit buffer lengths. [Apple documents the explicit decoder-selection key as iOS 17+](https://developer.apple.com/documentation/videotoolbox/kvtvideodecoderspecification_enablehardwareacceleratedvideodecoder); older SDKs use the native iOS default selection.

## Other dependencies

| Component | Pin | License/use |
| --- | --- | --- |
| CTranslate2 | v4.6.0 / `617405f4b050e994e829d527da6caa0e0030afe7` | MIT; C++ inference, CPU, Ruy int8 on arm64 and Accelerate float32 on x86 simulator |
| SentencePiece | v0.2.1 / `31646a467d2051eb904e0b45de3a73e91fe1c1e3` | Apache-2.0; original model tokenizer |
| OpenSSL | 3.5.9 LTS / `45e844fa2a14ec92d146bd8f5778ac130b6625fb` | Apache-2.0; protocol crypto and in-memory PKCS#12 identity generation; network TLS is Apple Network.framework |
| ZIPFoundation | 0.9.19 | MIT; authenticated-model package extraction |
| Pylux transitive libraries | Pinned submodule commits; json-c 0.17 at `b4c371fa0cbc4dcbaccc359ce9e957a22988fb34`, miniupnpc 2.2.8 at `b55145ec095652289a59c33603f3abafee898273` | Preserve all upstream notices. `collect-notices.py` collects fetched dependency notices into the app after native preparation; source manifest accompanies CI logs |

`bootstrap.py` applies exact guarded patches: use maintained OpenSSL instead of upstream's forced old mbedTLS; prevent macOS deployment settings from overriding the iOS target; add the narrow C bridge to the native core's own compilation; prevent CTranslate2's macOS deployment default from applying to iOS; honor the disabled Opus option; guard SentencePiece's optional Xcode-only CMake helper when using Ninja; exclude host macOS pkg-config IDN targets from iOS. Build options disable cpuinfo tools/tests and optional external IDN/HTTP2 libraries, use explicit iOS OpenSSL paths, refresh CMake host tool paths, and verify cached library architectures. All modifications are in the supplied source/build scripts. No proprietary ML Kit SDK is linked to this AGPL-derived application.

The runtime language package is the desktop's exact `argos-en_ar-1.0` archive: 88,502,631 bytes, SHA-256 `e2a6e84337f7ebbb55f9dc61dcba3a861c0d786ae5a46fa198fd8d6473f5c775`. The supplied archive metadata has no explicit model license field; its README names OpenSubtitles/UNPC corpora and Stanza. Do not substitute the Argos runtime's MIT license for the model's terms. Model redistribution rights remain unresolved; weights are not committed or bundled in the release app. The user can download from the original HTTPS source or import their existing exact package. CI downloads it solely as a test fixture, not an IPA resource.

Primary references: [Chiaki-ng](https://github.com/chiaki-ng/chiaki-ng), [Pylux](https://github.com/ForWard-Technologies-LLC/Pylux), [TP Play](https://github.com/mB14ck22/tp-play), [CTranslate2 build options](https://opennmt.net/CTranslate2/installation.html), [CTranslate2 quantization](https://opennmt.net/CTranslate2/quantization.html), [OpenSSL releases](https://www.openssl-library.org/source/), [Argos model-license discussion](https://github.com/argosopentech/argos-translate/issues/533).
