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
