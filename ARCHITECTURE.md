# GameLingo 0.2

The PS5 sends its primary HDMI signal directly to the TCL. A separately registered Remote Play client on the PC can supply a secondary view. The PC may also use a selected monitor or image file. GameLingo never forwards gameplay video to the TV.

## Windows

The PySide6 event loop owns the GUI. FrameSource produces an RGB PIL image, source identifier, dimensions and capture timestamp. WindowCaptureSource reads the foreground client area in physical desktop coordinates and suspends if the window loses focus or is minimized. DesktopCaptureSource reads a chosen display. ImageFileSource and SampleSource make repeatable tests possible without a console. All frame buffers are ephemeral.

The capture worker crops a normalized ROI, converts to grayscale, and hashes the exact region. Identical pixels reuse the latest OCR reading. Sampling slows on static frames. Windows.Media.Ocr returns words, lines and bounds. The subtitle region is grouped into one segment. The first shipped translation profile is English to Arabic. OCR returns no numeric confidence on this backend.

A tracker assigns a generation to each new line and tolerates limited OCR jitter on longer lines. An empty interval expires the line. One translation thread owns the model and SQLite connection. At most one job is active and one newer request waits. A result from an older generation is discarded. Each recognized line is cached in SQLite WAL and a bounded in-memory LRU. Cache identity includes normalized text, language pair, model, profile, and glossary. The Argos EN–AR model runs through its SentencePiece tokenizer and CTranslate2 on CPU. The model receives the grouped sentence. Recent text is held in memory only.

The capture worker posts bounded latest-value network events. WSS is off until the PC listener is requested or an existing pairing is resumed. The server binds one private IPv4 address. Each installation creates a TLS identity protected by Windows DPAPI. On first pairing the TV verifies the certificate fingerprint prefix shown on the PC before sending a short-lived PIN. Subsequent connections verify the entire certificate and authenticate using a random token. Windows stores the token digest. The TV encrypts the token with an Android Keystore key.

## TV

Kotlin Activity → foreground OverlayService → WindowManager.TYPE_APPLICATION_OVERLAY. The label is non-focusable and non-touchable. The service starts while the activity is visible and is explicitly stoppable. The permission flow uses Android settings. A test-only text can be displayed for ten minutes. The live receiver renders Arabic using Android fonts. It rejects unknown sessions and old sequence numbers and clears immediately on disconnect. A monotonic timer bounds message visibility. Keep-alive WebSocket pings and exponential retry recover a stopped listener. Existing UrTV components have no role in this application.

## Protocol 1

WSS over TCP 38443. UTF-8 JSON, integer `v: 1`, up to 16 KiB. New PC process means a new random session ID. The TV initiates `pair` with its one-time PIN or `hello` with its token. Successful first pairing returns `paired`; the server then sends `connection_status` with session and wall time. The client uses the server clock plus elapsed time for expiry. `subtitle_show` and `subtitle_update` carry id, sequence, session, original and translated strings, source/target languages, normalized x/y/w/h, frame and translation timestamps in Unix milliseconds, nullable confidence, category, font size, duration and absolute expiration. `subtitle_clear` and `subtitle_hide` clear the label. Frames stay on Windows. The server accepts heartbeat requests after authentication. Transport violations close the connection. Independent settings messages and coordinate-following rendering are not implemented in this build.

## Distribution

The standalone overlay probe is preserved at Git tag overlay-test-v0.1.0. The connected build upgrades its package in place, using the same project-specific debug certificate. Release builds use an externally provided signing key. The Windows MSI installs into the user's profile and registers shortcuts. Models, settings, cache and pairing identity live outside the program directory.

