# GameLingo for iPhone

Current work: [unregistered menus on demand](../validation/CURRENT-MENU-1-RESUME-AR.md). Home / Games / Settings and setup compiled successfully; [UI results](../validation/UI-SETUP-2-RESUME-AR.md) include the reviewed accessibility screenshots and separate earlier invalid image evidence. The last delivered play preview is documented in [PLAY-PREVIEW-1.md](../validation/PLAY-PREVIEW-1.md). The older build records below are historical.

This is a new native iOS target inside the restored GameLingo Windows/Android TV repository. Existing platform code is preserved. The actual iPhone app has compiled, linked and archived unsigned with Xcode 16.4 in GitHub Actions; 16 core tests and 7 Apple integration tests passed. **Physical iPhone/PS5/TV acceptance has not been performed.** Read `../docs/IOS_ARCHITECTURE.md` before changing the protocol and `VALIDATION.md` for the recorded build results. The Arabic delivery report is in [DELIVERY_AR.md](DELIVERY_AR.md).

## Implemented source

- SwiftUI Arabic RTL connection, translation/model, subtitle controls and performance tabs.
- Pinned Chiaki-derived protocol core, PS5 LAN discovery and manual-address registration, Keychain credentials, bounded reconnects, login PIN handling, H.264 720p30 stream profile.
- VideoToolbox decoder with a bounded compressed queue, direct CVPixelBuffer delivery and no video view or screenshot capture.
- Vision English dialogue ROI, desktop-derived structural dialogue gate, 2/4/8 sampling caps with thermal/low-power adaptation, one latest retained frame.
- Existing Argos EN–AR model, SentencePiece and CTranslate2 C++ bridge, one reused model/inference worker, bounded 256-entry in-memory translation cache and desktop short-command overrides.
- Stable dialogue event IDs, ordered corrections, independent generations, number/negation guards, latest pending request and stale-result rejection.
- iPhone-hosted WSS/38443 using the existing TV protocol, self-signed TLS identity, fingerprint + expiring PIN and token authentication, bounded output, no subtitle replay, same settings fields/revisions.
- Native appearance/position/timing controls, TV preview, desktop style import and persistent non-secret settings. The unchanged TV owns Arabic rendering, stacking, independent timers and automatic expiry.
- Core XCTest suite, simulator-only integration tests, deterministic actual Xcode project and independent unsigned IPA workflow/scripts.

## Primary build: GitHub Actions

The restored history and iOS implementation are hosted together in the private [Aljjulanda/GameLingo repository](https://github.com/Aljjulanda/GameLingo), created with the owner's explicit authorization after no original remote could be found. Run `.github/workflows/ios-build.yml` with workflow_dispatch, or push an iOS change to main or a codex branch.

The workflow uses Apple Silicon `macos-15`, explicit Xcode 16.4, source validation, pinned-source preparation, native device/simulator compilation, Swift package core tests, Apple integration tests, an unsigned archive, ZIP/Mach-O IPA validation and artifacts. Intel device compilation was also exercised before changing runners to avoid a long Intel queue and slow simulator initialization. No Apple certificate, provisioning profile, team or signing secret is required for the release archive. Simulator tests use the runner's local ad-hoc signing where needed for Keychain; that identity is not packaged in the IPA.

The artifact is `GameLingo-unsigned-IPA`, containing **GameLingo-unsigned.ipa**. The complete workflow passed in [run 43423525500](https://github.com/Aljjulanda/GameLingo/actions/runs/43423525500) at code commit `c6be805d35a0ffd5dca0cbee4cc6d90c1b23f20f`; [download the artifact](https://github.com/Aljjulanda/GameLingo/actions/runs/43423525500/artifacts/14035187638). The actual IPA was independently downloaded/validated on Windows. Device archiving/upload precedes simulator provisioning so a runner boot failure retains the built IPA; an artifact alone does not certify hardware acceptance. Logs and `.xcresult` are uploaded separately even if testing fails. The workflow follows the archive → Payload → zip methodology inspected in [BaraAlSalfaOman build.yml](https://github.com/Aljjulanda/BaraAlSalfaOman/blob/main/.github/workflows/build.yml) and its [unsigned script](https://github.com/Aljjulanda/BaraAlSalfaOman/blob/main/Scripts/build-unsigned.sh).

## Local Mac backup

Install Git, CMake, Ninja, protoc and Python 3.10+; select Xcode, then:

```bash
cd iOS
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash Scripts/prepare.sh
bash Scripts/test.sh
bash Scripts/build-unsigned.sh
```

`prepare.sh` fetches immutable native source revisions and selected pinned submodules into ignored `.build`, applies guarded patches, compiles iPhone libraries and resolves ZIPFoundation. `test.sh` also builds native simulator libraries and downloads the exact desktop model as an XCTest-only resource. It builds the test target, chooses/boots an explicit iOS 18.5 simulator, and executes the tests; failure attachments are exported with the logs. Use `IOS_TEST_DESTINATION` for a different installed simulator. Scripts fail instead of substituting stub libraries. Native libraries have compiled for iPhone arm64 and both arm64/Intel simulators; the complete simulator suite passed on arm64. Other toolchains remain unverified.

Open `GameLingo.xcodeproj` after preparation. Source changes can be registered deterministically with `python3 Scripts/generate-project.py`. Do not add Windows or Android sources to the iOS target.

## Legacy compatibility report

| Requirement | Status |
| --- | --- |
| macOS Monterey 12.7.6 / installed Xcode | Not accessible; actual installed version unknown |
| Xcode 14-readable project | Generated OpenStep project objectVersion 56, compatibilityVersion Xcode 14.0 |
| Swift 5.7 / iOS 16 source baseline | Intended; no SwiftData/Observation/Translation-framework dependency; deployment target 16.0 |
| Xcode 14.2 compilation/link | **Not verified**; dependency/toolchain compilation may need changes |
| Simulator XCTest async expectations | Uses modern XCTest `fulfillment`, primary build Xcode 16.4; Xcode 14.2 test compatibility is not claimed |
| Modern iPhone debugging from old Xcode | Not guaranteed by the older deployment target; sign/install separately |

## On-device setup

1. Sign the actual unsigned IPA with your own identity. LAN discovery uses UDP broadcast and the multicast entitlement; your signing profile may need Apple's multicast entitlement. Manual PS5 IPv4 registration is available when discovery is unavailable. External signing is your responsibility.
2. Put iPhone, PS5 and TV on the same reachable private IPv4 LAN. Allow Local Network access. The app binds only a selected local interface/address.
3. In Translation, download or import the exact existing EN–AR Argos package. The model is checked by size, SHA-256 and language pair, then loaded once. It works offline afterward. No paid API or subscription.
4. Register PS5 with the **secondary streaming account's** Base64 8-byte PSN Account ID and the console's 8-digit link code. No PSN password/token is requested by this app. Start the console with its controller if necessary.
5. Start the TV connection on iPhone. In the existing TV app enter the iPhone address in its existing computer-address field, plus the 12-hex-fingerprint/6-digit-PIN code. Existing Windows pairing is independent; switching source requires pairing to that source again. No TV APK update is required by this implementation.
6. Import the existing Windows `settings.json` under Subtitle Settings if you want the saved appearance instead of iPhone defaults. The current TV protocol has no settings-read API, so iPhone cannot silently retrieve the TV's saved style. Controls sync and preview live.
7. Choose the saved console, prepare the model, and start translation. Keep HDMI gameplay/controller on the main account. Keep GameLingo foreground/unlocked; leaving the app stops sessions and WSS. Optional dimming restores the prior brightness on stop/background.

## Known limitations and required acceptance

- Consult `VALIDATION.md` and the linked Actions run for actual build and artifact status.
- PS5 discovery/pairing, login PIN behavior, account/controller coexistence, reconnection and stream decoding require physical-device verification. The existing guide's second-account workflow is evidence from Windows, not iPhone validation.
- Native CTranslate2, SentencePiece and Chiaki compile on the primary runner. The original model's physical iPhone latency, accuracy, memory, battery and thermal behavior have not been benchmarked. No comparative device measurements support a superiority claim.
- Model redistribution terms are unresolved in its metadata; release IPA excludes weights. See `THIRD_PARTY.md`.
- No locked-screen streaming, background mode entitlement, cloud translation, dialogue history, replay, menu translation, controller input UI, Internet Remote Play or PSN OAuth login is implemented.
- Optional nearby-context translation is omitted; it remains absent/disabled rather than guessing source-to-TV coordinates.
- Reading expiry/stacking tests are preserved in the unchanged TV implementation. iOS does not implement a second renderer/timer.
- Performance values report processing latency, frame count/drop count, bounded translation depth, sampling cap, network status, available process memory and thermal state. No fabricated CPU/GPU counters.

Use `DEVICE_TEST_CHECKLIST.md` to record actual acceptance. Never mark a physical test passed using synthetic simulator fixtures.
