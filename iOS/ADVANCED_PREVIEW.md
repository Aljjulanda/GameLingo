# GameLingo advanced preview: implementation and evidence

**2026-11-14 physical TCL follow-up:** document rendering, real receiver delivery and pinned mDNS recovery subsequently passed. See [TCL-PREVIEW-2026-11-14.md](../validation/TCL-PREVIEW-2026-11-14.md). The original release copy of this report predates that follow-up; the IPA/APK binaries are unchanged.

## Protected baseline

The user confirmed physical iPhone/PS5/TCL operation on iOS 0.1.1 / TV 0.5.2, commit `ce6d3995f20b2250f5567348c7b7c6834785e172`. Low battery use and no noticeable heat are user observations, not lab measurements. Recovery tag: `stable/real-device-0.1.1`; development branch: `codex/advanced-ios`. Main and the stable release remain unchanged. An ignored local recovery bundle also preserves the baseline.

Architecture stays Chiaki -> VideoToolbox -> CVPixelBuffer -> cropped Vision -> Argos/CTranslate2 -> pinned WSS -> TCL overlay, with gameplay on HDMI. No continuous video renderer, microphone, PS5 audio playback, cloud, subscription, frozen-image feature or permanent dialogue/document history is added. Windows and native PS5 bridge source are unchanged.

## Build provenance and delivery limit

Certified iOS snapshot: `e7b7a3ea3782408e8768477a80d3c32331594929`, [successful run 43527679961](https://github.com/Aljjulanda/GameLingo/actions/runs/43527679961), iOS 0.2.0 (3). It passed 42 portable Swift tests, 14 Apple integration tests and four packaging-tool tests. These run on macOS/iOS Simulator, not a physical iPhone. TV preview version: 0.6.0 (8).

The next run, [43529787191](https://github.com/Aljjulanda/GameLingo/actions/runs/43529787191), commit `34d3a603c3fab642c71530715569ae10ddbf0ff6`, **did not start a runner**. GitHub reported failed recent payments or a spending limit needing increase. No account payment settings were changed. This is an account block, not a reported compilation/test failure. Later app changes must not be attributed to the earlier IPA.

Post-snapshot changes awaiting an Apple build: restore brightness/idle assertions when leaving the UI; Connection-tab Smart Reading shortcut; decoded-frame starvation recovery/counters; server-originated WebSocket ping watchdog. Android's additional NSD exception guard compiles locally but is also after that snapshot. The certified snapshot already supports native disconnect callbacks, client ping/pong, heartbeat, secure reconnects, manual-stop intent, background experiment and Smart Reading from the Translation tab. **Turn screen dimming off before trying background operation with that snapshot.**

## Background experiment and recovery

`BackgroundAudio` uses AVAudioEngine with a mono zero-producing source node, `.playback` and `.mixWithOthers`. The callback only clears buffers; it does not allocate OCR tasks, access the microphone or duck another app. The saved option defaults off, including old-settings migration. An active engine is not proof iOS allows indefinite OCR execution.

User intent, foreground, network, audio execution, suspension and intentional Stop are distinct. Interruption-began pauses audio while initially preserving healthy connections. Ended/shouldResume, route change, secondary-audio hint, media-services reset, foreground and network restoration provide recovery opportunities. Recovery respects external audible audio and uses a cooldown; no audio-focus polling loop is introduced. Now Playing is omitted because status controls do not grant execution time.

Without a valid execution mode, a UIKit background task supplies at most 20 seconds or OS expiration, then pauses processing/network while preserving intent. Stop invalidates retries, clears RAM context and persisted intent, and stops audio/native sessions. Notifications cannot resume a manually stopped session. Previous intent only recovers when saved console credentials, the model and network are available; the model is not reloaded repeatedly.

PS5 pointer/epoch guards retain healthy or starting sessions. Stale inference is generation-cancelled. The TV identity/token digest can remain cached across automatic rebinding; transient `EADDRINUSE` retries are bounded at 250/500/750 ms. Listener failures clear the starting flag for later recovery. Continuing old subtitles are suppressed after interruption instead of replayed.

Background Vision uses CPU-only recognition to avoid relying on GPU availability; this needs physical energy/latency measurement. Keychain protection remains `WhenUnlockedThisDeviceOnly`: an already-running cached listener can authenticate, but cold identity creation/new pairing while locked may fail. OS suspension may prevent every recovery callback. Automatic recovery after Instagram audio stops and lock-screen translation are **not physically certified**.

Bonjour `_gamelingo._tcp` advertises a public certificate-prefix hint. TV discovery only runs with a saved full SHA-256 pin and token, for a bounded 12-second window. The address is saved only after full TLS pinning/token authentication. First pairing remains manual. No trust bypass, location, VoIP or PiP is added. IPv6-only and multi-interface discovery remain unverified.

## Stable dialogue and inline names

English normalization, source position, continuity, confidence, speaker and disappearance preserve event identity. Cosmetic changes/Arabic paraphrases do not create a card or reset expiry. Negation, numbers, person/directions and changed destinations are protected. Conservative early semantic repair updates the same ID; later or clearly new dialogue gets a fresh ID. Repetition after disappearance is allowed. Bounded caches/tombstones prevent expired resurrection; no history is persisted.

TV `SubtitleState` repeats source-based stability before rendering, retaining the existing three-entry maximum, independent expiration, latest anchor and older-entry stacking. Corrections update the same card without restarting its clock.

Speaker detection accepts high-confidence `Name:` or a reliably separated label, optionally assisted by a comma-separated dictionary. Ordinary HUD words and weak OCR do not infer a person. The detected name is excluded from Argos input. Android renders a bidi-isolated inline prefix in default `#A6C7D8`, with show/hide/color/default controls. Spans preserve wrapping, outline, background and expiry. The user tests multiple games; no one-game dictionary is imposed. Unusual game layouts can still be missed.

## Smart Reading

An explicit request pauses dialogue publication, clears the latest-frame slot and waits up to six seconds for a fresh decoded frame. On-demand full-frame OCR reconstructs reading order/paragraphs. Existing Argos translates sentence-aware paragraph chunks sequentially; Arabic pages remain RAM-only. Closing cancels work through generation/ticket guards, clears the panel and restores dialogue without entering document text into context.

Limits: 150 OCR lines / 16,000 English characters, approximately 400-character sentence-aware chunks, up to 64 Arabic pages of 600 characters. Oversized content reports an error instead of silently truncating. The separate TCL panel supports multiline pages, Next/Previous/Close from the phone. No image freezing or archive exists. Complex multicolumn layouts and LLM-level paragraph coherence are not claimed. Read complex layouts in smaller visible sections.

New document/spans rendering requires the 0.6.0 APK. Older TVs retain normal v1 dialogue. Capability fields are optional; rendering ACKs are sent only if supported by the server, retaining compatibility with Windows's accepted message types. ACKs are emitted after actual Canvas drawing rather than socket receipt.

## RAM context and honest translation limits

Memory defaults to five previous events, with enable switch and saved capacity 1–20. Entries contain ID, source, confirmed speaker, timestamp and confidence. Corrections replace an event, documents are excluded, entries expire after 90 seconds, and Stop clears them. Conversation text is never saved to disk.

The actual use is **context-assisted whole-sentence terminology**, not a newly context-trained Argos model. For example:

```text
Collect 11 coins. = اجمع 11 قطعة نقدية.
river | Wait near the bank. = انتظر قرب ضفة النهر.
```

The optional trigger matches recent English words or a confirmed speaker at word boundaries. Rules are explicit and selected before publication. Previous sentences are not concatenated into model input. There is no blind idiom replacement or delayed second-engine rewrite. Without a matching rule, the existing Argos limitations remain.

An actual Qwen2.5-0.5B Q4_K_M / llama.cpp Windows CPU pilot ran four synthetic cases with context sizes 1/5/10/20. Argos median was about 47 ms / maximum sampled process RSS 141 MiB; Qwen about 761 ms / 500 MiB. The candidate lost negation, changed objects/numbers and produced unrelated text. It is rejected and not bundled. Larger memory did not guarantee quality. This small pilot is not an iPhone energy or real-game quality benchmark. See [Benchmarks/README.md](Benchmarks/README.md), pinned downloads and full measured outputs. A reviewed real-game corpus and suitable on-device model remain outstanding.

An additional actual-native Simulator benchmark tested the app CTranslate2 bridge and explicit authored rules: three synthetic cases, Argos roughly 21–31 ms, matching authored-rule selection roughly 0.07–1.97 ms. This measures rule selection on the CI machine, not general translation quality or physical-phone speed.

## Precise controls and measurements

Numeric subtitle/ROI/performance controls provide large +/- targets, numeric keyboard, visible bounds and per-field default reset. Arabic/Persian digits and decimal separators are supported; malformed/NaN input leaves the saved value unchanged. Apply or leaving the field validates/saves. Style updates are debounced. Physical movement directions remain independent of RTL, with steps 1/5/10/custom. Shared Windows display bounds/defaults are preserved.

Performance shows actual OCR/translation timing and bounded p95 windows, queue depth, context count, process CPU (100% = one core), RSS, available memory, thermal state, approximate battery change and document timing/sampled RSS delta. Background delivery counts require new-TV render ACKs. Diagnostic sampling is not Instruments energy profiling. Shared logs exclude PINs, tokens, private keys, dialogue history and credentials; connection diagnostics can contain local IPs.

## Evidence matrix

| Area | Completed evidence | Remaining limitation |
|---|---|---|
| Baseline | Recovery tag; unchanged Windows/native PS5; preserved-source validator | Preview is not promoted to stable |
| Swift | 42 core tests in certified snapshot | Later source awaits Apple build |
| Apple | 14 tests: VideoToolbox without renderer, Vision, native Argos, Smart Reading, audio notifications/Stop, metrics, TLS identity, LAN OkHttp | Simulator only |
| Network | Real JVM OkHttp 4.12.0 -> Simulator LAN listener: PIN/token, settings ACK, heartbeat/ping, bad PIN/pin/token, replacement/restart, document capability/session/sequence | New phone/TCL end-to-end not certified |
| Android | 24 JVM tests, production APK build, original signer identity | Complete new APK physical acceptance pending |
| TCL | Physical isolated Lab renderer passed inline spans/color/RTL/wrapping/stable clock/anchor | Earlier feature snapshot; document/discovery checks pending |
| Windows | 51 existing pytest tests pass; unchanged Hub with capability-offering OkHttp passes pair/settings/heartbeat/reconnect/full-pin/token rejection over PC LAN | Equivalent client, not final receiver on TCL |
| Dialogue/context | Correction/repetition/expiry/bounds/scoped-rule fixtures | Multiple real-game quality/layout evaluation pending |
| Background | State-machine/notification/cancellation checks and opt-in implementation | No continuous physical-background success claim |
| Resource cost | Windows pilot, native Simulator timing, app instrumentation | Phone baseline-vs-preview energy/thermal comparison pending |

TCL ADB became unavailable during final testing; unexecuted document/discovery checks were not recorded as passes. Lab package `dev.gamelingo.tv.lab` has independent preferences/Keystore; production pairing was preserved. Production `dev.gamelingo.tv` uses the original certificate SHA-256 `48cf8a45a37f4e5c338f98fa7d5135c7cdbaf59d50b39b8bf591a79622a28e38`.

## Repeatable checks

```text
python iOS/Scripts/validate-source.py
python iOS/Scripts/test-build-tools.py
cd iOS && swift test --parallel
bash iOS/Scripts/test.sh
gradle -p android-tv testDebugUnitTest assembleDebug
PYTHONPATH=desktop python -m pytest desktop/tests -q
python iOS/Integration/test-windows-compatibility.py --host <PC-private-LAN-IPv4>
```

Set `GAMELINGO_TV_KEYSTORE` to the original signing keystore. `-PlabBuild -PadvancedCanvasTest` selects Lab and `AdvancedCanvasRunner`; `-PlabBuild -PtvNetworkTest` selects `NetworkRunner`. Lab/test APKs must not be published as production. The preserved unsigned Actions workflow uses Xcode 16.4/macOS 15. Resolve the account block before certifying later app source.

## Physical acceptance and rollback

1. Stop translation. Update the TV APK without uninstalling. Externally sign the IPA with the same signing identity and update without deleting app data. Retain PS5 and TV registrations.
2. First verify foreground new dialogue on TCL with background mode off. Compare speed/battery/heat with baseline. Exercise cosmetic/semantic corrections, genuine repeats and inline names across games.
3. Read a short letter, then long multipage text. Navigate/close and confirm new dialogue resumes with no document context pollution.
4. Turn dimming off for the certified snapshot, enable background experiment, and observe **new** dialogue IDs/TV render ACKs from Home, Safari, WhatsApp, Instagram scrolling/video/audio-stop, calls and Bluetooth routes. Repeat screen-lock sessions of 5/15/30/60 minutes and background Wi-Fi interruption. Record states, CPU/RSS/thermal/battery and timing. An old subtitle or audio control is not success evidence.
5. Verify Stop prevents later auto-resume; foreground return creates no duplicate PS5 session; IP changes retain the full pin/token. No repeat PS5 registration is required.
6. For regression, Stop before replacing builds. Stable 0.1.1 / TV 0.5.2 stay in the prior release. Preserve data/signing identity; TV version downgrade may need `adb install -r -d` and can be restricted by the device. Do not uninstall production to force rollback.

## Platform references

- [Playback](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback), [mixWithOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers), [interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions): audio configuration is not an indefinite unrelated-work entitlement. Compatible legacy notifications are retained for the current SDK.
- [Long-running tasks](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados): finite user-initiated jobs with progress/cancellation, not endless game streaming. A future finite reading task needs newer SDK integration and hardware tests. BGProcessingTask is system-scheduled. Live Activities/Now Playing do not grant execution. PiP was not justified.
- [Local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): permission and declared Bonjour service remain necessary; listener ready does not prove peer reachability.
