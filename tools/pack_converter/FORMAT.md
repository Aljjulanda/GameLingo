# GameLingo Translation Pack format 1

`.glpack` is a ZIP containing exactly three ordinary files, with case-sensitive names:

```
manifest.json
translations.sqlite
checksums.json
```

There are no scripts, plugins, fonts, symlinks, nested paths, executable files, remote references or SQL statements supplied by the manifest. Additional/duplicate entries are rejected. Integrity hashes detect damage; they do not authenticate authorship or grant distribution rights.

## Manifest

UTF-8 JSON, at most 64 KiB. Required keys:

| Key | Constraint |
|---|---|
| `format_version`, `schema_version` | Both `1` |
| `game_id` | Lower-case ASCII identifier, 1–64 characters; `[a-z0-9][a-z0-9._-]*` |
| `game_title` | 1–100 characters |
| `source_language`, `target_language` | `en`, `ar` in this version |
| `pack_version` | 1–32 characters |
| `record_count` | 1–500,000 database rows |
| `usable_count` | 0–record_count rows passing the converter's format/placeholder gates; runtime ambiguity can still reject them |
| `categories` | Unique nonempty subset of `dialogue`, `menu`, `document`, `general` |
| `attribution` | Source description, at most 4,096 characters |
| `permission` | Actual license/permission information or an explicit unknown status, at most 2,000 characters |
| `built_at` | Build timestamp, at most 64 characters |
| `arabic_order` | Must be `logical` |
| `database_sha256` | Lower-case SHA-256 of the database |
| `speaker_names` | Optional list, at most 64 names of at most 40 characters; no comma/newline. Hints, never executable behavior |

The imported file is at most 128 MiB. The database is at most 256 MiB; checksums JSON at most 2 KiB. Each member must have a compression ratio at most 100:1. Extraction streams 64 KiB chunks to generated paths and verifies CRC and SHA-256 before activation. Checksums JSON contains exactly SHA-256 entries for `manifest.json` and `translations.sqlite`.

## SQLite schema

`PRAGMA user_version=1`. The exact schema is deliberately closed for version 1:

```sql
CREATE TABLE entries (identifier TEXT NOT NULL, original_id TEXT NOT NULL, source TEXT NOT NULL, normalized TEXT NOT NULL, target TEXT NOT NULL, category TEXT NOT NULL, source_file TEXT NOT NULL, flags TEXT NOT NULL, usable INTEGER NOT NULL)
CREATE INDEX by_exact ON entries(source, category)
CREATE INDEX by_normalized ON entries(normalized, category)
CREATE INDEX by_identifier ON entries(identifier)
```

No views, triggers, virtual tables, additional user tables or additional indexes are accepted. New schema requirements need a new schema version. Original IDs and conflicting target variants remain distinct rows. `source_file` records source provenance; it is never interpreted as an import/extraction path. `flags` is diagnostic JSON text. `usable` is 0 or 1.

Source and normalized text are at most 4,096 characters, target 16,000, source provenance 8,192 and flags 2,048. Import verifies UTF-8, field types, category membership, row/eligible counts, normalized keys, logical Arabic for eligible targets and SQLite integrity. No NUL characters are accepted.

Connections are read-only/immutable, with trusted schema disabled, query-only mode, no memory mapping, a 2 MiB page cache, reduced SQLite limits and bounded progress deadlines. Every query is fixed SQL with bound text parameters. No imported SQL is executed. No entire-database dictionary is built.

## Matching and ambiguity

Search only the selected, enabled, validated game's database. First try exact source and then a normalized key: NFKC, removal of incoming directional format controls, consistent curly apostrophes/quotes, whitespace/line wrapping, lower case and terminal `.`/`!` cosmetics. Questions, numbers/signs, actions, negation, directions and name text are not removed or fuzzily aliased. All target variants are considered, including blocked rows. Conflicting translations, unsupported rows or more than 32 matching records cause fallback. Equal translations associated with multiple IDs are safe only within that bound.

Dialogue searches `dialogue` plus `general`. On-demand Smart Reading searches `document` plus `general` using its existing complete chunks. It never replaces a paragraph with a substring match. Categories without reliable game-format evidence stay `general`; do not invent separate menu/document coverage counts. Approximate matching is intentionally disabled in the first version. A missing OCR character may reduce hit rate and correctly falls back to Argos.

## Installation and lifecycle

The iOS Files picker provides a security-scoped URL. GameLingo coordinates/copies it into a generated staging directory, validates there, creates a new UUID directory and atomically commits a small registry. A failed import leaves the old registry/pack active. Same-game imports replace only after validation and retain selection/enabled state. Identical manifests do not create duplicates. Removal clears selection if needed. There are at most 32 installed games.

The selected game and enabled state persist independently of PS5/TV credentials. Imported data uses protection until first user authentication, so an already-unlocked device can continue reading packs when locked where the existing iOS execution policy allows. A database is kept open across automatic reconnects. Selection changes discard the previous runtime connection; pending activation epochs cannot activate the wrong game. Startup checks the database hash again. Missing/corrupt packs cause an explicit warning and Argos fallback.

## RDR2 adapter limitations

The supplied installer contains a gzip-compressed **UTF-8 text export**, despite the `.gxt2` extension, inside CLR manifest resources. The converter also supports the documented little-endian binary GXT2 table layout as a separate detected input shape. It does not claim support for every installer or game format.

RAGE textual labels are joined using lower-case ASCII Jenkins one-at-a-time hashes; the original label is retained. Hex IDs are preserved canonically. English input defaults to strict UTF-8; the inspected dump needs the explicitly selected strict UTF-8/CP1252 policy. Conflicting English ID values are excluded rather than arbitrarily joined. Arabic conflicting ID variants are retained for runtime ambiguity rejection.

`~z~` is a subtitle-display marker, `~n~` a line break, and `~sl:...~` a timing/segment boundary. Only those known controls are interpreted. Unknown formatting, input/controller codes, variables and runtime placeholders remain flagged and ineligible. There is no assumption that a PC controller label is correct for PS5.

Arabic presentation-visual ordering must be explicitly selected for this producer. Conversion respects hard/timing boundaries, mirrors bracket glyphs, protects Latin/numeric islands and handles the observed visual-before-base vowel marks. Lam-alef ligatures expand after ordering. Already logical strings are not reversed. Complex mixed visual paragraphs are flagged. This is a producer-specific conversion, not a universal inverse of Unicode bidi; linguistic/visual review is still required.
