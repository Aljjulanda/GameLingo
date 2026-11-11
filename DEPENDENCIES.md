# Dependency selection

Exact Python build pins are in desktop/requirements-lock.txt. Hardware and execution results are in TEST_RESULTS.md. Selection was based on the Windows 10 host with two physical CPU cores, Intel Iris 6100 and approximately 16 GiB RAM.

| Component | Version or evaluation | License | Role and limitation |
|---|---|---|---|
| [Windows OCR](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine) | Windows 10 build 19045, local en-US pack | Windows component | English OCR in memory, word coordinates, no confidence score. The host also has ar-SA. |
| [PyWinRT](https://github.com/pywinrt/pywinrt) | Runtime 4.1.0, projection pins in lock | MIT | Native OCR from Python. Retain the binary projection tables in frozen builds. |
| [Qt for Python](https://doc.qt.io/qtforpython-6/) | PySide6-Essentials 6.12.0 | LGPLv3 option | GUI and RTL. Dynamically linked. |
| [Pillow](https://github.com/python-pillow/Pillow) and [MSS](https://github.com/BoboTiG/python-mss) | 13.0.0 and 10.2.0 | MIT-CMU / MIT | Visible display and window-region capture; MSS enumerates attached monitors. Protected or minimized surfaces are unsupported. |
| [DXcam](https://github.com/ra1nty/DXcam) | 0.3.0, DXGI and WinRT evaluated separately | MIT | Output duplication works on the host. Its WinRT backend logged an unavailable optional frame-rate property on this Windows version. Not bundled. |
| [Argos Translate](https://github.com/argosopentech/argos-translate) and [package index](https://github.com/argosopentech/argospm-index) | EN→AR 1.0 | Argos code MIT; model distributed separately | The official direct English–Arabic model is loaded through its native tokenizer and inference engine. No Stanza/Torch or model index call during gameplay. |
| [CTranslate2](https://github.com/OpenNMT/CTranslate2) and [SentencePiece](https://github.com/google/sentencepiece) | 4.9.0 and 0.2.3 | MIT / Apache-2.0 | CPU int8, one grouped subtitle. Numbers, inflection, menu terms and names require evaluation. |
| [websockets](https://github.com/python-websockets/websockets) and [cryptography](https://github.com/pyca/cryptography) | 17.4 and 50.0.2 | BSD-3-Clause / Apache-2.0 or BSD-3-Clause | WSS, certificate generation; standard Windows DPAPI protects secrets. |
| [OkHttp](https://github.com/square/okhttp) | 4.12.0 | Apache-2.0 | Android TLS/WebSocket client. Explicitly pinned self-signed identity. |
| [Android SDK](https://developer.android.com/reference/android/view/WindowManager.LayoutParams), Kotlin, Gradle | SDK/build tools 34, AGP 8.5.2, Kotlin 1.9.24, Gradle 8.9, JDK 21 | Android SDK terms and component licenses, Kotlin/Gradle Apache-2.0 | Tested on API 31, min API 26. Target 32 for this local build. |
| [PyInstaller](https://github.com/pyinstaller/pyinstaller), [WiX](https://github.com/wixtoolset/wix3) | 6.22.3 / 3.14.1 | GPL with bootloader exception / MS-RL | Windows x64 onedir and MSI. WiX 3 is a legacy build-only tool. |
| [chiaki-ng](https://github.com/chiaki-ng/chiaki-ng/releases/tag/v1.10.1) | 1.10.1 portable x64 | AGPL-3.0 | Separate program, owner pairs on PS5. This host needed the [LunarG](https://vulkan.lunarg.com/sdk/home/) x64 1.4.363.0 loader beside chiaki.exe and its documented OpenGL switch. |
| [Sony PS Remote Play](https://remoteplay.dl.playstation.net/remoteplay/lang/en/1100001.html) | Official alternative, not integrated | Sony terms | The user handles sign-in. Captureability, physical-controller interaction and protected surfaces depend on actual testing. |
| [RapidOCR](https://github.com/RapidAI/RapidOCR) / [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) | Package candidates 3.10.0 / 3.7.0 | Apache-2.0 | Potential multilingual backends. No performance/accuracy claims or bundled model weights. |
| [Tesseract](https://github.com/tesseract-ocr/tesseract) / [DeskTranslate](https://github.com/DeskTranslate/DeskTranslate) | Reviewed as alternatives | Apache-2.0 / MIT | Neither is required by the selected native OCR path. |
| [TVAssist](https://github.com/manjotsc/tvassist_android) / [TvOverlay](https://github.com/gugutab/TvOverlay) | Reference documentation | Apache-2.0 / no repository license identified | Independent code. References do not establish HDMI compatibility. |

The Windows client downloads only the model explicitly requested in the model manager. Its official HTTPS payload was measured at 88,502,631 bytes, SHA-256 e2a6e84337f7ebbb55f9dc61dcba3a861c0d786ae5a46fa198fd8d6473f5c775. Installation verifies the pinned bytes and whitelists archive entries. Other pairs are not offered until tested.

