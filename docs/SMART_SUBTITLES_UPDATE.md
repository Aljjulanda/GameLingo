# Smart subtitle update (Windows 0.3.1 / TV 0.3.0)

## Baseline and root cause

The baseline is Git tag baseline-before-smart-subtitles and work/baseline-before-smart.bundle. Existing settings were backed up before edits. No model, pairing identity, account registration or UrTV component was replaced.

The previous pipeline cleared the TV when OCR changed or became empty and renewed the single active line every two seconds. The receiver rendered into one TextView and scheduled one hide Runnable. Together these could erase readable Arabic early, replace the previous sentence on every new result and perpetually restart the same timer.

The updated pipeline emits unique dialogue IDs and no source-disappearance clear. Prefix extensions reuse the dialogue ID. Duplicate recognitions generate no additional entry. Session stop and network loss still clear. The receiver rejects stale transport sequences and expired deliveries. Display retention starts on the TV monotonic clock when a new entry is inserted. Corrections retain that entry's original deadline.

## TV renderer

One full-output, non-touchable and non-focusable TYPE_APPLICATION_OVERLAY window holds a Canvas. StaticLayout handles shaped Arabic, wrapping and measured text heights. Each active entry owns its expiry. Capacity is 1–3 (default 3), with oldest-first eviction before drawing. Actual entry heights also bound the stack. The newest block's bottom-center remains anchored independently of the previous blocks. Previous blocks expand upward. Oversize newest text is reported through the TV status; a configured unwrapped line is clipped with an explicit warning.

The default anchor is (outputWidth/2, 0.92*outputHeight). x and y are signed physical-pixel offsets. Up subtracts Y and left subtracts X. LayoutPolicy clamps the resulting position inside safe boundaries. Font size is Android sp; all position, padding, spacing, outline and border settings are physical pixels. The TV reports output dimensions in settings_ack.

Each visible entry holds only id, text, appearance-time and expiry. Expired and evicted entries are removed. There is no replay, archive or history UI. Existing hashed-key translation memory remains an inference cache.

## Configuration and protocol

Protocol v1 remains in use, extended with settings_sync, settings_ack, subtitle_preview_show and subtitle_preview_hide. Each control carries the normal session and sequence and a validated settings object with a millisecond revision. Windows persists the primary settings; Android persists the latest accepted settings. Older revisions are rejected. Settings sync before subtitle delivery on reconnect.

The TV preview has a local eight-second lifetime and never deletes active entries. Real dialogue immediately dismisses a preview. The Windows preview is scaled and approximate for system-font differences. The real-TV preview is authoritative for font fallback, density and exact coordinates.

## Resource management

The existing Windows Graphics Capture, Windows OCR, CTranslate2 and SentencePiece pipeline is retained. One sampled owned image, one OCR worker, one inference job and one replacement candidate remain bounded. The in-memory translation LRU remains bounded. Extra per-frame network rendering renewals were removed.

A small high-contrast stroke mask in the configured subtitle region triggers OCR on likely text changes; a periodic verification guards against false negatives. Background changes do not automatically imply text changes. Modes cap OCR at 2/4/8 samples per second. The optional sustained-load controller steps down after five high-load readings, restores after ten low-load readings, and uses an eight-second cooldown.

The performance page samples system and process CPU/RSS once per second and graphs up to 90 system-CPU samples. CPU percentages are normalized across logical cores. Stage timings, attempts, skipped attempts, cache counts and bounded job depth are separate from process measurements. Unsupported GPU utilization is labelled unavailable.

## Build

Use the existing BUILD.md commands and desktop/GameLingo.spec. Android uses the same project debug signing identity for local updates. Third-party libraries and inference weights are unchanged. New Windows pages are appearance.py and performance.py; the TV model and layout policy are independent Kotlin units.

## Verification limits

Controlled generated-window fixtures are separate from physical game tests. A before/after process report is saved alongside the test report. Short controlled runs do not establish multi-hour memory stability or universal OCR recall across game fonts. Hardware decoding and GPU inference are not silently enabled.

