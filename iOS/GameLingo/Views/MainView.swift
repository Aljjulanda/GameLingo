import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView {
            ConnectionView().tabItem { Label("الاتصال",systemImage:"antenna.radiowaves.left.and.right") }
            TranslationView().tabItem { Label("الترجمة",systemImage:"character.bubble") }
            SubtitleSettingsView().tabItem { Label("الترجمة المرئية",systemImage:"captions.bubble") }
            PerformanceView().tabItem { Label("الأداء",systemImage:"gauge") }
        }
        .tint(.teal)
        .alert("GameLingo",isPresented:Binding(get:{ model.errorMessage != nil },set:{ if !$0 { model.errorMessage = nil } })) {
            Button("حسنًا") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct ConnectionView: View {
    @EnvironmentObject var model: AppModel
    @State private var host = ""
    @State private var account = ""
    @State private var pin = ""
    @State private var loginPIN = ""
    var body: some View {
        NavigationView {
            Form {
                Section("الجلسة") {
                    Text(model.remoteStatus)
                    Button { model.running ? model.stop() : model.start() } label: {
                        Label(model.running ? "إيقاف الترجمة" : "بدء الترجمة",systemImage:model.running ? "stop.fill" : "play.fill")
                    }
                        .disabled(!model.running && (!model.modelReady || model.pairing))
                    Text("اترك التطبيق مفتوحًا. شغّل اللعبة واليد بحسابك المعتاد، واستخدم حسابًا ثانيًا لبث Remote Play.").font(.footnote).foregroundColor(.secondary)
                    Toggle("تعتيم الشاشة أثناء الجلسة",isOn:$model.settings.dimScreen)
                }
                Section("أجهزة PS5 المحفوظة") {
                    ForEach(model.consoles) { console in
                        HStack {
                            Button { model.settings.selectedConsoleID = console.id } label: {
                                Label("\(console.name) · \(console.host)",systemImage:model.settings.selectedConsoleID == console.id ? "checkmark.circle.fill" : "circle")
                            }.disabled(model.running)
                            Spacer()
                            Button(role:.destructive) { model.removeConsole(console.id) } label: { Image(systemName:"trash") }
                        }
                    }
                }
                Section("اكتشاف وتسجيل PS5") {
                    Button("البحث في الشبكة") { model.discovered = []; model.remote.discover() }.disabled(model.running || model.pairing)
                    ForEach(model.discovered) { item in Button("\(item.name) · \(item.host)") { host = item.host } }
                    TextField("عنوان PS5 المحلي",text:$host).keyboardType(.decimalPad).environment(\.layoutDirection,.leftToRight)
                    TextField("PSN Account ID · Base64",text:$account).textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection,.leftToRight)
                    SecureField("رمز ربط PS5 من 8 أرقام",text:$pin).keyboardType(.numberPad)
                    Button(model.pairing ? "جارٍ التسجيل…" : "تسجيل الجهاز") { model.pair(host:host,account:account,pin:pin); pin = ""; account = "" }.disabled(model.running || model.pairing)
                    Text("رمز الربط: إعدادات PS5 ← النظام ← Remote Play ← ربط جهاز. Account ID هو المعرّف الرقمي للحساب بصيغة Base64؛ لا تُدخل كلمة مرور PSN. إذا لم يظهر الجهاز، أدخل عنوانه يدويًا وشغّله باليد.").font(.footnote).foregroundColor(.secondary)
                }
                if model.loginRequired {
                    Section("رمز تسجيل دخول PS5") {
                        SecureField("4 أرقام",text:$loginPIN).keyboardType(.numberPad)
                        Button("إرسال الرمز") {
                            do { try model.remote.loginPIN(loginPIN); model.loginRequired = false; loginPIN = "" }
                            catch { model.errorMessage = error.localizedDescription }
                        }
                    }
                }
                Section("اتصال TCL") {
                    Text(model.tvStatus)
                    if !model.addresses.isEmpty {
                        Picker("عنوان iPhone",selection:$model.settings.localIP) { ForEach(model.addresses,id:\.self) { Text($0).tag($0) } }
                    }
                    Button("تحديث عناوين Wi-Fi") { model.refreshAddresses() }
                    Button("تشغيل اتصال التلفزيون / تجديد الرمز") { model.connectTV() }
                    if !model.pairingCode.isEmpty {
                        Text(model.pairingCode).font(.system(.title3,design:.monospaced)).textSelection(.enabled).environment(\.layoutDirection,.leftToRight)
                    }
                    Text("في تطبيق GameLingo TV الحالي، أدخل عنوان iPhone في حقل عنوان الكمبيوتر، ثم الرمز أعلاه. صلاحية الرمز 5 دقائق. عند التبديل بين Windows وiPhone أعد الاقتران بالمصدر المطلوب؛ لا تشغّلهما معًا.").font(.footnote).foregroundColor(.secondary)
                }
            }.navigationTitle("GameLingo")
        }.navigationViewStyle(.stack)
    }
}

struct TranslationView: View {
    @EnvironmentObject var model: AppModel
    @State private var importing = false
    var body: some View {
        NavigationView {
            Form {
                Section("اللغات") { LabeledContent("المصدر",value:"English"); LabeledContent("الهدف",value:"العربية") }
                Section("النموذج المحلي") {
                    Text(model.modelStatus)
                    if model.modelBusy { ProgressView() }
                    Button("تنزيل نموذج EN → AR") { model.downloadModel() }.disabled(model.modelBusy || model.running)
                    Button("استيراد حزمة .argosmodel") { importing = true }.disabled(model.modelBusy || model.running)
                    Button("تحميل النموذج المثبت") { model.loadModel() }.disabled(model.modelBusy || model.running)
                    Button("حذف النموذج",role:.destructive) { model.removeModel() }.disabled(model.modelBusy || model.running)
                    Text("تُجرى الترجمة على iPhone بعد تثبيت النموذج. لا توجد خدمة ترجمة سحابية أو سجل حوار. الحزمة هي نموذج Windows نفسه؛ راجع نسبته وشروطه قبل إعادة توزيعه.").font(.footnote).foregroundColor(.secondary)
                }
                Section("قراءة الحوار") {
                    Text(model.running ? "OCR والترجمة يعملان عند وصول إطارات PS5" : "OCR متوقف")
                    Picker("وضع الأداء",selection:$model.settings.mode) { ForEach(PerformanceMode.allCases,id:\.self) { Text($0.title).tag($0) } }
                    Text("منطقة القراءة كنسبة من الصورة؛ الأصل أعلى اليسار. أوقف الجلسة قبل تعديلها.").font(.footnote)
                    roiControl("X",keyPath:\.x); roiControl("Y",keyPath:\.y)
                    roiControl("العرض",keyPath:\.w); roiControl("الارتفاع",keyPath:\.h)
                    Text(model.settings.roi.isValid ? "منطقة صالحة" : "المنطقة تتجاوز حدود الصورة").foregroundColor(model.settings.roi.isValid ? .secondary : .red)
                    Button("استعادة منطقة الحوار الافتراضية") { model.settings.roi = .dialogue }.disabled(model.running)
                }
                Section { NavigationLink("المصادر والتراخيص") { LegalView() } }
            }.navigationTitle("الترجمة")
                .fileImporter(isPresented:$importing,allowedContentTypes:[.data],allowsMultipleSelection:false) { result in
                    switch result { case .success(let urls): if let url = urls.first { model.importModel(url) }; case .failure(let error): model.errorMessage = error.localizedDescription }
                }
        }.navigationViewStyle(.stack)
    }
    private func roiControl(_ title: String,keyPath: WritableKeyPath<SourceBox,Double>) -> some View {
        VStack(alignment:.leading) {
            Text("\(title): \(model.settings.roi[keyPath:keyPath],specifier:"%.2f")")
            Slider(value:Binding(get:{ model.settings.roi[keyPath:keyPath] },set:{ model.settings.roi[keyPath:keyPath] = $0 }),in:0...1,step:0.01).disabled(model.running)
        }
    }
}

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    private var thermalTitle: String {
        switch model.thermal { case .nominal: return "طبيعية"; case .fair: return "مرتفعة قليلًا"; case .serious: return "مرتفعة"; case .critical: return "حرجة"; @unknown default: return "غير معروفة" }
    }
    var body: some View {
        NavigationView {
            Form {
                Section("القياسات الفعلية") {
                    metric("زمن OCR",model.metrics.ocrMilliseconds,suffix:"ms")
                    metric("زمن الترجمة",model.metrics.translationMilliseconds,suffix:"ms")
                    metric("معالجة الإطار حتى OCR",model.metrics.frameMilliseconds,suffix:"ms")
                    metric("حد أخذ العينات الحالي",model.metrics.samplingRate,suffix:"/s")
                    metric("متوسط OCR الفعلي منذ بدء الجلسة",model.metrics.actualOCRRate,suffix:"/s")
                    LabeledContent("الإطارات المعالجة",value:String(model.metrics.frames))
                    LabeledContent("إطارات أحدث حلّت محل القديمة",value:String(model.metrics.dropped))
                    LabeledContent("مهام الترجمة النشطة والمعلقة",value:String(model.metrics.queueDepth))
                }
                Section("النظام") {
                    LabeledContent("الشبكة",value:model.networkStatus)
                    LabeledContent("الحالة الحرارية",value:thermalTitle)
                    LabeledContent("الذاكرة المتاحة للعملية",value:String(format:"%.0f MB",Double(model.availableMemory)/1048576))
                    LabeledContent("وضع الأداء",value:model.settings.mode.title)
                    Text("تصفّر القياسات حتى وصول إطارات حقيقية. تُخفّض العينات عند الحرارة أو وضع الطاقة المنخفضة، وتتوقف الجلسة عند الحرارة الحرجة.").font(.footnote).foregroundColor(.secondary)
                    Text("يجب أن يبقى التطبيق في المقدمة. قفل iPhone أو مغادرة التطبيق يوقف الجلسة؛ التعتيم لا يحوّلها إلى تشغيل في الخلفية.").font(.footnote).foregroundColor(.secondary)
                }
            }.navigationTitle("الأداء")
        }.navigationViewStyle(.stack)
    }
    private func metric(_ name: String,_ value: Double,suffix: String) -> some View { LabeledContent(name,value:String(format:"%.1f %@",value,suffix)) }
}

struct LegalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("GameLingo iOS مشتق جزئيًا من Chiaki/chiaki-ng وTP Play. مرخّص تحت AGPL v3 مع إذن OpenSSL الإضافي. يُقدّم دون ضمان. احتفظ بالمصدر وتعليمات البناء والتراخيص عند إعادة التوزيع.")
                Text("الترجمة تستخدم CTranslate2 وSentencePiece وحزمة Argos EN–AR. لا يُضمّن نموذج اللغة في التطبيق؛ يتم تنزيله من مصدره الأصلي أو استيراده.")
                Text("تطبيق مستقل وغير معتمد من Sony. أسماء PlayStation والعلامات الأخرى تخص أصحابها.")
                Text((try? String(contentsOf:Bundle.main.url(forResource:"ThirdPartyNotices",withExtension:"txt")!,encoding:.utf8)) ?? "تتوفر التراخيص مع المصدر.").font(.footnote).environment(\.layoutDirection,.leftToRight)
            }.padding()
        }.navigationTitle("المصادر والتراخيص")
    }
}
