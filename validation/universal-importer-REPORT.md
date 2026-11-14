# Universal localization importer — development report

Baseline: accepted real-device 0.2.0 remains at `stable/real-device-0.2.0` / `9ffe9814e2be2741a9782c84c08e4c5ff6b62872`. `main` remains `22139da223b92b17cb8e6b5b7b64e3f70c2530cc`. Work starts from preview 2 documentation commit `b9a0a5c` on the dedicated `codex/universal-file-importer` branch. Before changes, source validation (44 protected platform files), 17 converter tests and four packaging tests passed locally. Baseline Apple run 43619694040 passed 67 Swift core and 23 Apple integration tests.

## Picker diagnosis and remedy

The user confirmed installing build 7 and using the game library's import button, yet selection remained disabled. Build 7's UTI/conformance tests did not exercise a displayed document picker and therefore did not establish physical selection. Source inspection found two SwiftUI file-importer presentations in the same navigation flow (parent Argos picker and child game library picker). Whether presentation inheritance or a provider/OS issue caused the exact physical failure remains unconfirmed; the iPhone picker cannot be inspected remotely here.

Build 8 removes the game library's SwiftUI importer and presents its own `UIDocumentPickerViewController`, with `public.item`, copy import mode, a request to show extensions and a dedicated delegate. No filename-extension whitelist is applied before inspection. Existing Argos model import is unchanged. An app Documents inbox, visible under On My iPhone → GameLingo, also permits importing a sandbox copy without any system picker/UTI filter. Enumeration accepts regular files of every extension, rejects symlinks, skips subdirectories and limits directory size. The UI displays the actual installed build number.

Apple's [document picker copy initializer](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(foropeningcontenttypes:ascopy:)) provides the system-provider import UI. A provider can restrict its own availability or download behavior; GameLingo cannot override provider policy. iCloud and third-party providers, and arbitrary selection on a physical iPhone, require physical testing. Simulator XCUITest explicitly selects twelve synthetic fixture types (including an extensionless file) and exercises cancellation and inbox import; passing an API/UTI test alone is insufficient.

## Detection, parsing and conversion

- Signatures/structure: GLPACK (closed three-entry ZIP structure), ZIP, RAR, 7Z, PE/EXE, UnityFS, TKEY/GXT-like resources; text detection for JSON, XML, CSV/TSV, PO. Empty, malformed, unknown binary and unsupported inputs have distinct outcomes.
- JSON: arrays or `entries` of `source`/`target` (`en`/`ar`, `english`/`arabic` also accepted); parallel `en`/`ar` dictionaries joined by identical IDs. A flat `translations` English→Arabic dictionary requires explicit source/target language metadata. Identifier→Arabic dictionaries alone do not invent original English.
- XML: `entry` or `string` elements with direct source/target or en/ar child fields, optional ID/name and root metadata. CDATA and UTF-8/UTF-16 BOM are supported. DTD/entities, duplicate fields and nested text markup are refused.
- CSV/TSV: explicit source/target or en/ar headers; comma, tab or semicolon separators; RFC-style quotes, escaped quotes and embedded newlines. TXT with those table contents is detected from contents. Unstructured TXT is not fabricated into translations.
- PO: msgid/msgstr, multiline strings, contexts and attribution/header information. Fuzzy/plural entries are excluded; no plural-to-single translation is invented.
- ZIP: bounded extraction to generated sandbox paths, one regular payload file (directory entries are allowed), depth at most two ZIP layers. Multi-file archives require the external converter to preserve sidecar licensing/source data and avoid mixing games. No RAR/7Z/Unity extractor is bundled.
- PE: static MZ/PE signature/header-location inspection only. No Windows execution, shell/script execution, installer loading or executable resource extraction on iOS. In particular Arabic-RDR2.exe still requires the existing external static converter, whose dnfile/gzip adapter supports that installer. Selecting EXE is not successful conversion.

The matcher validates supplied English/Arabic pairs, excludes presentation-form Arabic, conflicting normalized translations and duplicates. Raw conversion creates the existing SQLite schema, manifest/checksums and GLPACK, then invokes the existing library validator and atomic installer. Existing metadata fields (attribution/author/copyright/permission/license) are preserved within format limits. Missing metadata is explicitly marked unknown. Without a declared game ID, a content-derived local ID avoids replacing an unrelated working game. Raw updates with different content and no game ID become separate library entries. Declared non-English/non-Arabic languages or visual Arabic ordering are rejected rather than relabeled. Unsupported licensing metadata structures are rejected rather than silently dropped. Sources remain partial; no missing dialogue is generated.

## Bounds and cancellation

- Input copy: 128 MiB, 64 KiB chunks, regular files only, coordinated scoped access, background utility queue.
- Raw parsing: 16 MiB UTF-8/16 input, 50,000 records, bounded fields/columns/nodes/depth. JSON graph is depth/node bounded before deserialization; XML never resolves external entities.
- ZIP: 64 entries, 64 MiB total general extraction, 16 MiB per general entry, 100:1 maximum expansion ratio, no traversal, absolute/drive paths, symlinks or duplicate/case-colliding paths. GLPACK retains its existing 256 MiB SQLite bound and stricter closed layout.
- Conversion deadline: 120 seconds; cancellation checked during copying, archive extraction, hashing, parsing, matching, insertion and pre-commit. File coordination cancellation is forwarded. SQLite's existing query time bounds remain; validation also supports cooperative interruption. Temporary copies are removed before completion, failure or cancellation is reported.
- Existing library changes occur only after complete checksum/schema/content validation and a pre-commit cancellation check. Cancellation after an already completed atomic commit is reported as success rather than pretending installation was rolled back.
- Live-session import is prevented; starting a session while conversion is busy is also prevented. PS5, TLS/WSS, OCR, Argos, reconnect, silent audio, speaker/RTL rendering and the TV/Windows source are otherwise unchanged.

## Validation and delivery

Pending CI and physical validation. Source/packaging/converter tests run locally on Windows; Swift and UIKit/XCUITest run in the existing macOS GitHub Actions workflow. Synthetic UI fixtures contain no third-party localization. Release IPA must be unsigned; external signing remains the user's responsibility. No Android rebuild is required.
