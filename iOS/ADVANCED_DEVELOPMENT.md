# Advanced development: baseline and background experiment

## Recovery and architecture

The user confirmed physical iPhone, PS5 and TCL translation works on the 0.1.1 / TV 0.5.2 baseline (`ce6d3995f20b2250f5567348c7b7c6834785e172`). Low battery use and no noticeable heat are user observations, not benchmark numbers. The protected recovery tag is `stable/real-device-0.1.1`; development is isolated on `codex/advanced-ios`. A local Git recovery bundle is in the ignored delivery directory.

Preserve Chiaki -> VideoToolbox -> CVPixelBuffer -> Vision -> local Argos/CTranslate2 -> pinned WSS -> TCL. No continuous video renderer is introduced. The game remains on HDMI. Windows is unchanged. Before development, the existing Windows suite passed 51 tests; source preservation validation passed. The baseline GitHub run is [43500370946](https://github.com/Aljjulanda/GameLingo/actions/runs/43500370946).

## Phase 1: opt-in background audio

`BackgroundAudio` uses AVAudioEngine with a mono zero-producing source node, `.playback` and `.mixWithOthers`. The realtime callback only clears preallocated buffers. It does not access the microphone, decode PS5 audio, duck other apps, use VoIP/location, or render video. The option defaults off, including when migrating existing settings. Turning it on is an experiment, not a claim of indefinite execution or App Store eligibility.

Audio interruption began stops the audio engine while preserving user intent and initially preserving healthy network sessions. Ended with `.shouldResume`, route changes, media-services reset, foreground activation and network restoration offer recovery opportunities. No aggressive audio-focus retry loop is used. If no valid execution mode remains, a finite UIKit background-task grace period is bounded to at most 20 seconds (or OS expiration), after which network/processing work is suspended while user intent remains. Manual Stop invalidates all scheduled recovery work.

The PS5 controller only recovers a missing native session. A live or starting session is retained. The model is not reloaded during recovery. Continuing source dialogue is suppressed across connection interruptions; no previous subtitle buffer is replayed.

Vision is explicitly CPU-only during the background experiment to avoid relying on background GPU access. Foreground processing retains the baseline configuration. CPU, latency and battery impact still require measurement on the physical phone.

The existing Keychain protection remains `WhenUnlockedThisDeviceOnly`. The TV token digest is cached in RAM for an already-running listener, so a token reconnect does not reread locked Keychain. Creating a fresh identity/listener or pairing while locked can still fail; protection is not weakened to hide this limitation.

Bonjour advertises `_gamelingo._tcp` with a public certificate-prefix service name. This is an address hint only: discovery must retain full saved certificate validation and token authentication. Manual IP remains available. `NSBonjourServices` is declared; no new raw multicast capability is added.

## OS limits and alternatives

- [Apple playback category](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback): background audio configuration supports media playback; it does not guarantee indefinite unrelated OCR/translation work from silence.
- [mixWithOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers): mixing avoids interrupting another app's audible session. No ducking or spoken-audio interruption option is used.
- [Handling interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions): the iOS 16-compatible legacy interruption API is used. Missing callbacks and suspension prevent a guarantee of immediate recovery. Newer lifecycle notifications cannot be compiled with the preserved Xcode 16.4 primary build.
- [Continuous background tasks](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados) support user-initiated jobs with real completion/progress, cancellation and expiration; they are not an entitlement to an endless session. A finite Smart Reading job is a better fit than an endless game stream, but newer SDK support and physical validation are required before integrating it.
- BGProcessingTask is system-scheduled, not a low-latency stream keepalive. Live Activities / Now Playing display status and do not independently grant execution. PiP is not implemented: the user prefers no rendering and there is no measured reason to add its overhead.

## Required physical validation

Simulator state-machine and network tests cannot certify background operation. For each foreground, Home Screen, Safari, WhatsApp, Instagram scrolling/video/stopped video, call, route/Bluetooth change and Wi-Fi interruption scenario, observe **new** dialogue IDs translated and rendered on TCL. Repeat screen-lock sessions for 5/15/30/60 minutes. Record CPU, memory, thermal state, battery percentage change, OCR/translation latency, audio state and reconnect count. Record any missing callback, protection error or OS suspension honestly. Do not label any of these scenarios successful until observed on hardware.
