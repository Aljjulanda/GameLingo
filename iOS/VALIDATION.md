# Validation status — 2026-11-13

This record describes local Windows checks and actual GitHub-hosted macOS runs. Historical evidence restored with the original project is not a new hardware run. The owner's private repository is [Aljjulanda/GameLingo](https://github.com/Aljjulanda/GameLingo).

| Check | Actual result |
| --- | --- |
| Restored source | Verified bundle SHA-256 and recovered original Git history at `e04a16a`; work branch `codex/ios` |
| TV APK identity | Desktop APK and delivered APK have identical SHA-256 `d533e1cf9e994e90bd390de54033e18effb8a23948d16df31dac2a8a5651c06f` |
| Windows regressions | **51 passed**, using the existing Windows Python environment and this checkout's `desktop` on PYTHONPATH |
| Windows/Android source preservation | No diff from restored baseline in `desktop/` or `android-tv/`; portable hash manifest checks 51 source/configuration files |
| Original offline model | SHA-256 and exact archive size verified; extracted only the five expected files |
| Actual translation on Windows | CTranslate2 4.9.0 / int8 translated three generated English sentences to Arabic; no cloud. This does not test the new iOS C++ bridge |
| Native dependency source preparation | Actual pinned Git/submodule fetch completed; guarded iOS patches applied successfully |
| Native Apple compilation | Chiaki including the Remote Play C bridge, CTranslate2, SentencePiece and OpenSSL compiled for iphoneos arm64 and iphonesimulator arm64 with Xcode 16.4 / build 16F6. Earlier Intel runs also compiled x86_64 simulator libraries |
| Swift validation | Initial parser checks covered 20 application/test/package files. Final application and Apple tests were actually type-checked and linked by Xcode; core tests compiled with Swift Package Manager |
| Xcode project structure | Generated and read by an OpenStep parser; 78 objects; deterministic regeneration passed; accepted by actual Xcode 16.4 dependency resolution and build invocation |
| Portable source checks | Python syntax, property lists, scheme XML, exact desktop display defaults/bounds, preserved-platform hashes, deterministic project generation passed |
| IPA validation-tool tests | **4 passed**: synthetic structure accepted; traversal/provisioning rejected; simulator/signed executable rejected; arm64 simulator platform and bundled test model rejected. Fixtures are temporary structural tests, not built IPAs |
| Shell/source whitespace | Bash syntax checks and Git diff checks passed |
| Portable Swift core XCTest | **16 passed** on the macOS runner, including configuration/persistence, pairing validation, bounded cache, display schema, dialogue identity/corrections and TV protocol ordering |
| Apple integration XCTest | **7 passed, 0 failures** on iOS 18.5 / iPhone 16 arm64 simulator: generated H.264→CVPixelBuffer, Vision English dialogue with full-frame ROI coordinates, actual C++ offline Arabic inference, localhost WSS pairing/reconnect/no replay, Keychain/TLS identity, Annex-B parsing and native invalid-buffer rejection |
| GitHub Actions | **Complete workflow succeeded** on Apple Silicon macos-15 with Xcode 16.4: [run 43423525500](https://github.com/Aljjulanda/GameLingo/actions/runs/43423525500). Earlier Intel/native/CMake and runtime diagnostics are preserved in repository/Actions history |
| Unsigned archive / IPA | **Produced** at code commit `c6be805d35a0ffd5dca0cbee4cc6d90c1b23f20f`; [artifact 14035187638](https://github.com/Aljjulanda/GameLingo/actions/runs/43423525500/artifacts/14035187638), 2,533,537 bytes. Downloaded actual IPA passed the independent Windows validator: physical iPhone arm64 executable, expected resources, no embedded signing material/model weights |
| Xcode 14.2 / Monterey | Not verified; actual installed Xcode inaccessible |
| Physical iPhone / PS5 / TCL acceptance | Not run; use `DEVICE_TEST_CHECKLIST.md` |

Generated model smoke results on Windows:

| English fixture | Actual model output |
| --- | --- |
| Where are you going? | إلى أين أنت ذاهب؟ |
| Follow me to the gate. | اتبعني إلى البوابة |
| We should not enter the building. | لا يجب أن ندخل المبنى |

The observed Windows inference times (roughly 60–228 ms in this single smoke check) are not iPhone predictions or sustained-session benchmarks. Selection of the existing model preserves the model/tokenization/greedy-decoding approach; a fair mobile comparison against ML Kit/Core ML/Marian and battery/thermal measurements remains outstanding.

The delivered IPA SHA-256 is `4a25e7feaade5f3c0457b32c7740216a6fcc381ca1fb02a654fa951f9ac86933`.

The Apple tests use generated pixels/video and a localhost TV client speaking the existing protocol; they do not connect to a PS5 or the physical Android TV receiver. The native translation test reads the verified fixture directly without a download/network call. Passing simulator timings are not mobile device benchmarks. The runtime tests caught and corrected a duplicate listener-port bind and ROI-relative Vision boxes being interpreted as full-frame coordinates; the generated pixel fixture's UIKit orientation was corrected separately. The delivery documentation commit changes no compiled source after the successful run.

The source implements the requested path and the physical-iPhone target builds successfully, but the complete gameplay workflow is **not verified** until physical acceptance passes. Existing Windows/TV binaries were neither reinstalled nor replaced during this session.
