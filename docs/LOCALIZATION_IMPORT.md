# iPhone localization import

Selection and conversion are different operations. The native copy-mode picker has no extension whitelist. Extensionless files and files called EXE, ZIP, GLPACK, RAR, 7Z, XML, JSON, CSV, TXT, PO, LOCRES, GXT, GXT2, PAK, BUNDLE, ASSETS, DAT, BIN, BYTES or anything else may be submitted for inspection. A provider can still impose its own restrictions. Directory packages are not regular files and are not converted by this importer.

The fallback is Files → long-press → Copy → On My iPhone → GameLingo → Paste, then GameLingo → Translation → Game Translation Library → Refresh Folder Files → tap the filename. This imports a regular sandbox file without asking a document provider to classify it. Installed packs and model files live separately in Application Support; file sharing exposes Documents only. Do not delete the app to install a new IPA.

## Supported content schemas

Filename extensions are not used to determine any of these schemas. Text supports strict UTF-8 (optional BOM) and UTF-16 LE/BE with a BOM. Limits apply before conversion. Generic text, Arabic-only strings and identifier-to-Arabic maps do not imply an English source mapping.

### JSON

```json
{
  "game_id": "example-game",
  "game_title": "Example Game",
  "attribution": "Original translator",
  "license": "Original licensing terms",
  "entries": [
    {"id": "scene-1", "source": "Move now.", "target": "تحرك الآن.", "category": "dialogue"}
  ]
}
```

An array of entry objects is also accepted. Aliases are `en`/`ar`, `english`/`arabic`, or `msgid`/`msgstr`. Optional `category` is dialogue/menu/document/general. Parallel `en` and `ar` dictionaries are joined by identical IDs. Unmatched IDs are excluded. A `translations` string dictionary uses English keys only when `source_language: en` and `target_language: ar` are explicitly supplied. Plain identifier-keyed dictionaries require the original English source or the external converter.

Metadata keys: game_id, game_title, pack_version, attribution, author, copyright, permission, license. Attribution fields and licensing fields are combined without silently dropping one. Oversized metadata is rejected, never silently truncated into a misleading license. Missing licensing information is explicitly marked unverified. Without a game_id, a content-derived local ID prevents accidental replacement of another game. A changed raw file without a declared game_id creates a separate entry.

### XML

```xml
<localization game_id="example-game" game_title="Example Game"
              attribution="Original translator" license="Original terms">
  <entry id="scene-1"><source>Move now.</source><target>تحرك الآن.</target></entry>
</localization>
```

`string` elements with `name` instead of `entry`/`id`, en/ar child fields and CDATA are also supported. Source/target fields must be direct children. Nested markup, DTD/external entities and duplicate fields are rejected. Root metadata attributes use the JSON metadata keys.

### CSV / TSV / structured TXT

```csv
id,source,target
scene-1,Move now.,تحرك الآن.
```

Explicit source/target, en/ar or english/arabic headers are required. Tab and semicolon delimiters are also supported. Quoted delimiters, doubled quotes, CRLF and embedded newlines are parsed. Duplicate headers, ragged rows or unterminated quotes are rejected. A TXT containing this table is accepted based on its contents; free-form TXT does not invent mappings.

### PO

```po
msgctxt "scene-1"
msgid "Move now."
msgstr "تحرك الآن."
```

Multiline quoted strings, headers and copyright/license/translator/author comments are retained. Fuzzy, obsolete and plural records are not converted to singular dialogue. C-style escapes that are not valid JSON string escapes require an external converter. Context-dependent translations of the same normalized source are excluded when their targets conflict.

### GLPACK / ZIP

GLPACK reuses the existing version 1 closed ZIP/SQLite/checksum format. All original validators and atomic installation remain active. The filename may be changed without changing detection.

A general ZIP may contain one convertible localization file (with any filename) or one GLPACK. Paths are validated first; extracted files receive generated names, never archive-supplied filesystem paths. Several usable independent candidates require external merging to avoid mixing games. No more than two ZIP layers are processed. Each general entry is at most 16 MiB; a nested GLPACK must also fit that entry limit. The top-level GLPACK retains the original larger database allowance.

### Recognized but not converted on iPhone

- PE/EXE: MZ and PE signature/location inspection only. No executable loading, code/script execution or installer resource extraction. The external GameLingo converter supports static extraction of the previously supplied Arabic-RDR2.exe; the iPhone importer does not include dnfile or a CLR runtime.
- RAR/7Z/UnityFS: signature detection and external-conversion guidance; no bundled extractor.
- TKEY/GXT-like data: recognition only; original English ID mappings and game-specific conversion may be required.
- LOCRES/PAK/ASSETS/DAT/BIN/BYTES: selection is allowed; content determines detection. Unknown binary formats are not parsed merely because their extension is familiar.

## Architecture and bounds

`LocalizationFilePicker` → scoped/coordinated sandbox copy → `LocalizationFormatDetector` → `LocalizationFormatAdapter` registry → `EnglishArabicMatcher` → `LocalizationPackBuilder` → existing `TranslationPackStore`/`PackDatabase` validation and atomic installation. Add an adapter to the registry and add a detector rule to support another format; the picker does not need an extension list.

Input: 128 MiB. Raw text: 16 MiB and 50,000 records. JSON/XML depth: 32; structural/node limits apply. CSV: 32 columns, bounded fields. ZIP: 64 entries, 64 MiB general expansion, 100:1 ratio, generated paths, CRC verification, no symlinks/traversal/duplicate paths. GLPACK: original closed schema/checksums and 256 MiB database bound. Conversion deadline: 120 seconds. Cooperative cancellation and SQLite interruption precede atomic commit. If commit has already completed, completion is reported truthfully as success.

Only explicit English/Arabic pairs are used. Invalid/missing/non-Arabic targets, presentation-form Arabic, duplicate rows and ambiguous normalized targets are excluded. Usable/rejected counts reflect the prepared data. GLPACK declared counts are displayed only after successful validation. No missing game text is invented or sent to a cloud translator.

Import/conversion is disabled during live translation, and starting a translation session while import is busy is prevented. Heavy work stays on utility queues; UI progress reports actual copy bytes and inserted entries. Other phases are indeterminate. Temporary data is removed before the result is delivered.

## Validation boundaries

Core parser/matcher/security tests run through Swift Package Manager. Apple integration tests cover actual SQLite/GLPACK creation, installation, failure preservation, cancellation and limits. XCUITest opens the native picker, taps twelve synthetic file types (including an extensionless file), checks that each selected filename reaches inspection, cancels selection and imports from the app inbox. Screenshots/hierarchies are exported as CI evidence.

The existing CI uses an iOS 18.5 simulator. A physical iPhone, iCloud account and third-party provider cannot be certified by these tests. Physical acceptance requires tapping EXE, ZIP, GLPACK and an unknown extension on the target iPhone and verifying the distinction between inspection and actual conversion.
