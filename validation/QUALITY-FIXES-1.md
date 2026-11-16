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
Focused Swift checkpoints must pass before proceeding to each following unit;
full archive/native/GUI tests remain a separate final gate. Android SDK/JDK21/
Gradle 8.9 and original signing key are available locally. Emulator and physical
TV availability must be verified rather than assumed.

No PS5, stream decode, sampling, ROI, network/pairing, background/recovery,
duplicate suppression, TV clocks or Windows changes are authorized by this batch.
No new release exists yet. Units A–I and final compatibility/latency/signature
validation are pending; this document is an execution record, not certification.
