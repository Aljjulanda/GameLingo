# Build

## Windows x64

Use Python 3.12 x64 with a Windows English OCR pack. In this checkout create a venv and install desktop/requirements-lock.txt from PyPI. From the repository root, with that environment active:

```powershell
python scripts/make_icon.py
python scripts/collect-notices.py licenses
python -m pytest desktop/tests
python -m PyInstaller --noconfirm --distpath dist --workpath build desktop/GameLingo.spec
Copy-Item licenses dist/GameLingo/licenses -Recurse -Force
Copy-Item THIRD_PARTY_LICENSES.md dist/GameLingo
python scripts/build-msi.py dist/GameLingo C:/tools/wix314 build/GameLingo-Setup.msi
```

Install the EN–AR model via the GUI before running the OCR + translation test. Set PYTHONPATH to the absolute desktop directory for pytest. Use WiX 3.14.1 binaries from the official wix3 release. The executable supports `--self-test absolute-report-path.json` for the synthetic end-to-end smoke test; run the GUI normally without arguments. Avoid adding unrelated toolchain DLL directories to the packaging environment. Windows supplies the ICU interface for Qt. PyWinRT requires its native .pywinrt tables beside the projection packages.

Starting with the 0.2.1 Windows package, the frozen self-test also starts a TLS listener on a random loopback port. The spec bundles the current Python distribution's matching OpenSSL libraries and, if present, its public SSL trust-policy asset. This preserves the runtime trust configuration.

## Windows capture verification

Run the installed executable with `--window-test absolute-report.json` to measure six short, uncached English captions in a real generated test window using Windows.Graphics.Capture. The fixture includes a changing corner counter, a two-line sentence, and extending text. `scripts/check-visible-dialogue.py` runs the same test from source. The report records misses and timings and is separate from the physical PS5 evidence.

## Android TV

Set JAVA_HOME, ANDROID_HOME and GRADLE_BIN for JDK 17/21, Android SDK 34 with build-tools 34.0.0 and Gradle 8.9. With Git Bash run `bash scripts/android-build.sh`. The connected debug APK is android-tv/app/build/outputs/apk/debug/app-debug.apk. Use a persistent **project-specific** Android user home to retain the debug signing identity for local updates. Secrets and signing keys are excluded from source archives.

For release distribution run `:app:assembleRelease` and sign the aligned APK with your own release key using Android build-tools apksigner. Verify with `apksigner verify --verbose`. A release identity must remain consistent for future updates. On this TCL the installed builds use the project debug identity.

Use scripts/tcl-test.sh from Git Bash only with an explicit TV_HOST, URTV_DIR, and package verified locally. Its identity guard checks manufacturer, model, G10, Android 12 and Aljulanda TV before any installation. The install path is for a new package; update uses pm install -r with the same signing identity. Neither operation alters Home or accessibility configuration. User consent is required before enabling the special overlay permission at installation.

