# Physical TCL preview follow-up — 2026-11-14 (Asia/Muscat)

The user made the TCL available again after the original preview report. The previously pending document/discovery checks were completed on the actual **TCL Smart TV Pro**, Android 12 / API 31, LAN IPv4 `192.168.3.138`. Host fixture: the existing Windows computer at `192.168.3.70`. These addresses document the observed test setup, not a subnet-based reachability assumption.

## Exact scope and provenance

App sources under test are the published preview snapshot `e7b7a3ea3782408e8768477a80d3c32331594929`, using the isolated **Lab build variant** `dev.gamelingo.tv.lab` version 0.6.0 (8). Production application code was not patched for the test. The variant changes the app ID/label and has independent preferences and Android Keystore. The test-only `NetworkRunner` was extended to request document and discovery assertions; its canonical-LF source hash is recorded in the accompanying JSON.

The user's production `dev.gamelingo.tv` stayed at **0.5.2 (7)** throughout. It was not uninstalled, updated, reset or paired to the fixture. The test runner cleared its separate preferences on exit. The tests did not access or change PS5 registration or the working phone-to-TV pairing.

Published binaries are unchanged:

| Asset | SHA-256 |
|---|---|
| GameLingo-unsigned.ipa | `a1a3239f62f348979cb95d8f5594694ab33b30e14bc5adc84ca96200b548e1ff` |
| GameLingo-TV-0.6.0.apk | `86699e0a7191a0be244392ecb7aa47648d2770e8a44bd0a3e58f5251300420af` |

The IPA remains from successful Actions run **43527679961**. No new Apple binary was generated or substituted for this follow-up. The user chose to retain the last successful IPA as a preview after the account billing block. Later unbuilt iOS changes are still excluded.

## Passed on hardware

1. **AdvancedCanvasRunner:** actual Android spans, StaticLayout, overlay view and Canvas on TCL passed inline speaker/color/RTL/wrapping checks, stable card/expiration/anchor, long document panel, next-page content, hide and return to dialogue. Test output:

   ```text
   PASS: inline speaker/color/RTL/wrap, stable card/clock/anchor, document pages and return to dialogue
   ```

2. **NetworkRunner plus unchanged Windows Hub:** the actual Android Receiver/OkHttp/AndroidKeyStore performed LAN TLS/pinning and PIN pairing, encrypted token storage, stale source/revision replacement, settings synchronization/ACK, ping/pong, saved-token reconnect and safe diagnostic redaction. It received page 1, page 2, document close and a new dialogue message. An attempted renderer ACK was correctly withheld for the legacy server, preserving its accepted message types.

3. **Real mDNS recovery:** after secure pairing, only the isolated fixture's saved host was replaced with obsolete `192.168.255.254`. The Receiver failed over through Android NSD to a real `_gamelingo._tcp.local.` advertisement from the PC, then authenticated and saved the correct host. Assertions checked the `discovery.found` stage and exact preservation of the full saved certificate fingerprint and encrypted authentication token. No new PIN or token was supplied for discovery recovery. Output:

   ```text
   PASS: physical Android LAN TLS/pinning, encrypted token, source/revision replacement, settings, ping/pong, saved-token reconnect, document pages/close and resumed dialogue, obsolete-host recovery through mDNS preserving full pin/token
   PASS: unchanged Windows server received settings_ack from physical TV
   ```

Both instrumentations returned Android `Activity.RESULT_OK` (`INSTRUMENTATION_CODE: -1`). Build/test stdout contains only fixed results and sanitized stages, never the temporary fixture PIN/token.

After the hardware runs, the Python coordinator's timeout-only error path was hardened to suppress `TimeoutExpired` arguments, which can contain the temporary fixture PIN. A separate simulated timeout check passed without contacting the TV. The successful execution path and production app code did not change. Evidence hashes identify the final reusable harness.

## Reproduction

Use an authorized ADB connection and a separate Lab build; do not run the fixture against the user's production preferences. Build the preview snapshot with `-PlabBuild -PadvancedCanvasTest`, install its Lab APK and test APK, grant Lab overlay permission, and run:

```text
adb -s <TV> shell am instrument -w dev.gamelingo.tv.lab.test/dev.gamelingo.tv.AdvancedCanvasRunner
```

Copy the extended `NetworkRunner.kt` from the development branch into that snapshot's androidTest source only. Build with `-PlabBuild -PtvNetworkTest`, update the test APK and run the repository fixture:

```text
python -m pip install --target iOS/.build/discovery-packages zeroconf==0.154.0 ifaddr==0.2.0
python iOS/Integration/test-tv-windows.py --adb <adb.exe> --tv <TV> --host <PC-private-IPv4> --package dev.gamelingo.tv.lab --documents --discovery --discovery-packages iOS/.build/discovery-packages
```

The optional test dependency is installed only into the ignored target directory, not the working Windows application's environment. The fixture uses [python-zeroconf's ServiceInfo/Zeroconf API](https://python-zeroconf.readthedocs.io/en/latest/api.html), advertises only the temporary fixture's public certificate hint, unregisters it on exit and stops the temporary Windows Hub. The Windows application implementation itself is unchanged. Temporary publication queues and delayed messages are fixture-only.

## What remains unproven

This validates the preview Android source through an isolated build on actual TCL hardware, plus a real LAN/mDNS fixture. It is **not** a physical iPhone-to-TCL end-to-end test of Smart Reading or the iPhone's Bonjour advertisement. It does not prove continuous translation while Instagram is active, during calls or while the phone is locked. Real-game OCR ordering/translation quality, phone energy/thermal cost and all background-duration scenarios remain pending. Follow the original preview's instruction to disable screen dimming before experimenting with background execution.
