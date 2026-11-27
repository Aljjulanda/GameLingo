import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("الرئيسية",systemImage:"house") }
            NavigationStack { GamesView() }.tabItem { Label("الألعاب",systemImage:"gamecontroller") }
            NavigationStack { AppSettingsView() }.tabItem { Label("الإعدادات",systemImage:"gearshape") }
        }
        .tint(.teal)
        .overlay(alignment:.top) {
            SessionFeedbackBanner(feedback:model.feedback).padding(.horizontal,16).padding(.top,8)
        }
        .sheet(isPresented:$model.showingPackLibrary) {
            NavigationView {
                GamePackLibraryView(library:model.packLibrary)
                    .toolbar { ToolbarItem(placement:.cancellationAction) {
                        Button("إغلاق") { model.showingPackLibrary = false }
                    } }
            }.environmentObject(model)
        }
        .alert("GameLingo",isPresented:Binding(get:{ model.errorMessage != nil },set:{ if !$0 { model.errorMessage = nil } })) {
            Button("حسنًا") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

enum DeviceSettingsScope { case all, console, television }

struct ConnectionView: View {
    var scope = DeviceSettingsScope.all
    @EnvironmentObject var model: AppModel
    @State private var host = ""
    @State private var account = ""
    @State private var pin = ""
    var body: some View {
        Form {
                if scope != .television {
                Section("أجهزة PS5 المحفوظة") {
                    if model.consoles.isEmpty { Text("لا يوجد PS5 محفوظ. سجّل جهازك مرة واحدة أدناه.").foregroundColor(.secondary) }
                    ForEach(model.consoles) { console in
                        HStack {
                            Button { model.settings.selectedConsoleID = console.id } label: {
                                Label("\(console.name) · \(console.host)",systemImage:model.settings.selectedConsoleID == console.id ? "checkmark.circle.fill" : "circle")
                            }.disabled(model.running)
                            Spacer()
                            Button(role:.destructive) { model.removeConsole(console.id) } label: { Image(systemName:"trash") }
                                .accessibilityLabel("حذف الجهاز \(console.name)").disabled(model.running)
                        }.buttonStyle(.borderless)
                    }
                }
                Section("اكتشاف وتسجيل PS5") {
                    if model.consoles.isEmpty { registrationControls }
                    else { DisclosureGroup("تسجيل PS5 آخر") { registrationControls } }
                }
                }
                if model.loginRequired { PS5LoginSection() }
                if scope != .console {
                Section("اتصال التلفزيون") {
                    NavigationLink("مسح رمز QR على التلفزيون") { TVQRPairingView() }
                    Text(model.tvStatus)
                    Text("تُمنع مهلة القفل أثناء الاستماع. العمل خارج التطبيق يتطلب تفعيل تجربة الخلفية، ويظل خاضعًا لسماح iOS.").font(.footnote).foregroundColor(.secondary)
                    if !model.addresses.isEmpty {
                        Picker("عنوان iPhone",selection:$model.settings.localIP) { ForEach(model.addresses,id:\.self) { Text($0).tag($0) } }
                    }
                    Button("تحديث عناوين Wi-Fi") { model.refreshAddresses() }
                    Button("تشغيل اتصال التلفزيون / تجديد الرمز") { model.connectTV() }
                    if !model.pairingCode.isEmpty {
                        Text(model.pairingCode).font(.system(.title3,design:.monospaced)).textSelection(.enabled).environment(\.layoutDirection,.leftToRight)
                    }
                    Text("في تطبيق GameLingo TV الحالي، أدخل عنوان iPhone في حقل عنوان الكمبيوتر، ثم الرمز أعلاه. صلاحية الرمز 5 دقائق. عند التبديل بين Windows وiPhone أعد الاقتران بالمصدر المطلوب؛ لا تشغّلهما معًا.").font(.footnote).foregroundColor(.secondary)
                    if !model.tvDiagnostics.isEmpty {
                        DisclosureGroup("تشخيص اتصال التلفزيون") {
                            Text(model.tvDiagnostics.joined(separator:"\n")).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                        }
                        ShareLink(item:model.tvDiagnostics.joined(separator:"\n")) { Label("مشاركة التشخيص",systemImage:"square.and.arrow.up") }
                        Text("السجل لا يتضمن رمز الاقتران أو رموز المصادقة. قد يتضمن عناوين الشبكة المحلية.").font(.footnote).foregroundColor(.secondary)
                    }
                }
                }
        }.navigationTitle(scope == .console ? "جهاز PS5" : scope == .television ? "اتصال التلفزيون" : "الأجهزة والاتصال")
    }
    @ViewBuilder private var registrationControls: some View {
        Button("البحث في الشبكة") { model.discovered = []; model.remote.discover() }.disabled(model.running || model.pairing)
        ForEach(model.discovered) { item in Button("\(item.name) · \(item.host)") { host = item.host } }
        TextField("عنوان PS5 المحلي",text:$host).keyboardType(.decimalPad).environment(\.layoutDirection,.leftToRight)
        TextField("PSN Account ID · Base64",text:$account).textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection,.leftToRight)
        SecureField("رمز ربط PS5 من 8 أرقام",text:$pin).keyboardType(.numberPad)
        Button(model.pairing ? "جارٍ التسجيل…" : "تسجيل الجهاز") { model.pair(host:host,account:account,pin:pin); pin = ""; account = "" }.disabled(model.running || model.pairing)
        Text("رمز الربط: إعدادات PS5 ← النظام ← Remote Play ← ربط جهاز. Account ID هو المعرّف الرقمي للحساب بصيغة Base64؛ لا تُدخل كلمة مرور PSN. إذا لم يظهر الجهاز، أدخل عنوانه يدويًا وشغّله باليد.").font(.footnote).foregroundColor(.secondary)
    }
}

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    private var thermalTitle: String {
        switch model.thermal { case .nominal: return "طبيعية"; case .fair: return "مرتفعة قليلًا"; case .serious: return "مرتفعة"; case .critical: return "حرجة"; @unknown default: return "غير معروفة" }
    }
    var body: some View {
        Form {
                Section("القياسات الفعلية") {
                    metric("زمن OCR",model.metrics.ocrMilliseconds,suffix:"ms")
                    metric("زمن الترجمة",model.metrics.translationMilliseconds,suffix:"ms")
                    metric("الترجمة p95 · آخر 120 قياسًا",model.metrics.translationP95,suffix:"ms")
                    metric("OCR p95 · آخر 120 قياسًا",model.metrics.ocrP95,suffix:"ms")
                    LabeledContent("جمل السياق في الذاكرة",value:String(model.metrics.contextEntries))
                    LabeledContent("تأكيدات رسم جمل جديدة بالخلفية",value:String(model.backgroundDeliveries))
                    LabeledContent("بداية قياس الجلسة",value:model.sessionStarted.formatted(date:.omitted,time:.standard))
                    metric("معالجة الإطار حتى OCR",model.metrics.frameMilliseconds,suffix:"ms")
                    metric("حد أخذ العينات الحالي",model.metrics.samplingRate,suffix:"/s")
                    metric("متوسط OCR الفعلي منذ بدء الجلسة",model.metrics.actualOCRRate,suffix:"/s")
                    LabeledContent("الإطارات المعالجة",value:String(model.metrics.frames))
                    LabeledContent("إطارات أحدث حلّت محل القديمة",value:String(model.metrics.dropped))
                    LabeledContent("مهام الترجمة النشطة والمعلقة",value:String(model.metrics.queueDepth))
                }
                Section("استرداد PS5 · أحداث مؤكدة") {
                    LabeledContent("محاولات إعادة اتصال PS5",value:String(model.remoteMetrics.attempts))
                    LabeledContent("إعادات اتصال PS5 الناجحة",value:String(model.remoteMetrics.successes))
                    LabeledContent("محاولات إعادة الاتصال الفاشلة",value:String(model.remoteMetrics.failures))
                    LabeledContent("حوادث غياب الإطارات",value:String(model.remoteMetrics.starvations))
                    LabeledContent("طلبات إصلاح فك الترميز",value:String(model.remoteMetrics.decoderRequests))
                    LabeledContent("مقاطعات الصوت",value:String(model.audioInterruptions))
                    LabeledContent("انقطاعات الشبكة",value:String(model.networkInterruptions))
                    LabeledContent("مؤشر التراجع الحالي · ليس عدد انقطاعات",value:String(model.recoveryAttempts))
                    metric("عمر اتصال PS5 الحالي",model.remoteMetrics.uptime,suffix:"s")
                    if let age = model.remoteMetrics.decodedFrameAge { metric("عمر آخر إطار مفكوك",age,suffix:"s") }
                    if let age = model.remoteMetrics.encodedFrameAge { metric("عمر آخر إطار وارد",age,suffix:"s") }
                    if model.remoteMetrics.successes>0 { metric("زمن محاولة الاتصال الناجحة",model.remoteMetrics.lastRecoverySeconds,suffix:"s") }
                    DisclosureGroup("تشخيص الجلسة · دون مفاتيح أو رموز") {
                        Text(model.sessionDiagnostics.joined(separator:"\n")).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                    }
                }
                Section("الحوار والمتحدثون") {
                    LabeledContent("قراءات حوار مكررة تم تجاهلها",value:String(model.metrics.duplicatesSuppressed))
                    LabeledContent("تصحيحات OCR مدمجة",value:String(model.metrics.correctionsMerged))
                    LabeledContent("قراءات اسم متحدث مقبولة",value:String(model.metrics.speakersDetected))
                    LabeledContent("تسميات اسم غير مؤكدة",value:String(model.metrics.speakersUncertain))
                    if model.quality[.speakerClassification] {
                        LabeledContent("تسميات مؤكدة أُخفي اسمها",value:String(model.metrics.speakerHidden))
                    }
                    if !model.metrics.nameConfidence.isEmpty { Text(model.metrics.nameConfidence).font(.caption) }
                    DisclosureGroup("تتبع مواضع الترقيم · بلا نصوص") {
                        Text(model.metrics.punctuationTrace).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                        if !model.tvRenderSignature.isEmpty { Text(model.tvRenderSignature).font(.system(.caption,design:.monospaced)).textSelection(.enabled) }
                        Text("مواضع العلامات في ترتيب النص واتجاه أول حرف قوي عبر مراحل الترجمة، واتجاه الفقرة المرسومة عند دعمه؛ لا يتضمن نص الحوار.").font(.footnote)
                    }
                }
                HybridStatisticsView(library:model.packLibrary)
                Section("النظام") {
                    metric("CPU · 100% تعني نواة واحدة",model.cpuPercent,suffix:"%")
                    metric("ذاكرة العملية RSS",model.residentMegabytes,suffix:"MB")
                    if let used = model.batteryUsed { metric("انخفاض نسبة البطارية منذ البدء",used,suffix:"%") }
                    Text(model.audioStatus).font(.footnote)
                    ShareLink(item:model.performanceSnapshot) { Label("مشاركة قياسات الجلسة",systemImage:"square.and.arrow.up") }
                    LabeledContent("الشبكة",value:model.networkStatus)
                    LabeledContent("الحالة الحرارية",value:thermalTitle)
                    LabeledContent("الذاكرة المتاحة للعملية",value:String(format:"%.0f MB",Double(model.availableMemory)/1048576))
                    LabeledContent("وضع الأداء",value:model.settings.mode.title)
                    Text("تصفّر القياسات حتى وصول إطارات حقيقية. تُخفّض العينات عند الحرارة أو وضع الطاقة المنخفضة، وتتوقف الجلسة عند الحرارة الحرجة.").font(.footnote).foregroundColor(.secondary)
                    Text("تجربة الصوت الصامت اختيارية ولا تضمن استمرار التنفيذ. تأكيد الرسم يصل من تطبيق TV المتوافق، ولا يغني عن التحقق من ظهور حوار جديد فعليًا أثناء القفل. قياسات البطارية تقريبية وليست اختبار طاقة مخبريًا.").font(.footnote).foregroundColor(.secondary)
                }
                Section("تكلفة Smart Reading · عند الطلب فقط") {
                    metric("OCR للمستند",model.metrics.documentOCRMilliseconds,suffix:"ms")
                    metric("مجموع ترجمة المستند",model.metrics.documentTranslationMilliseconds,suffix:"ms")
                    metric("الزمن الكلي للمستند",model.metrics.documentMilliseconds,suffix:"ms")
                    metric("زيادة RSS المرصودة أثناء العمل",model.metrics.documentExtraMegabytes,suffix:"MB")
                    Text("قياسات مرصودة للعملية، وليست قياسًا لمعدل استهلاك البطارية أو ضمانًا لالتقاط كل ذروة ذاكرة. لا يُقاس GPU هنا.").font(.footnote).foregroundColor(.secondary)
                }
        }.navigationTitle("التشخيص والقياسات")
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
