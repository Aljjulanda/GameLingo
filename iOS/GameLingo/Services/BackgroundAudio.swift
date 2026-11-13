import AVFAudio
import UIKit

/// Opt-in silent-audio experiment. An active engine is not proof of background
/// OCR execution. No microphone, PS5 audio, video renderer or audio ducking.
@MainActor
final class BackgroundAudio {
    var onChange: ((Bool,Bool,String) -> Void)?
    var onRecovery: (() -> Void)?
    private var engine: AVAudioEngine?
    private var observers: [NSObjectProtocol] = []
    private(set) var wanted = false
    private(set) var interrupted = false
    private let session = AVAudioSession.sharedInstance()
    private var lastRecoveryAttempt = -100.0
    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] note in
            Task { @MainActor [weak self] in self?.interruption(note) }
        })
        observers.append(center.addObserver(forName:AVAudioSession.mediaServicesWereResetNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }; self.engine = nil
                self.onChange?(false,self.interrupted,"أُعيدت خدمات الصوت")
                if self.wanted { self.lastRecoveryAttempt = -100; self.recover(); self.onRecovery?() }
            }
        })
        observers.append(center.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wanted else { return }
                self.recover()
                self.onRecovery?()
            }
        })
        observers.append(center.addObserver(forName:AVAudioSession.silenceSecondaryAudioHintNotification,object:nil,queue:.main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, self.wanted,
                      let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
                      AVAudioSession.SilenceSecondaryAudioHintType(rawValue:raw) == .end else { return }
                self.lastRecoveryAttempt = -100; self.recover(); self.onRecovery?()
            }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func start() { wanted = true; if !interrupted { activate() } }
    func recover(foreground: Bool = false) {
        guard wanted else { return }
        // Foreground reactivation is an additional opportunity if the system did
        // not deliver interruption-ended. Never contend with another audible app.
        let now = ProcessInfo.processInfo.systemUptime
        if interrupted {
            guard !session.isOtherAudioPlaying, !session.secondaryAudioShouldBeSilencedHint,
                  foreground || now-lastRecoveryAttempt >= 15 else { return }
            interrupted = false
        }
        if engine?.isRunning != true && (foreground || now-lastRecoveryAttempt >= 15) { activate() }
    }
    private func activate() {
        guard wanted, !interrupted, engine?.isRunning != true else { return }
        lastRecoveryAttempt = ProcessInfo.processInfo.systemUptime
        do {
            try session.setCategory(.playback,mode:.default,options:[.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.1)
            try session.setActive(true)
            let engine = AVAudioEngine()
            let format = AVAudioFormat(standardFormatWithSampleRate:44100,channels:1)!
            let source = AVAudioSourceNode(format:format) { silent,_,_,buffers -> OSStatus in
                silent.pointee = true
                for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                    if let bytes = buffer.mData { memset(bytes,0,Int(buffer.mDataByteSize)) }
                }
                return noErr
            }
            engine.attach(source); engine.connect(source,to:engine.mainMixerNode,format:format)
            engine.prepare(); try engine.start(); self.engine = engine
            onChange?(true,false,"تجربة الصوت الصامت نشطة؛ استمرار الترجمة بالخلفية غير مضمون")
        } catch {
            engine?.stop(); engine = nil
            onChange?(false,false,"تعذر تفعيل تجربة الخلفية · \((error as NSError).code)")
        }
    }
    private func interruption(_ note: Notification) {
        guard wanted else { return }
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue:raw) else { return }
        if type == .began {
            interrupted = true; engine?.stop(); engine = nil
            lastRecoveryAttempt = ProcessInfo.processInfo.systemUptime
            let suspended = note.userInfo?[AVAudioSessionInterruptionWasSuspendedKey] as? Bool ?? false
            onChange?(false,true,suspended ? "علّق iOS جلسة الصوت؛ نية الترجمة محفوظة" : "الصوت متوقف بسبب مقاطعة؛ نية الترجمة محفوظة")
        } else {
            let options = AVAudioSession.InterruptionOptions(rawValue:note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            interrupted = !options.contains(.shouldResume)
            if wanted && !interrupted { activate(); onRecovery?() }
            else { onChange?(false,interrupted,"بانتظار سماح النظام باستئناف الصوت") }
        }
    }
    func stop() {
        wanted = false; interrupted = false; engine?.stop(); engine = nil
        try? session.setActive(false,options:.notifyOthersOnDeactivation)
        onChange?(false,false,"تجربة الخلفية متوقفة")
    }
}
