# Quality fixes batch 1 — execution record

## Baseline and gates

Latest published release (drafts excluded, prereleases included, sorted by
`published_at`): `ios-v0.3.0-preview.3`, published 2026-11-14T19:33:29Z,
commit `bf3675e66147ba9202eec7252726e16b2c9090f6`, prerelease=true.
Branch `codex/quality-fixes-1` starts at that commit, not main.

The release contains `GameLingo-unsigned.ipa` (iOS 0.3.0 build 8,
`dev.gamelingo.ios`, deliberately unsigned for external signing) and **no APK**.
Build route: `.github/workflows/ios-build.yml`, macos-15/Xcode 16.4; retained.
The latest release is experimental; this was reported before branching.
Its native picker UI automation failed; portable/core and Apple integration
tests passed. Subsequent run 43634745988 on importer HEAD also failed the native
picker UI test (remote accessibility snapshot interruption); 78 core and 30
Apple integration tests passed. This is not recorded as a successful full run.
The user separately confirmed real-iPhone GLPACK import and selection of ZIP,
EXE and an unknown extension. That does not replace the automated release gate.

TV source at baseline: 0.6.1 (9), package `dev.gamelingo.tv`. Original signer
SHA-256: `48cf8a45a37f4e5c338f98fa7d5135c7cdbaf59d50b39b8bf591a79622a28e38`.
Original keystore exists outside Git; supply its path through
`GAMELINGO_TV_KEYSTORE` for builds, never generate a replacement production key.
No secrets are included in this record. Previous releases remain untouched.

## Importer prerequisite comparison

Compared release commit to `codex/universal-file-importer` at
`9df94d32e6d4a6c6589a39729eeb37b3e998206f` for all eleven requested files.
Nine are identical: FramePipeline, OfflineTranslator, DialogueContent,
OCRDialogue, VisionDialogueOCR, Dialogue, SubtitlePresentation,
TranslationPacks and PackDatabase. Only LocalizationImport (NUL rejection in
IDs/metadata) and GameTranslationImporter (explicit SQLite UTF-8 bind lengths)
differ. No missing importer/pack/metrics prerequisite requires a broad merge.
Port these small data-safety guards with their tests; do not merge unrelated
version bumps or unverified picker automation changes.

## Environment and scope

Read ADVANCED_PREVIEW.md, docs/IOS_ARCHITECTURE.md and VALIDATION.md before code.
Local host is Windows; no Swift, Docker or installed WSL distribution available
on PATH. Apple SDK/native Simulator tests require existing macOS Actions route.
Focused portable Swift checkpoints (Ubuntu 24.04, installed Swift reported in logs) must pass before proceeding to each following unit;
full archive/native/GUI tests remain a separate final gate. Android SDK/JDK21/
Gradle 8.9 and original signing key are available locally. Emulator and physical
TV availability must be verified rather than assumed.

No PS5, stream decode, sampling, ROI, network/pairing, background/recovery,
duplicate suppression, TV clocks or Windows changes are authorized by this batch.
No new release exists yet. Units A–I and final compatibility/latency/signature
validation are pending; this document is an execution record, not certification.

## Unit A — work in progress

Implemented independent persisted flags (all default OFF): `quality.measurement`,
`quality.provenanceMarker`, `quality.punctuationTrace`, `quality.sessionCapture`.
Capture additionally requires explicit per-session consent and never resumes
from saved settings. Other enumerated flag IDs are reserved; no corresponding
unimplemented options appear in the UI. Tests must pass before proceeding to B.

Extends HybridMetrics (moved into portable Core, not duplicated), retains legacy
attempt counters, adds published unique-event provenance and fallback reasons.
Y means first accepted publication of a stable dialogue ID within the selected
pack activation, not lookup attempts or synthetic probes. Publication IDs are
RAM-only and capped at 50,000 with an explicit saturation bit. Synthetic pack
probes use seeded validated EN sources and the existing lookup function without
incrementing gameplay counters. Logical punctuation traces contain marks,
positions and first-strong class only. Rendered-TV signatures/markers still
require the coordinated TV change; not yet verified.

Opt-in capture uses one bounded JSONL (4 MiB / 30 minutes), complete iOS file
protection, backup exclusion, expiry after 24 hours, explicit export/delete,
Stop handling and no automatic continuation after process termination. Native
protection/inference/cache checks are added to the Apple integration target but
have not run yet. Portable fixtures cover denominator, independent persistence,
optional-wire rollback, logical trace, consent, size/time/retention and replay.

Local results: source preservation/project validation passed, four packaging
tests passed, 17 converter tests passed. Initial macOS checkpoint 43839023313
remained queued for over eight minutes without a runner, annotations or test
output. Portable checkpoints use the supported Linux Swift package to avoid
that queue; this does not replace Xcode 16.4/native/Simulator release checks.
No unit is certified yet and no release was published.

### A focused results so far

- Portable Swift: 86 XCTest cases passed on Swift 6.4.2/Linux, run
  https://github.com/Aljjulanda/GameLingo/actions/runs/43840385496 at `684f1dc`.
  The final Swift Testing line reports zero tests because these are XCTest
  cases executed by the parallel runner, not Swift Testing declarations.
- Android: 31 JVM tests passed, zero failures/errors; production-package APK
  built locally using the original keystore. Verified APK signer fingerprint
  matches the installed baseline. This is an intermediate APK, not a release.
- A subsequent optional rendered trace now returns a strictly validated,
  bounded content-free signature in an existing render ACK; no new message
  type, transport layer, authentication, timer or pairing behavior changes.
  A new trace flag OFF emits no optional request field. Native tests pending.
- Physical TCL ADB at its last known address did not respond; no physical
  rendering or gameplay validation is claimed for these changes.
- Release baseline's picker UI harness taps filename captions. Previous
  importer attempts improved this to thumbnail taps but mistook the ZIP icon's
  own text for the filename. The harness now requires filename-specific OCR
  patterns, waits for provider dismissal before querying AUT accessibility,
  and still verifies the delegate-delivered filename. These test-only changes
  remain unverified until the actual native GUI run passes.

### Native environment blocker and authorized retry

Full Apple run https://github.com/Aljjulanda/GameLingo/actions/runs/43841413404
never acquired a runner and failed before any build/test step. GitHub's exact
annotation: "The job was not acquired by Runner of type hosted even after
multiple attempts", plus an explicit macOS ARM64 capacity notice. This is not a
compiler/test failure and produced no IPA. Latest portable run
https://github.com/Aljjulanda/GameLingo/actions/runs/43843783626 passed 87 XCTest
cases at `d54e9eb`; native integration/GUI checks remain pending.

The user was informed and replied "نفذ اللي تشوفه مناسب" to the runner choice.
Use macos-15-intel with **the same Xcode 16.4 and all existing build/test gates**.
The archive destination remains generic physical iOS/ARM64. Simulator native
inference on Intel uses the existing FLOAT32 branch, so timings/model results
must be identified as Intel Simulator, not phone/ARM64 measurements. No signing,
security or mandatory test bypass is introduced.

Replay now calls the same production post-OCR selector/parser and the existing
tracker/publication gate with an explicit synchronous stub. The selector was
extracted verbatim from Vision into existing Core/OCRDialogue.swift, verified by
literal function-body comparison; Vision delegates to it. Original fallback
box arithmetic is retained, including floating-point representation. Sampling,
ROI and duplicate algorithms are unchanged. Added real replay fixtures for
speaker segmentation, duplicate suppression and negative menu selection.
Unit A is still awaiting native verification. Units B–I have not started, and
there is no new release.

### Immutable real-data fixture source

The Intel runner started, but run 43844820344 stopped before archive/native
integration at the unchanged real-RDR2 fixture's SHA-256 check. The mutable
upstream Pages installer changed after the approved baseline tests. Reviewed
metadata: current 11,940,944 bytes / SHA-256
`a3992dfad44167947a18ac46cf7c81e037adb274c1ab4d4beff9c244893bd88b`;
approved desktop file 11,941,456 bytes / SHA-256
`3eaead8f4e851ad6c6c9a894415799e047928c522f009a632830cc3826fd0598`.

Fetched bounded historical upstream revisions without executing any installer.
Commit `04e9bb1ee583740fcba30b1a016329d4a3243a62` contains bytes identical to the
approved file (same length AND SHA-256). The validation script now downloads
that immutable upstream revision; **the approved digest is unchanged**. No
fixture, hash verification or test is skipped, and no localization is uploaded.
Two other reviewed revisions did not match and were not adopted. The test
continues to statically extract and validate the original approved corpus.

Also corrected provenance classification of cached command-map outputs: they
remain `command`, never `argosCache`. The shared command table/text/key behavior
is unchanged; new portable tests distinguish it from real model-cache hits.
No translation punctuation behavior has changed yet (unit F is pending).

### Approved-corpus check restored; standalone benchmark dependency fixed

Intel run 43846469584 passed the original-corpus native SQLite validation:
228,174 rows / 209,459 eligible; 1,000 correct matches and 102 expected
rejections; 1,102 lookups, average 0.081 ms / p95 0.107 ms. Validation took
14.918 s on the Intel CI Mac; this is lookup correctness, not game quality.
The run then caught a real integration error: adding the provenance helper to
DialogueContent introduced a TranslationOrigin dependency into a standalone
maintenance benchmark that intentionally compiles only legacy dialogue files.
Move that helper to Core/TranslationCommands.swift; do not weaken or modify the
benchmark. Native archive/integration/GUI gates have still not run. Retry all
required checks after correcting source organization.

### Unit A native failures under investigation (no release)

Run 43847957262 compiled/archived the actual iPhone target and passed the
independent IPA validator: 2,893,765 bytes, SHA-256
`2ebcde90e285e836ee3d8520d2a3fedef40f672990e1035ffdffd1d3fb4111cc`,
`dev.gamelingo.ios` 0.3.0 (8), unsigned ARM64. Intermediate only; not published.
It passed 89 portable tests and original-corpus/maintenance checks, then ran
32 Apple tests with six assertions failing in **two** cases. Existing TV WSS,
Keychain/TLS, Vision, native model inference and all 13 pack/import tests passed.
New real-Argos provenance/cache/equivalence test also passed.

Five assertions were one cascading Smart Reading failure after the original
20-second cold-model-load expectation timed out on the overloaded Intel
Simulator. The log contains CoreAudio host-overload warnings; that is evidence
of contention, not proof of the exact load delay. Do not change production
background/audio/recovery behavior. The test now reports actual cold-load
milliseconds, keeps a bounded 90-second startup deadline (separate from
post-OCR latency), and does not proceed with an unloaded model. All existing
fresh-frame, translated-page, retained-number and RAM-context checks remain.
Actual post-OCR/readiness deadlines are unchanged.

The sixth assertion cast Foundation's untyped protection attribute directly to
FileProtectionType and obtained nil. Read both the imported newtype and its
NSString raw value; report metadata presence/type to distinguish bridging from
unsupported metadata. The expected class is still COMPLETE, not relaxed. Also
set file protection explicitly after the empty-file creation, and fail closed
on a physical iPhone if read-back does not confirm COMPLETE. No dialogue is
written before that check. Simulator support is NOT assumed or claimed yet.

Focused native checkpoints can select explicit XCTest identifiers and reject
an empty/no-executed test result. They do not generate a release IPA and cannot
substitute for the full unfiltered archive/native/GUI final workflow. Unit A
still needs the affected native checks to pass before proceeding to B.
