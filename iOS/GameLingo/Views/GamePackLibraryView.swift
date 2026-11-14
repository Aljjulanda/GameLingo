import SwiftUI
import UniformTypeIdentifiers

enum GamePackDocument {
    static let type = UTType(exportedAs:"dev.gamelingo.glpack",conformingTo:.data)
    // Download/iCloud providers can retain a dynamic or generic type for .glpack.
    // Let users select those files; the importer verifies extension and contents.
    static let pickerTypes: [UTType] = [.item]
    static func accepts(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.caseInsensitiveCompare("glpack") == .orderedSame
    }
}

@MainActor
final class GamePackLibrary: ObservableObject {
    let store: TranslationPackStore
    @Published var state = GamePackState()
    @Published var metrics = HybridMetrics()
    @Published var busy = false
    @Published var message = ""
    var onNamesChanged: ((String) -> Void)?
    init(store: TranslationPackStore = TranslationPackStore()) {
        self.store = store
        store.onChange = { [weak self] value in
            guard let self else { return }; self.state = value
            let active = value.loaded ? value.registry.packs.first { $0.manifest.gameId == value.registry.selectedGame && $0.enabled } : nil
            self.onNamesChanged?((active?.manifest.speakerNames ?? []).joined(separator:","))
        }
    }
    func refreshMetrics() { store.sampleMetrics { [weak self] in self?.metrics = $0 } }
    @discardableResult
    func importFile(_ url: URL, sessionRunning: Bool = false) -> Bool {
        guard !sessionRunning else { message = "أوقف جلسة الترجمة قبل إضافة حزمة؛ ثم افتح الملف مجددًا."; return false }
        guard !busy else { message = "انتظر اكتمال استيراد الحزمة الحالية."; return false }
        guard GamePackDocument.accepts(url) else { message = "اختر ملف حزمة ترجمة بامتداد ‎.glpack من تطبيق الملفات."; return false }
        busy = true; message = "جارٍ التحقق من الحزمة واستيرادها…"
        store.importPack(url) { [weak self] result in
            guard let self else { return }; self.busy = false
            switch result {
            case .success: self.message = "تم استيراد الحزمة والتحقق منها؛ اختر اللعبة لتفعيلها"
            case .failure(let error): self.message = (error as? PackFailure)?.localizedDescription ?? "تعذر استيراد الحزمة؛ بقيت المكتبة السابقة محفوظة"
            }
        }
        return true
    }
    var method: String {
        state.loaded ? "حزمة اللعبة المختارة ثم Argos عند الحاجة" : "Argos المحلي"
    }
}

struct GamePackLibraryView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var library: GamePackLibrary
    @State private var importing = false
    var body: some View {
        Form {
            Section("طريقة الترجمة") {
                Text(library.method)
                if let game = library.state.registry.packs.first(where:{ $0.manifest.gameId == library.state.registry.selectedGame }) { LabeledContent("اللعبة المختارة",value:game.manifest.gameTitle) }
                else { Text("لم تُختر لعبة") }
                Button("Argos فقط / إلغاء اختيار اللعبة") { library.store.changeSelection(game:nil) }
                    .disabled(model.running || library.busy || library.state.registry.selectedGame == nil)
                Text("يُبحث في حزمة اللعبة التي تختارها فقط. عند غياب مطابقة موثوقة أو وجود أكثر من ترجمة محتملة، تُستخدم الترجمة المحلية تلقائيًا.").font(.footnote).foregroundColor(.secondary)
            }
            Section("الحزم") {
                Button("إضافة حزمة ترجمة / تحديث حزمة") { importing = true }.disabled(model.running || library.busy)
                if library.busy { ProgressView() }
                if !library.message.isEmpty { Text(library.message) }
                if let error = library.state.error { Text(error).foregroundColor(.orange) }
                if model.running { Text("أوقف جلسة الترجمة لتغيير اللعبة أو الحزم.").font(.footnote) }
                ForEach(library.state.registry.packs) { pack in
                    NavigationLink {
                        Form {
                            Section("معلومات الحزمة") {
                                Text(pack.manifest.gameTitle).font(.headline)
                                LabeledContent("اللغات",value:"English → العربية")
                                LabeledContent("نسخة الحزمة",value:pack.manifest.packVersion)
                                LabeledContent("التغطية",value:pack.manifest.coverage == "partial" ? "جزئية" : "غير مقاسة")
                                LabeledContent("المداخل القابلة للبحث",value:"\(pack.manifest.usableCount)")
                                LabeledContent("إجمالي المداخل",value:"\(pack.manifest.recordCount)")
                                LabeledContent("الحجم المثبت",value:ByteCountFormatter.string(fromByteCount:pack.bytes,countStyle:.file))
                                Text("تم فحص البنية والسلامة عند الاستيراد. قد تُرفض بعض المداخل أثناء البحث بسبب الغموض؛ الفحص لا يثبت جودة الترجمة أو مصدرها البشري.").font(.footnote)
                            }
                            Section("التفعيل") {
                                Toggle("تفعيل الحزمة",isOn:Binding(get:{ library.state.registry.packs.first(where:{$0.id == pack.id})?.enabled ?? false },set:{ library.store.enable(pack.id,$0) }))
                                Button("اختيار هذه اللعبة") { library.store.changeSelection(game:pack.manifest.gameId) }
                                Button("حذف الحزمة",role:.destructive) { library.store.remove(pack.id) }
                            }.disabled(model.running || library.busy)
                            Section("المصدر والإذن") { Text(pack.manifest.attribution); Text(pack.manifest.permission) }
                        }.navigationTitle("معلومات الترجمة")
                    } label: {
                        VStack(alignment:.leading) {
                            Label(pack.manifest.gameTitle,systemImage:library.state.registry.selectedGame == pack.manifest.gameId ? "checkmark.circle.fill" : "gamecontroller")
                            Text("\(pack.manifest.packVersion) · \(pack.manifest.usableCount) مدخل · \(pack.enabled ? "مفعّلة" : "معطّلة")").font(.caption)
                        }
                    }
                }
            }
            Section("الاستيراد من الملفات") {
                Text("احفظ ملف ‎.glpack في تطبيق الملفات، ثم أضفه هنا أو افتحه باستخدام GameLingo. يمكن اختيار الملفات حتى إن لم يتعرّف iOS على نوعها؛ لن تُقبل إلا حزمة سليمة. تُنسخ الحزمة إلى GameLingo؛ لن تحتاج بقاء الملف الأصلي أو وجود كمبيوتر أثناء اللعب. استيراد حزمة لنفس اللعبة يحدّثها بعد التحقق، ويحتفظ بالاختيار والتفعيل.").font(.footnote)
                Text("القوائم والمستندات تستخدم الحزمة عند المطابقة الكاملة عبر Smart Reading الذي تشغّله يدويًا. لا تُترجم الصور والأنسجة تلقائيًا.").font(.footnote)
            }
        }
        .navigationTitle("مكتبة ترجمات الألعاب")
        .fileImporter(isPresented:$importing,allowedContentTypes:GamePackDocument.pickerTypes) { result in
            switch result { case .success(let url): library.importFile(url,sessionRunning:model.running); case .failure: library.message = "لم يُستورد ملف" }
        }
    }
}

struct HybridStatisticsView: View {
    @ObservedObject var library: GamePackLibrary
    var body: some View {
        Section("حزمة اللعبة وArgos") {
            Text(library.method)
            LabeledContent("أحداث الحوار",value:String(library.metrics.dialogueEvents))
            LabeledContent("عمليات بحث الحزمة",value:String(library.metrics.lookups))
            LabeledContent("مطابقات / رجوع إلى Argos",value:"\(library.metrics.matches) / \(library.metrics.fallbacks)")
            LabeledContent("مطابقات غامضة رُفضت",value:String(library.metrics.ambiguous))
            LabeledContent("طلبات Argos",value:String(library.metrics.argos))
            LabeledContent("مطابقة حرفية / بعد التطبيع",value:"\(library.metrics.exact) / \(library.metrics.normalized)")
            LabeledContent("مطابقة تقريبية آمنة",value:String(library.metrics.approximate))
            LabeledContent("بحث الحزمة · المتوسط / p95",value:"\(NumericInput.format(library.metrics.average)) / \(NumericInput.format(library.metrics.samples.p95)) ms")
            Text("البحث التقريبي معطّل في هذا الإصدار لحماية المعنى. الإحصاءات بلا سجل دائم للحوار.").font(.footnote)
        }
    }
}
