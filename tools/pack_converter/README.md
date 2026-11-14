# GameLingo Pack Converter

Requires Python 3.10+ with SQLite. Only static CLR extraction additionally requires the pinned dependencies in `requirements-extraction.txt`:

```powershell
python -m pip install -r tools/pack_converter/requirements-extraction.txt
python tools/pack_converter/test_converter.py
python tools/pack_converter/convert.py extract --installer C:/Users/julanda/Desktop/Arabic-RDR2.exe --output iOS/.build/rdr2-private
git clone https://github.com/cedricalpatch/Red-Dead-Redemption-2-Text-Files.git iOS/.build/rdr2-english
git -C iOS/.build/rdr2-english checkout cdb2b8ab3134291a19a86d8d35fe0bd48cb8f926
python tools/pack_converter/convert.py build --english iOS/.build/rdr2-english --arabic iOS/.build/rdr2-private/r_text.gxt2 --output iOS/.build/rdr2-private/RDR2-Arabic.glpack --report iOS/.build/rdr2-private/conversion-report.json --game-id rdr2 --title "Red Dead Redemption 2" --pack-version 1.5-gl1 --attribution "Arabic PC 1.5 supplied localization; English cedricalpatch cdb2b8a; authorship unverified" --english-revision cdb2b8ab3134291a19a86d8d35fe0bd48cb8f926 --english-encoding utf-8-or-cp1252 --arabic-order presentation-visual --timestamp 2026-11-14T00:00:00Z
```

Use an ignored/outside-repository work directory for real data. Do not execute the installer, DLLs, ASIs or scripts. Extraction reads only the supported resource and never installs a mod or writes registry entries. Unsupported formats fail explicitly. Raw `.gxt2` text/binary files can be supplied directly to `build` without using an installer.

For another game's compatible exported table, set its game ID/title/attribution; do not reuse RDR2 ordering conventions without evidence. `parse_file`, `prepare`, `extract` and the shared ID-join/package builder are separate data adapters/stages for extending input support. No new iPhone build is required for each compatible pack. See [the versioned format specification](FORMAT.md).

The build preserves all original IDs and computes coverage/conflict/placeholder/order diagnostics. It never creates missing translations using a model. Given identical inputs, options, timestamp and SQLite/Python implementation, the generated package is deterministic. Source paths use portable `/` separators.

Local outputs may contain third-party copyrighted text. Neither public availability nor an installer loader's MIT license grants rights to redistribute its translation tables. The inspected English repository has no identified permissive content license; the Arabic site credits KG Studio and its own revision team, but no permission for GameLingo redistribution was established. Generate/import the pack locally. Do not commit it or upload it to a public release without permission.

`validate-real-rdr2.py` optionally verifies the pinned public installer hash and English revision, rebuilds transient data and checks it using the actual Swift/SQLite reader on a CI Mac. It never executes the installer. Third-party tables stay in ignored private working storage; only content-free counts/timing are exported. `--python-only` performs extraction/conversion without the native Swift phase on Windows. This does not certify physical iPhone gameplay, translation accuracy, or a global pack hit rate.

On iPhone: Files â†’ save `.glpack`; GameLingo â†’ Translation â†’ Game Translation Library â†’ Add Pack; inspect the imported game and choose it. Ordinary use is offline. Keep the Argos model installed for immediate fallback. Stop the translation session before changing/importing/removing packs. Smart Reading remains manually activated.
