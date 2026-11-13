# Physical-device acceptance record

Status: all items below are **not run in this session**. Record date, device, iOS, PS5 firmware, TV version, core commit, Xcode, IPA SHA-256 and actual observations before marking pass.

- [ ] External signing/install succeeds; multicast entitlement/profile behavior documented; local-network prompt correct.
- [ ] PS5 discovery returns the real console; manual IP works when broadcast is unavailable.
- [ ] Invalid account/PIN rejected; valid pairing stored in Keychain; no key/token emitted to logs.
- [ ] App relaunch reuses saved consoles and TV identity; settings/position persist.
- [ ] PS5 game stays on TCL HDMI; controller on main account and streaming on secondary account do not interfere.
- [ ] VideoToolbox receives/decodes real H.264 frames; OCR is fed CVPixelBuffer with no renderer/screenshot.
- [ ] Short commands, multiline dialogue, extending captions, OCR jitter, speaker-label loss, number and negation changes behave correctly.
- [ ] Model download/import validates checksum; airplane mode with Wi-Fi enabled still translates after installation.
- [ ] Genuine repeated dialogue after disappearance or intervening dialogue appears; duplicate observations do not create entries or restart timers.
- [ ] Slow/obsolete translations never replace newer dialogue; disconnected frames/results do not survive reconnection.
- [ ] Existing unmodified GameLingo-TV.apk pairs using iPhone address/code; wrong fingerprint/PIN/token rejected.
- [ ] TV reconnect starts empty, then receives new dialogue only; old messages never replay.
- [ ] Normally one subtitle; rapid dialogue stacks up to three upward; fourth removes oldest; newest anchor stays fixed.
- [ ] Each sentence expires independently during silence; corrections retain original clock; grace/hard cap work.
- [ ] Windows style import preserves appearance; settings revisions/acknowledgements and live preview succeed.
- [ ] Every font/color/opacity/outline/shadow/background/width/alignment/line-spacing control renders correctly.
- [ ] Background fits actual Arabic text; default 60% max width; 1/5/10/custom pixel nudges remain precise at TV edges.
- [ ] Stop/background/lock clear TV, release stream, restore brightness and idle timer. Foreground resume requires deliberate restart.
- [ ] 60–120 minute session: record OCR/translation/end-to-end percentiles, memory growth, battery delta and thermal transitions, without invented CPU/GPU values.
- [ ] Adverse LAN tests: dropped network, console standby, TV restart, Wi-Fi address change, unavailable model and memory pressure.
- [ ] Switching back to unchanged Windows application and TV pairing still works. Keep historical desktop/TV evidence separate from this test record.
