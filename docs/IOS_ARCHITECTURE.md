# iOS integration architecture

Inspected baseline: `e04a16aed1beedbbba09ef75b961961326fc6ed0` (Windows 0.5.2 / TV 0.5.1), restored from the user's SHA-256 verified Git bundle into the existing Lingo workspace. The desktop APK matches the output APK (SHA-256 `d533e1cf9e994e90bd390de54033e18effb8a23948d16df31dac2a8a5651c06f`). No GitHub remote was configured. Existing evidence is historical, not a new physical-device test.

## Existing implementation

| Component | Existing code and behavior | iOS treatment |
| --- | --- | --- |
| Windows application | Python/PySide6 UI; `storage.py` JSON and DPAPI persistence | Separate SwiftUI target; UserDefaults and Keychain |
| Capture | `remoteplay.py` launches installed Chiaki with a separate streaming account; `capture.py`, `window_capture.py`, `frame_conversion.py` sample a Windows.Graphics.Capture window | Native Chiaki protocol bridge and VideoToolbox pixel buffers; no screenshot capture |
| OCR | `ocr.py` Windows.Media.Ocr; `recognition.py` dialogue ROI, menu/geometry filtering, two fresh empty observations | Vision English recognition with the same dialogue-first ROI and bounded scheduling; reproject Vision's ROI-relative boxes into full-frame top-left coordinates before filtering/tracking |
| Scheduling | `performance.py` Economy/Balanced/Performance caps 2/4/8, small edge mask and periodic verification | Thermal/low-power adaptation; single latest decoded-frame slot |
| Translation | `models.py`, `translation.py`: Argos EN–AR 1.0, SentencePiece/CTranslate2 int8, model reused, bounded caches, short-command overrides | Reuse exact verified model/tokenizer through native CTranslate2/SentencePiece; proprietary ML Kit is not linked into the AGPL-derived app; weights downloaded/imported separately |
| Event identity | `tracking.py`, `dialogue_events.py`, `pipeline.py`: normalization, stable UUID namespace, spatial/temporal OCR corrections, number/negation guards, latest pending translation, stale-generation rejection | Port algorithmic behavior and regression fixtures, independent of UI/runtime |
| TV transport | `network.py` **hosts WSS on translation source**, private IPv4 port 38443, JSON v1 / 16 KiB, self-signed ECDSA certificate, fingerprint-prefix + expiring PIN, token authentication | iPhone must host a TLS WebSocket server. A WebSocket client to the TV would be incompatible |
| TV receiver | `Receiver.kt` initiates connection; cert pinning; session/sequence guards; clears on disconnect; retry; settings acknowledgement | Preserve existing receiver and APK; pair TV to iPhone's address and identity |
| Display settings | `display_settings.py`, `appearance.py`: validated snake_case settings, revisions, presets, pixel offsets, independent style/position/timing messages | Preserve field names, bounds and revision ordering; expose native controls |
| Subtitle lifecycle | `SubtitleCanvas.kt`, `SubtitleState.kt`, `LayoutPolicy.kt`: TV owns adaptive reading clocks; 1–3 entries; latest anchored, older upward; correction retains timer; autonomous expiry and tombstones | Continue delegating rendering/lifetime to the existing TV. No second incompatible timer or history |
| Tests/build | `desktop/tests`, Kotlin state/layout tests, source build scripts; **no existing GitHub Actions workflow in baseline** | Keep platform builds independent; add iOS-only workflow |

## Target data path

PS5 (secondary streaming account) → Chiaki C protocol core → bounded compressed input → VideoToolbox → CVPixelBuffer → bounded latest-frame sampling → Vision dialogue ROI → stable event identity → one active + one latest pending offline translation → existing JSON v1 over iPhone-hosted WSS → unchanged TV receiver/canvas.

HDMI remains PS5 → TV. Cropping/sampling OCR does not reduce the original PS5 stream bandwidth. The existing usage guide requires a streaming account different from the controller's account; this must be verified again on iPhone. No continuous locked-screen/background operation is assumed.

## Verification boundaries

The local host is Windows. The owner subsequently authorized creating the private Aljjulanda/GameLingo repository, and the primary macOS workflow has executed with Xcode 16.4. Actual results are recorded in `../iOS/VALIDATION.md`. Simulator fixtures do not establish physical hardware decoding, real iPhone OCR/translation latency or PS5/iPhone/TV end-to-end behavior. Unsigned packaging is only successful when an actual archive exists and passes IPA validation. Do not infer Xcode 14.2 compatibility from the deployment target.
