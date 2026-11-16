import SwiftUI
import UniformTypeIdentifiers

enum GamePackDocument {
    static let type = UTType(exportedAs:"dev.gamelingo.glpack",conformingTo:.data)
    // The picker has no extension whitelist. Recognition/validation happens later.
    static let pickerTypes: [UTType] = [.item]
    static func accepts(_ url: URL) -> Bool {
        url.isFileURL
    }
}

@MainActor
final class GamePackLibrary: ObservableObject {
    let store: TranslationPackStore
    @Published var state = GamePackState()
    @Published var metrics = HybridMetrics()
    @Published var selfTestReport = ""
    func testPack() { store.selfTest { [weak self] in self?.selfTestReport = $0.summary } }
    @Published var busy = false
    @Published var message = ""
    @Published var inspection: LocalizationInspection?
    private let importer = GameTranslationImporter()
    private var importControl: LocalizationImportControl?
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
        guard GamePackDocument.accepts(url) else { message = "اختر ملفًا محليًا من تطبيق الملفات."; return false }
        busy = true; message = "جارٍ فحص الملف"; inspection = LocalizationInspection(filename:url.lastPathComponent)
        importControl = importer.start(url,store:store,update:{ [weak self] report in
            self?.inspection = report; self?.message = report.stage
        }) { [weak self] _,report in
            guard let self else { return }; self.busy = false; self.importControl = nil
            self.inspection = report; self.message = report.result
        }
        return true
    }
    func cancelImport() { importControl?.cancel(); message = "جارٍ إلغاء الاستيراد وتنظيف الملفات المؤقتة…" }
    var method: String {
        state.loaded ? "حزمة اللعبة المختارة ثم Argos عند الحاجة" : "Argos المحلي"
    }
}

struct GamePackLibraryView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var library: GamePackLibrary
    @State private var importing = false
    @State private var inboxFiles: [URL] = []
    @State private var inboxError = ""
    private let inbox = LocalizationInbox()
    var body: some View {
        Form {
            Section("طريقة الترجمة") {
                Text(library.method)
            if model.quality[.measurement] {
                Text(library.metrics.status(active:library.state.loaded,damaged:library.state.error != nil,threshold:model.quality.noHitThreshold))
                Text("المقام هو عدد معرّفات الحوار التي نُشرت للمرة الأولى منذ تفعيل اللعبة؛ لا يشمل محاولات OCR أو الاختبار الاصطناعي.").font(.footnote)
                ForEach(TranslationOrigin.allCases,id:\.rawValue) { origin in
                    LabeledContent(origin.title,value:String(library.metrics.origins[origin,default:0]))
                }
                Button("اختبار الحزمة · اصطناعي") { library.testPack() }.disabled(!library.state.loaded || model.running)
                if !library.selfTestReport.isEmpty { Text(library.selfTestReport).font(.footnote) }
            }
                if let game = library.state.registry.packs.first(where:{ $0.manifest.gameId == library.state.registry.selectedGame }) { LabeledContent("اللعبة المختارة",value:game.manifest.gameTitle) }
                else { Text("لم تُختر لعبة") }
                Button("Argos فقط / إلغاء اختيار اللعبة") { library.store.changeSelection(game:nil) }
                    .disabled(model.running || library.busy || library.state.registry.selectedGame == nil)
                Text("يُبحث في حزمة اللعبة التي تختارها فقط. عند غياب مطابقة موثوقة أو وجود أكثر من ترجمة محتملة، تُستخدم الترجمة المحلية تلقائيًا.").font(.footnote).foregroundColor(.secondary)
            }
            Section("الحزم") {
                Button("إضافة ملف تعريب") { importing = true }.disabled(model.running || library.busy).accessibilityIdentifier("gamePacks.import")
                if library.busy {
                    if let done = library.inspection?.progressDone, let total = library.inspection?.progressTotal, total > 0 {
                        ProgressView(value:Double(done),total:Double(total))
                        Text("\(done) / \(total) \(library.inspection?.progressUnit ?? "")").font(.caption)
                    } else { ProgressView() }
                }
                if let report = library.inspection { Text(report.filename+" · "+report.format).font(.caption).accessibilityIdentifier("gamePacks.fileSummary") }
                if !library.message.isEmpty { Text(library.message).accessibilityIdentifier("gamePacks.importStatus") }
                if library.busy { Button("إلغاء الاستيراد",role:.cancel) { library.cancelImport() }.accessibilityIdentifier("gamePacks.cancelImport") }
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
            if let report = library.inspection {
                Section("نتيجة فحص الملف") {
                    LabeledContent("الملف",value:report.filename)
                    LabeledContent("النوع من المحتوى",value:report.format)
                    LabeledContent("الحجم",value:ByteCountFormatter.string(fromByteCount:report.bytes,countStyle:.file))
                    LabeledContent("بيانات تعريب",value:answer(report.localization))
                    LabeledContent("تحليل الصيغة مدعوم",value:answer(report.supported))
                    LabeledContent("مقابلة الإنجليزية والعربية",value:answer(report.mapping))
                    if let count = report.usable { LabeledContent("المداخل القابلة للاستخدام",value:String(count)) }
                    if report.rejected > 0 { LabeledContent("مداخل مكررة أو غير صالحة استُبعدت",value:String(report.rejected)) }
                    if !report.requirement.isEmpty { Text(report.requirement) }
                    if !report.result.isEmpty { Text(report.result) }
                }
            }
            Section("الاستيراد من مجلد GameLingo") {
                Text("إذا عطّل مزوّد الملفات اختيار ملف، اضغط عليه مطولًا في «الملفات» وانسخه إلى «على الـiPhone الخاص بي ← GameLingo». حدّث القائمة هنا ثم اضغط اسم الملف؛ لا يعتمد هذا المسار على تصنيف امتداده.").font(.footnote)
                Button("تحديث ملفات المجلد") { refreshInbox() }.accessibilityIdentifier("gamePacks.refreshInbox")
                if !inboxError.isEmpty { Text(inboxError) }
                ForEach(inboxFiles,id:\.self) { file in
                    Button(file.lastPathComponent) { library.importFile(file,sessionRunning:model.running) }
                        .disabled(model.running || library.busy).accessibilityIdentifier("gamePacks.inbox."+file.lastPathComponent)
                }
            }
            Section("الاستيراد من الملفات") {
                Text("يمكن اختيار أي امتداد للفحص؛ الاختيار لا يعني نجاح التحويل. تُكتشف GLPACK وZIP من المحتوى. تُحوّل JSON وXML وCSV/TSV وPO التي تتضمن أزواجًا إنجليزية وعربية. المثبّتات والصيغ الأخرى قد تحتاج المحوّل الخارجي؛ لا يُشغّل التطبيق ملفات EXE.").font(.footnote)
                Text("تحفظ المكتبة الحزمة بعد التحقق. تبقى الحزمة السابقة عند فشل الفحص أو إلغائه؛ اختر اللعبة بعد الاستيراد لتفعيلها.").font(.footnote)
                Text("القوائم والمستندات تستخدم الحزمة عند المطابقة الكاملة عبر Smart Reading الذي تشغّله يدويًا. لا تُترجم الصور والأنسجة تلقائيًا.").font(.footnote)
                Text("GameLingo \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "؟") · البناء \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "؟")").font(.caption).accessibilityIdentifier("gamePacks.build")
            }
        }
        .navigationTitle("مكتبة ترجمات الألعاب")
        .onAppear { refreshInbox() }
        .sheet(isPresented:$importing) {
            LocalizationFilePicker(directory:inboxFiles.isEmpty ? nil : inbox.directory) { url in
                if let url { library.importFile(url,sessionRunning:model.running) }
                else { library.message = "أُلغي اختيار الملف؛ لم تتغير المكتبة" }
                importing = false
            }
        }
    }
    private func answer(_ value: Bool?) -> String { value.map{$0 ? "نعم" : "لا"} ?? "لم يُحدّد بعد" }
    private func refreshInbox() {
        do { inboxFiles = try inbox.files(); inboxError = "" }
        catch { inboxFiles = []; inboxError = "تعذر عرض المجلد أو تجاوز عدد ملفاته الحد؛ انقل الملفات المطلوبة فقط إلى GameLingo" }
    }
}

struct HybridStatisticsView: View {
    @ObservedObject var library: GamePackLibrary
    @EnvironmentObject var model: AppModel
    var body: some View {
        Section("حزمة اللعبة وArgos") {
            Text(library.method)
            if model.quality[.measurement] {
                Text(library.metrics.status(active:library.state.loaded,damaged:library.state.error != nil,threshold:model.quality.noHitThreshold))
                Text("المقام هو عدد معرّفات الحوار التي نُشرت للمرة الأولى منذ تفعيل اللعبة؛ لا يشمل محاولات OCR أو الاختبار الاصطناعي.").font(.footnote)
                ForEach(TranslationOrigin.allCases,id:\.rawValue) { origin in
                    LabeledContent(origin.rawValue,value:String(library.metrics.origins[origin,default:0]))
                }
                Button("اختبار الحزمة · اصطناعي") { library.testPack() }.disabled(!library.state.loaded || model.running)
                if !library.selfTestReport.isEmpty { Text(library.selfTestReport).font(.footnote) }
            }
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
