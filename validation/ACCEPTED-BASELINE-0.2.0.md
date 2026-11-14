# Accepted GameLingo 0.2.0 baseline — 2026-11-14

The user explicitly accepted the current successful version and requested updating the production TCL application. This supersedes the former 0.1.1 / TV 0.5.2 baseline for future development; the old release and recovery tag remain available.

## Accepted artifacts

| Artifact | Version | Compiled source | SHA-256 |
|---|---|---|---|
| iPhone unsigned IPA | 0.2.0 (4) | `9ffe9814e2be2741a9782c84c08e4c5ff6b62872` | `d5ad9c4f336259b1e370ce7959639d3a0ff701b00c9cda11300385f35c9f1b8b` |
| Production TV APK | 0.6.0 (8) | `e7b7a3ea3782408e8768477a80d3c32331594929` | `86699e0a7191a0be244392ecb7aa47648d2770e8a44bd0a3e58f5251300420af` |

The TV APK is exactly the published, physically tested snapshot from preview 1; no rebuilt or differently signed APK was substituted. The current source tree also includes a later NSD exception guard, which is not in this accepted APK. The iPhone file is exactly preview 2's successful Actions artifact, not a new build.

Recovery tag: `stable/real-device-0.2.0` at the compiled iPhone source. Stable release: `ios-v0.2.0`. Main was advanced by a normal fast-forward to that source; subsequent documentation-only baseline recording does not change the app binaries. Prior tag `stable/real-device-0.1.1` and earlier releases are preserved.

## Production TCL update evidence

- Device: TCL Smart TV Pro, Android 12 / API 31.
- Original production package: `dev.gamelingo.tv`, 0.5.2 (7).
- `adb install -r` succeeded with the original signer certificate SHA-256 `48cf8a45a37f4e5c338f98fa7d5135c7cdbaf59d50b39b8bf591a79622a28e38`.
- Production package now reports 0.6.0 (8).
- SHA-256 of the saved overlay preferences file matched byte-for-byte before/after installation, measured while the app was stopped. No preference values or credentials were printed or archived.
- Relaunch restored `OverlayService` as a foreground service. Overlay permission remained allowed. Saved host/token and the 64-character certificate fingerprint were still present; values were not logged.
- The app reported **connected, waiting for translation** after restart. This is authentication/connection evidence, not proof that every new feature has rendered a real game line in this follow-up.

## Evidence and remaining limits

Actions [43561212569](https://github.com/Aljjulanda/GameLingo/actions/runs/43561212569) passed 42 Swift core, 14 Apple integration and four packaging-tool tests. Previous Android checks passed 24 unit tests. Physical source-equivalent Lab tests passed inline name/RTL/wrapping/stable clocks, document pages/close/return, real Receiver delivery and pinned mDNS recovery against the unchanged PC Hub; see [TCL follow-up](TCL-PREVIEW-2026-11-14.md).

The user's acceptance is a real-device success report, not a laboratory energy or long-duration background certification. Silent background audio stays optional/experimental. Instagram/audio interruptions, lock-duration continuity, physical frame-starvation recovery, phone energy/thermal impact and broader game-specific OCR/translation quality remain limited to the explicitly recorded evidence. Do not convert adoption into unsupported claims about these scenarios.

Future work should preserve this accepted architecture, PS5 credentials/streaming, current pin/token protocol and Windows program. New experiments should use a separate development branch and retain this recovery point.
