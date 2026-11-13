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
    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] note in
            Task { @MainActor [weak self] in self?.interruption(note) }
        })
        observers.append(center.addObserver(forName:AVAudioSession.mediaServicesWereResetNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }; self.engine = nil
                self.onChange?(false,self.interrupted,"أُعيدت خدمات الصوت")
                if self.wanted && !self.interrupted { self.activate(); self.onRecovery?() }
            }
        })
        observers.append(center.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wanted, !self.interrupted else { return }
                if self.engine?.isRunning != true { self.activate() }
                self.onRecovery?()
            }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func start() { wanted = true; if !interrupted { activate() } }
    func recover(foreground: Bool = false) {
        guard wanted else { return }
        // Foreground reactivation is an additional opportunity if the system did
        // not deliver interruption-ended. Never contend with another audible app.
        if foreground && !session.isOtherAudioPlaying { interrupted = false }
        if !interrupted && engine?.isRunning != true { activate() }
    }
    private func activate() {
        guard wanted, !interrupted, engine?.isRunning != true else { return }
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
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue:raw) else { return }
        if type == .began {
            interrupted = true; engine?.stop(); engine = nil
            onChange?(false,true,"الصوت متوقف بسبب مقاطعة؛ نية الترجمة محفوظة")
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
