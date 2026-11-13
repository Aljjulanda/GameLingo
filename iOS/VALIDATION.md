# Validation status — 2026-11-13

This record describes this Windows session only. Historical evidence restored with the original project is not a new hardware run.

| Check | Actual result |
| --- | --- |
| Restored source | Verified bundle SHA-256 and recovered original Git history at `e04a16a`; work branch `codex/ios` |
| TV APK identity | Desktop APK and delivered APK have identical SHA-256 `d533e1cf9e994e90bd390de54033e18effb8a23948d16df31dac2a8a5651c06f` |
| Windows regressions | **51 passed**, using the existing Windows Python environment and this checkout's `desktop` on PYTHONPATH |
| Windows/Android source preservation | No diff from restored baseline in `desktop/` or `android-tv/`; portable hash manifest checks 51 source/configuration files |
| Original offline model | SHA-256 and exact archive size verified; extracted only the five expected files |
| Actual translation on Windows | CTranslate2 4.9.0 / int8 translated three generated English sentences to Arabic; no cloud. This does not test the new iOS C++ bridge |
| Native dependency source preparation | Actual pinned Git/submodule fetch completed on Windows; guarded iOS patches applied successfully; no native Apple compilation performed |
| Swift syntax | 20 application/test/package files parsed with tree-sitter-swift 0.7.4; no parser errors. Parsing is **not** Swift type checking, SDK availability checking or linking |
| Xcode project structure | Generated and read by an OpenStep parser; 78 objects; deterministic regeneration passed. `xcodebuild` has not opened/built it here |
| Portable source checks | Python syntax, property lists, scheme XML, exact desktop display defaults/bounds, preserved-platform hashes, deterministic project generation passed |
| IPA validation-tool tests | **3 passed**: synthetic structure accepted; traversal/provisioning rejected; simulator/signed executable rejected. Fixtures are temporary structural tests, not built IPAs |
| Shell/source whitespace | Bash syntax checks and Git diff checks passed |
| XCTest code supplied | 16 portable Swift core tests and 7 Apple integration tests, including generated H.264→CVPixelBuffer, Vision OCR, offline inference, WSS pairing/reconnect and Keychain/TLS identity. **Not executed here** |
| GitHub Actions | Not run: restored repository has no remote and no GameLingo GitHub repository was identified in the connected account |
| Unsigned archive / IPA | Not produced; no Xcode/macOS build execution available here |
| Xcode 14.2 / Monterey | Not verified; actual installed Xcode inaccessible |
| Physical iPhone / PS5 / TCL acceptance | Not run; use `DEVICE_TEST_CHECKLIST.md` |

Generated model smoke results on Windows:

| English fixture | Actual model output |
| --- | --- |
| Where are you going? | إلى أين أنت ذاهب؟ |
| Follow me to the gate. | اتبعني إلى البوابة |
| We should not enter the building. | لا يجب أن ندخل المبنى |

The observed Windows inference times (roughly 60–228 ms in this single smoke check) are not iPhone predictions or sustained-session benchmarks. Selection of the existing model preserves the model/tokenization/greedy-decoding approach; a fair mobile comparison against ML Kit/Core ML/Marian and battery/thermal measurements remains outstanding.

The source implements the requested path, but a functional iPhone release is **not certified** until the macOS build, simulator suite and physical acceptance pass. Source changes may still be required by the first Apple compilation. Existing Windows/TV binaries were neither reinstalled nor replaced during this session.
