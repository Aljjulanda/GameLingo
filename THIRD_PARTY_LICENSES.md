# Third-party notices

The dedicated PS5 window source uses psutil (BSD-3-Clause), windows-capture (MIT) and its OpenCV dependency. License files and the OpenCV wheel's third-party notices are in the corresponding subdirectories of licenses.

The Windows build dynamically loads Qt/PySide6 and Shiboken under LGPLv3. Their original DLLs remain replaceable in the installed directory. Source and build materials for the matching Qt and Qt for Python releases can be obtained from https://download.qt.io/official_releases/qt/ and https://download.qt.io/official_releases/QtForPython/. The licenses directory beside the executable contains the applicable terms and wheel notices.

Python uses the PSF license. Windows OCR is provided by the installed Windows runtime. PyWinRT is MIT. Pillow uses the MIT-CMU license, MSS uses MIT, NumPy uses BSD terms with bundled notices. CTranslate2 uses MIT, SentencePiece uses Apache-2.0, and websockets uses BSD-3-Clause. Cryptography distributes code under Apache-2.0 or BSD-3-Clause and includes OpenSSL notices. PyInstaller uses GPL terms with its bootloader exception. Build and evaluation tools are listed separately in DEPENDENCIES.md.

The Android APK includes Kotlin standard libraries, OkHttp and Okio, each under Apache-2.0. The overlay source was written for this project. No TvOverlay, TVAssist, UrTV or chiaki-ng source was incorporated. chiaki-ng remains a separate AGPL-3.0 application acquired directly from its own release. Its official binary and account data are outside the installer.

The English–Arabic translation package is a separate user download from Argos. Its upstream README names OPUS OpenSubtitles and UNPC as training corpora. Model attribution is preserved in the installed model directory. The included installer contains no translation weights. See https://github.com/argosopentech/argospm-index and the installed model README.

