import SwiftUI
import VisionKit

struct TVQRPairingView: View {
    @EnvironmentObject var model: AppModel
    @State private var invitation: QRBootstrap?
    @State private var busy = false
    @State private var status = "افتح QR مؤقتًا من GameLingo TV، ثم امسحه هنا."
    @State private var fingerprint = ""
    @State private var task: Task<Void,Never>?
    var body: some View {
        VStack(spacing:16) {
            Text(status).padding()
            if let invitation {
                Text("TV: \(invitation.name)").font(.headline)
                Text("بصمة جلسة TV: \(invitation.fingerprint.suffix(12))").font(.caption.monospaced())
                if !fingerprint.isEmpty { Text("بصمة الآيفون للمقارنة على TV: \(fingerprint)").font(.caption.monospaced()) }
                Button("تأكيد التلفزيون وإرسال طلب الاقتران") {
                    busy = true; status = "جارٍ الاتصال المشفر؛ وافق على هوية الآيفون على TV."
                    model.hub.prepareQRBootstrap { result in
                        switch result {
                        case .failure(let error): busy = false; status = error.localizedDescription
                        case .success(let (host,code)):
                            fingerprint = String(code.prefix(64).suffix(12))
                            task = Task {
                                do { try await QRBootstrapClient(invitation).exchange(phone:host,code:code,name:UIDevice.current.name); status = "قُبل الاقتران؛ جارٍ اتصال TV بمصدر الترجمة. يُحفظ الاقتران تلقائيًا بعد المصادقة." }
                                catch { status = error.localizedDescription }
                                busy = false
                            }
                        }
                    }
                }.disabled(busy || !model.tvListening)
                Button("مسح رمز جديد") { task?.cancel(); self.invitation = nil; fingerprint = "" }.disabled(busy)
            } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRScanner { value in
                    do { invitation = try QRBootstrap.decode(value,now:TVHub.now()); return true }
                    catch { status = error.localizedDescription; return false }
                }.frame(minHeight:280)
            } else { Text("الكاميرا غير متاحة؛ فعّل إذن الكاميرا أو استخدم الإدخال اليدوي من شاشة الاتصال.") }
            if busy { ProgressView() }
            Text("QR للجلسة الحالية فقط، بلا أسرار اقتران دائمة. لا حاجة لمسحه مجددًا بعد حفظ الاقتران. كلا الجهازين على الشبكة المحلية.").font(.footnote).padding()
        }.navigationTitle("اقتران TV عبر QR")
            .onAppear { if !model.tvListening { model.connectTV() } }.onDisappear { task?.cancel() }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    var recognized: (String) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(recognized) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes:[.barcode(symbologies:[.qr])],qualityLevel:.balanced,recognizesMultipleItems:false,isHighFrameRateTrackingEnabled:false,isHighlightingEnabled:true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning(); return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let recognized: (String) -> Bool
        private var delivered = false
        init(_ recognized: @escaping (String) -> Bool) { self.recognized = recognized }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for case .barcode(let code) in addedItems { if let value = code.payloadStringValue, recognized(value) { delivered = true; scanner.stopScanning(); break } }
        }
    }
}
