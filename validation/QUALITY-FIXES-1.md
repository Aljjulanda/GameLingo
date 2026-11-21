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

### Focused native evidence and final unit-A corrections

Focused run 43854174879 executed four cases. Secure WSS and actual Argos
cache/equivalence passed. Model initialization measured 13,551.5 ms on this
Intel Simulator. Smart Reading still failed because the test constructed and
OCR-warmed its image AFTER starting the production six-second fresh-frame
wait. Move synthetic image preparation before the request; offer its frame
only after the waiting state is observed. Production deadline/reading code is
unchanged; translated pages/number/freshness/context checks remain required.

Protection metadata was absent (`present=false`) even after explicit setting;
this is now an observed runtime limitation rather than an assumed cast issue.
A direct Foundation control-file probe must confirm the same absence before
marking the metadata-only hardware check skipped on Simulator. Backup exclusion,
consent, no automatic resumption, limits, retention and replay remain tested.
The real-device path never skips: it refuses recording unless COMPLETE is
read back. A portable policy test rejects missing/weaker/unrecognized classes.
Do not claim hardware encryption was validated by Simulator results.

Final provenance ledger replaces each stable ID's source on accepted updates,
without increasing Y. X follows the actual final source, including reuse with
an explicit original basis and non-nil pack identity. Attempt origins/fallbacks
are recorded before inference, including later cancellations. Rule/reuse paths
are counted; selection identity rejects stale attempts. The UI immediately
clears stale scope counters when changing games/activation and when resetting
measurement. Unknown/synthetic compatibility probes never affect the ledger.

Trace now uses actual Unicode Bidi_Class (ICU on Swift / Character on Android),
including Roman numerals and supplementary Arabic letters; no script-range
heuristic. Android's 31 JVM tests passed again after this change. Optional
`provenance_basis` is sent only with the marker flag; all flags OFF omits every
new optional field.

Capture records pre-filter raw Vision lines AND actual glyph-derived segments,
not only successful publications. Raw observation records have no fabricated
engine provenance; publication records carry the chosen origin/basis. Monotonic
relative timestamps allow typewriter replay. The replay selects the raw stream
when present and never counts publication records as extra OCR reads. Both
streams remain within the same protected, bounded, consent-only JSONL file.
No production OCR sampling, ROI, filtering or duplicate algorithm was changed.

### Unit A checkpoint accepted; unit B in progress

Source b00f181 passed all 91 portable Swift cases (run 43858901911), 31 Android
JVM cases, packaging/source checks, and five native runtime cases in focused run
43858905781. The sixth native case explicitly skipped only the hardware file-
protection metadata assertion after both capture and direct Foundation control
returned no metadata. Consent, backup exclusion, no resumption, bounds and the
physical-device fail-closed COMPLETE policy remain required and passed their
available tests. This is not a full release gate or physical-device validation.

Unit B extends the existing parser/selector; all four flags remain OFF by default.
Recognized leading cues keep a distinct English source identity, while only the
body reaches rules/pack/Argos. A cue alone uses the authored masdar, never model
inference. Optional cue metadata is ignored by old TVs (a cue-only body remains
readable); inline styling arrives in G. Mid-sentence and uncertain narrative
brackets remain intact. Confirmed spatial labels can be removed without claiming
their identity; hidden counts and confidence bins contain no text. Digit names
use explicit bounded patterns, and entirely ordinary/HUD prefixes are excluded.
Geometry preferences are independently persisted and bounded in Advanced.
Vision's existing language-correction setting remains enabled; customWords are
deduplicated/capped at 200 and cleared when the dictionary flag is OFF. Real
Vision comparisons and portable regression checks are pending before unit C.

Unit B portable checkpoint 43865241302 passed all 100 Swift cases, 4 packaging
cases and 17 converter cases on a5f70ad, including Latin accents/curly apostrophes
and dictionary HUD/invalid-digit exclusions. Native run 43863620579 (f9a7ec9)
executed five methods: actual production pipeline cue-only/body-rule with NO
installed model passed, and both original above/side/wrapped Vision cases passed.
The new dictionary comparison and direct cue fixture failed because selected text
was empty; ordinary examples failed both with dictionary OFF and ON, while both
name examples passed in each mode. Fixed fixture left coordinates were not centered
inside the existing conservative dialogue gate. Center synthetic samples, assert
raw Vision words separately from selected dialogue, and rerun. Production ROI,
sampling, selector thresholds and model paths remain unchanged. These failures
are not waived and B is not yet accepted for progression to C.

### Unit B actual native results and Simulator crash

Run 43866560622 (8874bf6) passed the actual no-model cue/body-rule pipeline,
raw Vision dictionary controls (names 2/2 and ordinary words 2/2 in both OFF/ON
modes), direct cue recognition, and original above/side speaker layouts. The
last original wrapped-speaker case aborted inside Apple's Simulator Metal XPC
stack, not an XCTest mismatch. Exported crash attachment SHA-verified ZIP:
12ea8279188de4f0124f8ea7c43023201f47a5e2aad71ab63535fb1192934d69.
Backtrace: MTLSimDriver sendXPCMessageWithReplySync -> Metal command queue ->
VideoToolbox pixel transfer -> TextRecognition -> VNCRImageReaderDetector.
Assertion: an NSString received `bytes`. The same old case passed in the first
focused attempt. Do not suppress it or count the incomplete run as green.
Retry the unchanged five-case job on another hosted VM, same Xcode16.4/iOS18.5,
foreground Vision path and all assertions. Core100 on this source passed in
43866275783. Production GPU/background/decoder settings remain unchanged.

### Unit B repeated Simulator-only crash; provisional unit C

The unchanged retry on job 133346296709 again passed raw Vision name/ordinary
controls, direct cue and above/side layouts, but hit the same MTLSimDriver XPC
assertion in the old wrapped-label case. Its very first cold Vision call also
exceeded the synthetic pipeline fixture's 45-second deadline. Production already
uses an autorelease pool per sampled frame. Test image/request loops now match
that lifetime instead of retaining autoreleased Vision/Metal resources across
many reads. Cold Vision initialization is logged separately before the unchanged
45-second publication assertion; no foreground/GPU/ROI/rate setting is changed.
All five cases are retained. Unit C's dictionary configuration also avoids
setting empty customWords on untouched OFF requests, while explicitly clearing
it on ON-to-OFF rollback. Fresh native B+C verification remains mandatory.

Unit C is provisional until its portable and native tests pass. Added bounded
per-game/general names JSON (protected until first unlock for background access,
backup excluded), manual/pack/auto priority, explicit deletion blocklist, counts,
manual editing and JSON import/export. Only actual accepted speaker evidence
learns: high-confidence colon once; bracket/separate twice on DISTINCT stable
event IDs. Pending IDs are RAM-only. Separate-label confidence is retained
independently from body confidence. Thresholds are persisted in Advanced. No
sentence text is inferred as a name or written as automatic history.

Only active validated exact name->Arabic pack pairs seed the store. Cache versions
change on output-affecting name changes, not count-only updates; translator and
frame reuse invalidate safely without resetting tracker/display clocks. Delayed
old-name results cannot refill the new-version frame cache. Vision dictionaries
update only on change, cap200 and clear on rollback; dictionary-only names do not
silently become known speaker identities when learning/store use is OFF.

The four-form placeholder experiment runs REAL Argos on authored synthetic
fixtures, reports exact form/count/order survival AND comparison of surrounding
words with unprotected output. Changed markers automatically retry unprotected.
No production form is selected yet (`NameProtectionPolicy.form=nil`), so there is
no dead protection switch. Selection/unsupported status follows observed native
results. Default learning/store-output flag remains OFF. Transliteration uses
explicit conventional examples plus documented digraph/vowel approximations and
is editable, not linguistically authoritative. Capture/trace can show the actual
engine input/raw output only with opt-in diagnostics; reuse caches strip them.

Unit C portable run43886083400 passed all110 Swift cases on aaf9d46, plus source,
packaging and converter checks. Native43886089955 stopped at build-for-testing:
SwiftUI property wrappers require one variable per declaration. Split the two
combined @State declarations; no runtime tests ran in that attempt. Also guard
async file imports/edit/export by store/scope identity (including a selected game
literally named general), so a late result cannot apply to a different scope.
The next focused native run retains all six Vision/production B+C methods and
four names methods, including real Argos probes/cache controls and protection
capability reporting. No optional protection form is selected until results.

### Real unit C experiment: reject placeholder protection in production

Run43887703263/job133370203726 compiled the names screen and executed the four
names methods: UI scope/manual/deletion passed, actual Argos cache invalidation
passed, all20 real four-form probes executed, hardware metadata-only assertion
explicitly skipped after absent direct control metadata. Three of20 markers
survived (letters2, brackets1); ZERO surrounding-word controls passed. Examples:
markers survived while `follow` remained English, or an imperative became a
present-tense verb. Underscore/guillemet forms were deleted or rewritten.
Survival alone is demonstrably insufficient. No robust form was found.

Isolate the experiment behind DEBUG, remove its production translator routing
and unavailable flag/setting. Release keeps original Argos input/inference;
names still support speaker identity, editable Arabic labels and Vision words.
This conditional C sub-feature is explicitly unsupported, not presented as
working or enabled merely because a flag is OFF. Research fixtures remain
repeatable in Debug, including malformed-marker fallback controls.

B's foreground Vision dictionary and cue methods passed again, but the repeated
Simulator MTLSimDriver pixel-transfer crash now occurred in dictionary refresh.
Autorelease lifetime matching alone did not resolve it. Test synthetic buffers
were BGRA without IOSurface, whereas actual VideoDecoder input is 420v NV12 +
Metal compatibility + IOSurface (VideoDecoder.swift294-296, unchanged). Match
that actual format using a test-only CPU conversion of the monochrome fixture
into video-range luma/neutral chroma. No production decoder, GPU selection, ROI,
sampling or assertions are changed. Native recheck is required; not a claimed
fix yet. Also preserve legacy suppression of a confident Name: with no body,
while unknown bracket-only narrative and ordinary prefixes stay readable.

Native79374d4 remained queued on Intel for over15minutes, with no other repository
run in progress. Add a manual checkpoint runner choice (Intel/default or Apple
Silicon macos-15), keep Xcode16.4 and every test unchanged, and try ARM capacity.
The full release workflow is unchanged. Remove checkpoint push activation to
avoid an accidental duplicate expensive job; manual tests remain available.
Names typed place/term remain in Vision words but are not added as trusted
PERSON speaker identities. New source still needs Core/native revalidation.

ARM checkpoint43897279214 did not receive a hosted runner: annotation says
"The job was not acquired by Runner of type hosted even after multiple attempts"
and reports ARM capacity constraints. No checkout/build/test step ran. This is
not a native test result. Keep Xcode16.4; retry available Intel capacity. Also
serialize first names-file export under the store lock, preventing an empty
first-export write from racing a concurrent explicit edit. Native experiment
logs now identify ARM64 versus Intel Simulator instead of hardcoding Intel.

### Unit D: explicit corrections (provisional native verification)

The isolated store checkpoint43903003194/job133424306406 passed the full portable
suite, including three new store/RAM tests. Corrections use the existing v1
normalization (including its terminal dot/exclamation normalization), exact wins,
and conflicting normalized targets reject instead of choosing arbitrarily. JSON
validation is atomic and game/general role scoped; only explicit save/import
writes a protected, backup-excluded file. No automatic dialogue persistence.

The next change wires the tested store into a shared correction/reuse/rule
priority helper and the live pipeline, plus direct translator lookup ahead of
pack/model/cache. Independent persisted `corrections` defaults OFF. A bounded20
published-line RAM list clears on Stop, disabling the feature and scope change.
Explicit edits affect future/unpublished work, never replay expired cards or
reset the tracker/TV clocks. Editor/import callbacks retain store identity. A
changed correction/flag invalidates both caches; delayed old-context results are
recomputed only while still unpublished and accepted by the tracker, and old
scope results are discarded. Required native tests cover no-model priority,
actual Argos cache edit/delete/OFF/scope, UI library RAM/persistence, and a real
Vision->FramePipeline correction-before-rule fixture. These are NOT yet passed.

B/C native Intel43902723228 is still queued without a runner at this writing.
No new release or IPA/APK has been published. D production wiring remains
provisional pending build/native/legacy verification; do not move on to E until
its required tests are resolved or the incomplete unit is explicitly isolated.

D sourcecd80f78 passed all114 portable cases in43903911917/job133427512789.
A library-generation token now also rejects callbacks queued before Stop, OFF
or A->B->A scope changes, even if the app has already restarted a session when
the main queue receives them. The token is RAM-only, never a persisted history.
Its native regression fixture exercises late Stop and returning-scope callbacks.

Intel43902723228 was cancelled by a higher-priority stale concurrency request,
NOT by an Intel capacity annotation. The old43894082288 eventually became pending;
its normal cancel then succeeded (earlier409 requests had not been queued yet).
New combined B/C/D native43904258846 oncd80f78 is queued on Intel, same Xcode16.4.
ARM43897279214 remains the confirmed hosted-capacity failure.

Latest D checkpoint43905093088/job133431678474 on60569e5 passed all114 Core
cases plus full source/project/packaging/converter checks. The combined native
request43905189703/job133432031866 on the SAME source is queued with all seven
B/C/D Vision methods, NamesIntegrationTests, CorrectionsIntegrationTests, and
the active-pack correction priority/rollback test. Preceding43904258846 was
explicitly cancelled before acquiring a runner so the newer callback guard and
pack-priority fixture are included; it is not a failed runtime result. Freeze
production changes until this native checkpoint provides build/runtime evidence.
The Arabic status document is provisional and does not advertise a new build.

### User-prioritized independent TV preparation (unit G)

The owner explicitly requested preparing the APK while Apple hosted capacity is
unavailable, then revisiting iOS builds. This overrides the previous unit order
for the independently testable receiver renderer; E/F/H/I are not advertised as
complete. Latest prior native43905189703 ended before any runner/step: hosted
runner not acquired after multiple attempts. No B/C/D native result was obtained.

TV0.6.2-quality.1/code10 builds locally with the original signer. All40 Android
cases pass (31existing+3policy+6nativegraphics). Pinned Robolectric4.13/API28
StaticLayout/Skia runs on Windows; no local emulator or connected ADB device.
Saved synthetic screenshots visually inspected. The published-release Canvas
oracle is exact bf3675e6 source with class identifier references renamed, test
only. Pixel-equivalence all-OFF, old renderer ignoring new optional fields,
rollback, physical alignment, font/color/outline opacity, multiline wrapping,
cue-only duplicate avoidance, aliases/tombstones/clock preservation tested.
Receiver/WSS/pairing/discovery/desktop and duplicate/display-clock algorithms
unchanged; SubtitleState exposes a read-only canonical entry accessor only.

Optional metadata cue/cue_only, speaker.arabic, provenance/basis are rendered
inside bidi isolates; small provenance badge only for pack/correction paths.
No metadata -> original SpeakerText path. A rejected frozen paraphrase retains
its actual old provenance; absent optional fields clear decoration on rollback.
A separate optional arabic_paragraph_direction bool maps to the existing persisted
OFF-by-default iOSflag; AR body RTL, no AR letters LTR, physical alignment fixed.
A new portable Core contract test covers independent rollback/required wire data.
Future IPA native verification remains mandatory. No source/pack/capture data or
keys are bundled into test images/APK. See Arabic TV report for exact APK hash,
original certificate, package/version, limitations and installation steps.
No new GitHub Release, no replacement of old release or physical TV installation.

### Full run43920818047: archive succeeds; runtime green was NOT test execution

Full Intel run onfb76f91 acquired a runner and passed source/115 Core cases,
real RDR2/maintenance validation, project and physical ARM64 archive. IPA artifact
14255356102 verified ZIPdigest2fe0f1e1e4d9f859f498c4b40750fde0b27ee15806ded9639fd2719a14ece5c3;
actual IPA3,024,681bytes SHA2563cdb1dea050a022e73cd3fb477891a459b15908fed07529fbcf0fa0d2c63304a,
dev.gamelingo.ios0.3.0/build8, unsigned/physical ARM64 structure validated locally.
It is NOT approved/published: the whole run failed.

The API marked the native step successful, which initially led to an incorrect
progress claim. Inspection of the actual validation artifact14255437882 (ZIP
SHA2560d5c4b2039fe77c0944357a18ab4d3a48a1316920c7d7541d3f3b1bfd8527f19)
revealed apple-tests.log EMPTY and NO result bundle. Exact job line:
`iOS/Scripts/test.sh: line51: TEST_FILTER_ARGS[@]: unbound variable`.
The full unfiltered route expanded an empty optional array under macOS Bash3.2
nounset and never invoked xcodebuild test. Focused runs used a nonempty array.
Thus B/C/D runtime is STILL unverified; do not claim a pass from step color.

Use an always-nonempty command array and append only explicit validated filters.
Both full/focused native and picker scripts now require a nonempty XCTest
execution summary AND result bundle. Four orchestration regressions run the REAL
shell script with fake SDK tools: unfiltered invocation, optional filter
forwarding/rejection, zero-exit/no-tests rejection, failure through tee/cleanup.
All4 passed locally using Git Bash, separately labeled STUB/orchestration tests;
these do not replace actual Mac tests. Keep Xcode16.4 and all runtime cases.
Move IPA upload after both runtime and actual picker checks, preventing a failed
run from exposing a new IPA artifact as if approved.

Picker build also caught a real test compilation error: waitFinished throws but
testSandboxFolderImportsWithoutSystemPicker had neither throws nor try. Corrected
in0c14b60; no application behavior or assertions removed. Repeat the FULL workflow
on the combined fix. No new Release, no distribution of this failed-run IPA.

### Corrected full attempts blocked by hosted Mac allocation

Portable checkpoint43940573931 on429dc052b418f4471c10da4b9a3cb7c5c2f18733
passed115 Core tests plus source/converter/packaging and4 STUB orchestration cases.
Corrected full Intel43940652518 and ARM43943685073 both failed BEFORE checkout,
with no allocated runner or steps. Latest ARM job133567565916 completed at about
2026-11-16T20:06UTC (17 November00:06 Oman); workflow conclusion failure, job
cancelled. Check annotations explicitly state:
`The job was not acquired by Runner of type hosted even after multiple attempts`
and `Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times.`
No corrected native/picker execution or IPA artifact resulted. Xcode16.4 and all
gates are unchanged. No additional production changes while the required B/C/D
runtime gate remains blocked. E/F/H/I remain unfinished; full batch NOT ready.
Original-key TV APK remains locally ready with40 tests passed, source99da49a.
No Release published, old Release untouched. Manual Arabic build guide added;
use Run workflow on quality branch for fixes, not Re-run jobs on an older SHA.

### Native runtime checkpoint verified on20 November from full run44031605630

The17 November ARM full run on d1ac56d actually executed47 native XCTest cases:
45passed,2 capability skips,0failures. Actual apple-tests.log42,809bytes and
GameLingoTests.xcresult are present in artifact14306256835. Downloaded validation
ZIP125,689,999bytes SHA256d728176130860f3ca23016e9f76d833d11cb2b41b4997dd09f575ab8167c4209.
The2skips are names/capture protection metadata unavailable in both Simulator and
direct Foundation controls; physical file protection remains unverified.
All22 AppleIntegration,3 Corrections,14 Pack cases passed; Names3pass1skip,
Quality3pass1skip. In particular all7 B/C/D Vision/pipeline cases passed using NV12,
including old above/both-sides/wrapped tests. Real model/cache/scope/correction
precedence cases passed. No Metal crash in this ARM run. B/C/D runtime gate is
resolved for this source, subject to final regression of subsequent changes.

Whole workflow still FAILED: picker UI1pass1failure. Actual native picker selected
exe/zip/glpack/rar/7z with delegate-verified names, then XML thumbnail tap at
(70.41,417.92)pt left the provider unchanged. Pre-tap and teardown screenshots
visually confirm the correct XML thumbnail and unchanged Files grid; the sandbox
test passed. This is observed interaction failure, not proof XML cannot import.
Test now tries the visible filename caption once IF provider remains visible,
then still requires exact delegate filename, completed inspection and all12
extensions plus cancellation. No app/importer behavior or assertions removed.
Full rerun required. No IPA uploaded by corrected workflow; no Release published.

### E reversible pack profiles — implemented, native gate pending

Policies3192357:122 Core tests passed44719198477. V2 database121c6d6:
128 passed44719804882. Integrated109ab7f:130 passed44721368186, including all
source/project/converter/packaging checks. No local Windows Swift execution.

New imports validate the ORIGINAL hash/schema/contents before generating a new
managed v2 database. Existing installed v1 stays readable and unchanged until
explicit reimport. Raw v1 columns/keys/flags/usable/targets remain for allOFF.
V2 adds indexed punctuation keys and sparse profiles1markup/2label/3combined;
all derived keys/rows/counts/names/statistics rederived during validation. No
caller SQL, extra schema objects, orphan/duplicate/missing variant or arbitrary
ambiguous result is accepted. SQLite page cap256MiB, bounded cache, cancellation;
external file never changed. Index/matching key v1 unchanged.

Markup controls limited to ~z~/~n~/~s~ and balanced <C> wrappers. Visible inner
text preserved; unknown/unbalanced tokens remain and are unusable when cleaning
is enabled. Numeric brace/printf placeholders retained but excluded in cleaning
profile. An originally unusable row can recover ONLY when known unresolved
markup was its sole blocker (presentation-form conversion annotation allowed),
with all text checks passing. Report before/after/cleaned/excluded + statistical
reversed-order WARNING only, no Arabic reversal. Runtime/selftest use selected
profile's actual usable count/source. AllOFF uses original exact/normalized SQL.

Punctuation tier only in v2 and with packPunctuation flag. Preserve word borders,
interior apostrophes, signed/decimal numbers; strict ambiguity/no tier fallthrough
after ambiguous/unsupported normalized result. Provenance packPunctuationless.
Confirmed source Name: split under packLabels, metadata in flags. HUD/cue/ordinary
prefixes and IDs rejected. Identical EN target label can be removed; AR target
label requires an independent unique exact EN-name/AR-name record in raw data.
Unknown AR prefix is deliberately retained rather than guessed. Quality-only names kept
separate from original manifest.speakerNames. Aligned exact EN-name/AR-name pair
wins; otherwise editable approximate transliteration, explicitly tagged. Persisted
packLabel entries filtered when that flag isOFF, without deleting the store or
losing manual edits. Manual/canonical raw pack decisions/blocklist win.

Activate now is explicit after successful import. Corrections and cached outputs
follow actual selected/active game, pack activation, all quality flags, names and
corrections versions. Frame reuse also invalidates for advanced setting changes;
delayed unpublished outputs cannot refill a new context. Tracker/duplicate logic,
TV clocks and transport unchanged. No new dialogue history/logging.

New native integration cases cover managed v2 import/external bytes/flag rollback/
actual lookup provenance/name alignment/restart, explicit activation/legacy names,
real Argos cache game/flag/names isolation and stale correction scope rejection.
Real RDR2 CLI now compiles actual shared Core policies, upgrades in ignored staging,
validates v2, compares allOFF on independent expected old samples, measures time/
size and asserts raw DB hash unchanged; only aggregate counts/timings exported.
These new native/real-data cases have NOT run yet. F/H/I remain unfinished.
ARM44718640360 failed before runner allocation; Intel44721577664 on109ab7f acquired
a runner and is current full validation. Keep Xcode16.4/all gates. No Release.

Intel44721577664 then FAILED compiling Core on Xcode16.4: inferred local values
from `variants.first{...}?.1 ?? row.original` remained Optional under its Swift
version, despite130 passing on Ubuntu's newer compiler. Use an explicit typed
selection function instead. No tests/archive/native execution in this attempt.
Also added strict raw aligned-name lookup during profile derivation/validation:
known AR prefixes can be safely removed; unknown ones stay. New Core regression
covers matching ambiguity after split, raw rollback and exact name evidence.
Native import fixture now exercises aligned AR prefix (not only English prefix).

Full44722281933 onbb02183 passed Xcode16.4 Core and actual RDR2 v2 validation,
native dependency preparation, tracker benchmark and physical archive; native/
picker tests still running. Observed live DOM metrics (get final artifact later):
228174records/209459raw usable;1102 allOFF-equivalent independently expected
samples (1000matches/102rejections); upgrade82527.57ms, v2validation102451.65ms,
original validation14068.67ms; database174120960bytes; cleaned32680/excluded13,
markup usable219624; possible-visual-order-warning false. These timings are NOT
phone performance. They expose a real problem: cumulative work exceeds the
importer's existing120second control on this test host. Do NOT publish this as a
ready large-pack import or increase the timeout to hide it.

Optimize unchanged rows: avoid regex/JSON/normalization/content checks repeated
for every profile when already-validated raw text has no relevant marker; decode
flags only on demand; reuse static warning dictionaries. Targeted cleanup now
preserves ordinary whitespace unless a SUPPORTED token actually changes text,
preventing unnecessary sparse copies (the old measured count includes whitespace
rewrites). New regression checks zero extra variants for ordinary spaced lines.
Raw source validation, strict derived validation, ambiguity checks/page caps/
cancellation/deadlines remain. Re-measure on same Intel environment before gate.

#### Current E verification and corrected live-status interpretation

Optimizations489bfef then conservative recovery guardc938ad3 passed all132 portable
tests in44725040332 (previous44724707140 also succeeded). Recovery now requires
ACTUAL supported token removal and no remaining delimiter that could represent an
unknown marker; removing only a label/ordinary whitespace cannot unblock old data.

Run44722281933 onbb02183 was explicitly cancelled to validate the optimized source
after observing the import budget regression. It is NOT a completed native pass.
Its final validation artifact14623294273 ZIP82876bytes digest
2e2d8ee2fbb93cbff3c54523ddac02ee56b062ba2afeecd2aecd8f793e9d7cc3
was downloaded/verified. Release and Debug test builds SUCCEEDED. Contrary to the
stale live browser view (which showed an old ClangStatCache line), actual
apple-tests.log29908bytes shows12 Apple cases PASSED from11:12:47UTC, then the B
cue pipeline case STARTED before cancellation. No E Pack cases/picker ran and no
full summary. Partial xcresult Staging is not a completed result. A user progress
claim that there were no case results was explicitly corrected. Never infer
zero execution from missing/stale live DOM chunks.

Current full ARM44726181204/job136254309789 on c938ad3 acquired a runner, passed
Mac Core132/real RDR2/native prepare/maintenance/archive; actual native/picker
verification pending. Completed RDR2 step live DOM reports:228174rows,
209459raw usable;1102 allOFF equivalence samples (1000matches102rejections),
raw validation8640.26ms, upgrade8236.06ms, v2validation15458.39ms; database
112472064bytes,5610cleaned13excluded,209617markup-usable, warning false.
Final artifact still required for durable evidence. Approx32.3sec cumulative
core work is below the existing120sec importer control on this ARM Mac; copy/
hash/provider work and physical iPhone timing are separate. Old timings were
Intel, new ARM: do NOT claim a same-host speedup ratio. Database size/derived-row
reduction and targeted whitespace regression are environment-independent.
No new Release, no approved current IPA; F/H/I still unfinished.

#### Durable c938 native result and current F investigation (20 November)

Downloaded artifact14626190519 for44726181204: ZIP123678211bytes,
SHA256541791dc6dabaab7ebd2b2b9a9085fed151074f5f3e6de50166d2bb3dea19285.
Actual apple-tests.log:50executed,48passed,2capability skips,0failures.
All three E integration cases passed. Native tests alone do not make this run
green: picker UI executed2cases, sandbox passed, real-provider selection failed
at XML after5verified extensions, including the caption fallback. Archive step
passed but IPA upload correctly did not run. No new Release.

Downloaded aggregate RDR2 report confirms the timings/counts above. No private
source dialogue was extracted into tracked files or published. Current Files
investigation uses actual provider List rows and the same exact delegate filename,
12extension, cancel and sandbox assertions. Only the system-provider test language
is English for Vision OCR; Arabic product strings/render fixtures are separate.
Focused workflow can opt into picker checks, and cannot publish release assets.

F pure punctuation/command policies passed138 portable cases at610ed53 (run
44730942937). Runtime wiring repairs model output only, never explicit corrections,
pack text or command-map values. Quoted and mixed-Latin bracket text is preserved;
unbalanced state is content-free. Raw inference is retained only for opt-in trace/
capture, before repair. Cache invalidates on either independent flag change. Added
native real-model rollback/cache/trace tests and synthetic sentence-splitting
research, not a production splitter. No F switches are visible until verified.

F line-cap initial8f02cda checkpoint44731313016 correctly failed: anchored grouping
only considers immediate neighbours of the first body line, so changing prefix3
to5 alone does not admit a five-line body.498e056 adds bounded connected-neighbour
growth only with lineLimits ON; OFF retains the original filter verbatim. HUD
counters are excluded, total body height bounded. New unanchored5/6-line bodies
need compact layout, an actual sentence anchor, and repeated OCR evidence; short
line majority alone is never a menu veto. Advanced caps persisted (3...5/4...6),
not yet exposed.143-case checkpoint44731562043 and focused native44731368649 are
pending outcomes; the latter source8f02cda predates the anchored grouping correction
and does not certify that correction. Typewriter/H/final I remain unfinished.

#### Later 20 November verification (before final release gate)

44731368649/job136271683875 (8f02cda, Intel) actually ran7native Quality cases:
6passed,1file-protection capability skip,0failures. Real Argos punctuation/raw
trace/cache/one-flag rollback and explicit-correction authority passed. Native
sentence research on3multi-sentence fixtures found no clear meaning improvement:
whole/split times512/944ms,497/651ms,580/859ms (single measurements on Simulator,
not a phone benchmark). Three single-sentence controls retained the whole-input
path, including Mr./Dr./St., ellipsis and quotes. No production splitter/flag was
added. A repeatable Windows CPU int8 experiment on the exact hash-verified local
Argos package reached a similar semantic conclusion, separately from iOS proof;
tools/quality/compare_argos_sentences.py records3repeat medians using synthetic
authored inputs. The Windows application's files/model were never changed.

The same focused workflow FAILED picker UI. Its English provider view menu did
not open using the previous Arabic leading-edge coordinate. Later XCTest itself
reported XPCReplyCheck/NSCFString bytes; video attachment contains only a pending-
attachment error, not usable video, so do not claim a visual root-cause proof.
Sandbox import passed. Artifact14627432445,64812346bytes, SHA256
09caeb410244d7178f11780b47f7751331284bd15e571d18738e4972cd424f16 was downloaded/
verified.6071302 uses English trailing-edge More and OCR-found Cancel. No product
import filtering changed. Its initial ARM run44762618645 was cancelled without
executing steps. Picker still needs an actually passing rerun, not assumptions.

44764080712/job136383937153 (90fd566, Intel) PASSED8native cases:7passed1capability
skip. Actual Apple Translation LanguageAvailability API returned unsupported for
en-ar on iOS18.5/build22F77 in0.339s. No session/download/engine option was added.
This does NOT establish availability on the user's current physical iOS release.
API: https://developer.apple.com/documentation/translation/languageavailability/status(from:to:)

All-off cross-Release gate44763237497 on d5bebc7 PASSED151Core cases and an actual
separately compiled bf3675e Release/current post-OCR comparison.10synthetic
streams/24canonical messages matched exactly (stable-ID namespace normalized;
required text, geometry, lifecycle fields preserved). Same Ubuntu CI host2900
timed observations: baseline median0.534ms/p951.390ms; current OFF0.542/1.390ms;
representative quality enabled0.680/5.061ms. This excludes Vision, SQLite lookup,
Argos, asynchronous worker, network/TV/physical hardware. It is NOT whole-system
latency. The enabled workload intentionally emitted25messages (including cue).

44764232354 on c97fe0c PASSED157Core cases + same-output gate. Per-fixture timing
localized the enabled tail to the6-line unanchored region (fixture6median7.451ms,
p957.622ms on that host); overall baseline0.779/1.922ms, OFF0.766/1.903ms,
enabled1.034/6.977ms. af43122 reuses name/word classification only within the
same at-most8-line OCR observation when lineLimits is ON, never across frames.
79b2bd9 also accepts short multi-line dialogue with multiple punctuation/pronoun
anchors plus compact layout and repeated observation. Short-line majority alone
is not a menu veto. Menus/HUD exclusions and OFF semantics remain unchanged.
Re-measure optimized code before claiming the regression resolved.

F punctuationRepair/commandPunctuation/lineLimits controls became visible at
128d6e4 after portable/native component checks; defaults remain OFF. Typewriter
remains hidden pending native verification. The research settling policy was
promoted to Core atbc60e96 after its7policy tests, followed by5publication tests,
bounded selected-game ID hints (max256, no dialogue history), and a terminal-only
punctuation change regression. f88651e integrates EARLY translation with delayed
publication in FramePipeline, preserves the existing tracker/worker/TV clocks,
flushes an already-ready interrupted result before source identity advances,
and uses a fresh offered frame through the unchanged pacer for confirmation.
Bitmap signatures never count as OCR reads. Held state is one RAM closure and
clears on Stop/pause/interruption/disconnect/manual reading; context edits retry
only a still-current unpublished result. Unselected games learn for the session;
only selected validated game IDs are remembered. Automatic detection is based on
multiple strict monotonic prefix extensions with stable region/speaker and high
confidence; jitter/punctuation-only/unrelated lines are negative evidence.
Whole-input Argos remains unchanged. Three new native Vision/NV12+rule-worker
tests cover2actual reads/OFF first-read, interrupted short line ordering, and Stop/
restart. These are NOT real-model or physical-device claims.

f88651e portable checkpoint44765445844 PASSED; full native/picker sourcef88651e
runs44765544702(ARM) and44765782205(Intel) are pending results. They do not include
the later per-read optimization/short-line anchor refinement. The final full IPA
workflow, exact versions/identities, one-flag matrix, and physical acceptance are
still required. No new IPA uploaded or Release published.

#### Current source / blockers after 16:06 UTC

Run44765782205/job136389903722 onf88651e completed. Xcode16.4 Debug test build
SUCCEEDED; Simulator data migration was slow but eventually completed, not an app
failure. Actual3new Vision/NV12+rule-worker typewriter cases all PASSED: interrupted
short-line ordering11.484s, Stop/restart12.719s,2real OCR reads/OFF21.091s. Whole
focused suite11executed,10passed,1protection metadata skip,0native failures.
These wall times include generated Vision fixtures/host overhead, NOT subtitle
latency or physical-phone timing. Picker step failed again: neither leading nor
trailing guessed header edge exposed List in OCR, then screenshot attachment XPC
reportedNSCFString bytes. Do NOT assert the menu's actual position without an
independent screen. Artifact14646444040 digest
027757249f3ad465949b761d37c7f2a818ecdca934f2c5c33491f81c3b20c924,
54119390bytes, contains durable evidence; not yet downloaded locally.

44766435730 on79b2bd9 passed159Core cases and cross-Release comparison. Same-host
median/p95ms: Release0.409/1.077, currentOFF0.429/1.128, enabled0.535/1.907.
Six-line enabled fixture median2.145/p952.280ms. OFF canonical24messages unchanged,
enabled canonical25messages unchanged from earlier enabled fixtures. The earlier
c97 host was different: do NOT publish a cross-host speedup percentage. Current
overhead is lightweight and the repeated-classification source was investigated.

827f053 adds the same TypewriterPublication policy to QualityReplay with a
synchronous early stub/held result, actual observation filtering, optional game
hint, no EOF/hashed-frame fake confirmation.4new tests cover a publication record
not counting as a read, interrupted/terminal order, unknown/OFF/zero legacy output,
and3s continuous-growth deadline.44768928821/job136401033614 PASSED163Core cases
and unchanged approved-Release equivalence. Actual async timing still belongs to
native Frame tests, not this replay. Native tests expanded afterf88651e to cover
one-flag OFF with other flags ON,zero duration, and editing an explicit correction
while a result is held. The added correction case remains unexecuted so far.

5b5edc8 prepares iOS0.3.1 build9 and exposes typewriter (OFF) with Advanced window
3...20(default5) and settle0...3seconds(default3). All other quality defaults remain
OFF. Game hints max256 selected IDs; reset clears them. Names retry scopes now use
scopeKey including general/game roles; nonfinite saved settling duration defaults
to3. Both 5b5edc8/44770458040 and bb6300e/44770965398 portable checkpoints PASSED.

bb6300e adds CI-only independent `simctl io screenshot` captures on diagnostic
markers to test-picker-ui.sh (bounded24screens/15min, cleaned background watcher).
This replaces failing in-test screenshot attachments for diagnostic stages but
does NOT skip any selection, exact delegate filename, extension, cancel or sandbox
assertion. Current focused run44771052654 onbb6300e,Intel, runs only the existing
GameSwitch smoke case plus actual picker UI to obtain real provider images. Its
uploaded logs should contain picker-system-1.png(beforemenu),-2.png(aftermenu),etc.
Inspect those images BEFORE changing more coordinates/filtering/product code.
No new IPA artifact/Release. Full0.3.1 build9 workflow still required after picker
fix, including the latest native correction/zero/all-other-flags tests and all
old integration cases. APK remains the already verified original-key0.6.2-quality.1.


#### 16:59 UTC: actual focused result, no new IPA

Run44775318198 at556e2ef executed12 native tests:10 passed,1 capability
skip,1 failure. The held-correction case timed out waiting45s for its first
OCR metric; this does not establish a production correction failure. The
expanded other-flags-on / zero-duration first-read cases, interrupted ordering,
Stop/restart, actual Argos punctuation/cache/rollback and Apple availability
all passed. Picker investigation was skipped because the preceding native
step failed. No IPA/release certification is inferred.

At1c22eef, the held-correction test verifies and initializes the exact native
Vision image before timing the pipeline observation, matching the two-read
test. Focused picker investigation now runs even after a native failure (unless
cancelled); the job remains failed and the full release gate is unchanged.
Run44778642657 is the pending focused native+picker retry.

APK0.6.2-quality.1 was independently reverified locally with apksigner, aapt,
DEX test-class absence and empty runtime-source diff since99da49ac: package
dev.gamelingo.tv/code10,1511120 bytes, SHA-256
e3605dd8bf1177940cee202a29b15179a07c2b4d8b61c51b0a153938133e1520,
original signer48cf8a45a37f4e5c338f98fa7d5135c7cdbaf59d50b39b8bf591a79622a28e38.
No unchanged APK rebuild or physical install was performed.

Current1c22eef portable checkpoint44778614096 passed all163 XCTest cases
(the final Swift Testing0 line is not that suite), source/build orchestration
and converter checks. Same-host optimized actual-Core benchmark: baseline
median0.820/p952.015ms; currentOFF0.819/1.968; enabled0.974/3.476. OFF
24 canonical messages equal baseline; same exclusions and no cross-host
performance comparison apply.


#### 17:22 UTC: crash report corrects the earlier screenshot-RPC hypothesis

Run44778642657 at1c22eef: all4 typewriter native cases passed, including
held correction replacement, zero-duration and one-flag-OFF/all-others-ON.
Ten native cases passed, one protection-capability skip, one crash in the
research case. Restarted-suite4/4 totals are NOT the whole-run result.
Actual picker More/List controls worked and EXE's exact delegate filename
was verified; the next selection crashed. Sandbox import passed. No IPA.

Artifact14651268969:142465505 bytes, SHA-256
5fe257e2b7df34caf9d4969c2f03454c77c5838ad5ac93e2c6d79f58163dccdb.
Downloaded, digest verified, independent provider PNG3 inspected (actual List
command), native exported crash9DA745B9-B298-46B3-8D88-AFA2837E8319.ips
inspected. The native crashing thread is MTLSimDriver newCommandQueue through
VideoToolbox pixel transfer and TextRecognition; another thread is inside
VisionDialogueOCR/FramePipeline.sample from a prior test, while main is loading
Argos. Neither Argos nor JSON attachment serialization caused this crash.
The same XPCReplyCheck string alone does NOT prove a screenshot RPC defect;
that earlier hypothesis is superseded. The picker lacks an exported IPS, so
its identical error during screenshot OCR is not independently stack-proven.

At180478e, Stop accepts an optional OCR-queue-drain completion; existing
callers retain identical asynchronous scheduling/reset. Native fixture cleanup
awaits that completion to prevent prior Vision work overlapping later cases.
The Stop/restart behavior test retains its initial ordinary Stop, so cleanup
does not substitute a disconnect/reset for the behavior being asserted.
Picker-only control OCR usesCPUOnly=true; production foreground Vision, decode,
sampling/ROI and release assertions are unchanged. No JSON evidence removed.

Focused Intel44782637839 and full ARM6444782644434 dispatched on the same
source. Xcode16.4/all full release gates remain; no artifact upload/publish
unless the full run passes. ARM64 allocation is not assumed.


## النتيجة النهائية — نُشرت معاينة الجودة 1 في 21 نوفمبر 2026

- الريليز الجديد: [ios-v0.3.1-preview.1](https://github.com/Aljjulanda/GameLingo/releases/tag/ios-v0.3.1-preview.1)، منشور كمعاينة؛ لم يُعدّل ريليز الرجوع السابق.
- المصدر `69b3e188f0fe410edfd3923c0dc57e8b702ac718` على `codex/quality-fixes-1`؛ [التشغيل الناجح 44816815978](https://github.com/Aljjulanda/GameLingo/actions/runs/44816815978)، Intel/Xcode 16.4/profile `quality-preview-1`.
- نجحت بوابات المعاينة: 163 Core، تكافؤ 24 رسالة/10 streams، RDR2/SQLite الحقيقي، الأرشيف، و42 حالة أصلية: 40 نجاحًا وتجاوزا بيانات حماية الملفات غير المتاحة في المحاكي. لا فشل أو إعادة محاولة داخل تشغيل القبول النهائي.
- [IPA 0.3.1 (9)](https://github.com/Aljjulanda/GameLingo/releases/download/ios-v0.3.1-preview.1/GameLingo-unsigned.ipa)، `dev.gamelingo.ios`، ARM64 iPhone، غير موقّعة، 3081287 بايت؛ SHA-256 `ea458fcd0346e9b4e4844b4dd7ff2dcb1be6423e932cebdea2fd3a6c8c1ba3a6`. فُحص غياب التوقيع وprovisioning وxctest ونموذج الاختبار. التوقيع الخارجي للمستخدم.
- [APK 0.6.2-quality.1 (10)](https://github.com/Aljjulanda/GameLingo/releases/download/ios-v0.3.1-preview.1/GameLingo-TV-0.6.2-quality.1.apk)، `dev.gamelingo.tv`، 1511120 بايت؛ SHA-256 `e3605dd8bf1177940cee202a29b15179a07c2b4d8b61c51b0a153938133e1520`. أُعيد استخدام نسخة 40 اختبارًا المعتمدة دون بناء، وفُحص توقيع المفتاح الأصلي فعليًا.
- [التقرير العربي النهائي](https://github.com/Aljjulanda/GameLingo/releases/download/ios-v0.3.1-preview.1/GameLingo-Quality-Report-AR.md) و[البصمات](https://github.com/Aljjulanda/GameLingo/releases/download/ios-v0.3.1-preview.1/SHA256SUMS.txt). نُزّلت الأصول المرفوعة الأربعة وتطابقت بصماتها، وتحقق وسم الريليز من commit البناء نفسه.
- النص المتدرج مستبعد من ربط الإنتاج ومؤجل؛ أبحاثه واختباراته محفوظة. Vision/FramePipeline المصورة وFiles التفاعلية وحماية الملفات العتادية مؤجلة للفحص الميداني. لم تُختبر الدفعة على iPhone/TCL/PS5 الفعلي. جميع ميزات الجودة الباقية OFF افتراضيًا. ليست هذه شهادة اكتمال A–I.
- أصول النشر أربعة محددة فقط؛ لا بيانات RDR2 خاصة أو مفاتيح أو تسجيلات لعب أو نموذج تجريبي أو أدلة محاولة فاشلة ضمنها. لا عمل نشر متبقٍ لهذه المعاينة.
- أدلة التشغيل محليًا: `iOS/.build/quality-preview-44816815978/`؛ بيان النشر النهائي `iOS/.build/quality-delivery/published-quality-release.json`. أداة النشر المحلية تستخدم تحقق Windows الأصلي لسلسلة شهادات خادم الرفع؛ لم يُعطّل TLS أو التحقق من المضيف ولم يتغير TLS التطبيق.

---

## السجل السابق المحفوظ للمراجعة التاريخية

