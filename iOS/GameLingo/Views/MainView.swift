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
                    Text("التشغيل الافتراضي في المقدمة؛ تجربة الخلفية من تبويب الترجمة. شغّل اللعبة واليد بحسابك المعتاد، واستخدم حسابًا ثانيًا لبث Remote Play.").font(.footnote).foregroundColor(.secondary)
                    Toggle("تعتيم الشاشة أثناء الجلسة",isOn:$model.settings.dimScreen)
                    if model.running {
                        Button("Smart Reading · قراءة النص الظاهر") { model.smartRead() }
                            .disabled(!model.streamConnected || !model.tvConnected || !model.tvDocuments || model.readingActive)
                        if model.readingActive {
                            Text(model.readingStatus)
                            if !model.readingPages.isEmpty {
                                HStack {
                                    Button("السابقة") { model.moveReadingPage(-1) }.disabled(model.readingPage==0)
                                    Text("\(model.readingPage+1) / \(model.readingPages.count)")
                                    Button("التالية") { model.moveReadingPage(1) }.disabled(model.readingPage+1>=model.readingPages.count)
                                }.buttonStyle(.bordered)
                            }
                            Button("إغلاق القراءة والعودة للحوار") { model.closeReading() }
                        }
                    }
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
                Section("حزم الألعاب") {
                    NavigationLink("مكتبة ترجمات الألعاب") { GamePackLibraryView(library:model.packLibrary) }.accessibilityIdentifier("gamePacks.library")
                }
                QualitySettingsSection()
                Section("تشغيل الجلسة والخلفية") {
                    Toggle("تجربة الصوت الصامت في الخلفية",isOn:$model.settings.advanced.backgroundAudio)
                        .onChange(of:model.settings.advanced.backgroundAudio) { _ in model.updateBackgroundExperiment() }
                    Text(model.sessionStatus)
                    Text(model.audioStatus).font(.footnote)
                    Text("اختياري وتجريبي. لا يشغّل صوت PS5 ولا يعرض الفيديو. قد يعلّق iOS التطبيق أو يمنع الاستئناف أثناء القفل. نجاح التجربة يُقاس بوصول جمل جديدة إلى TCL؛ ظهور جلسة صوت لا يثبت ذلك.").font(.footnote).foregroundColor(.secondary)
                }
                Section("ذاكرة السياق والمصطلحات") {
                    Toggle("ذاكرة سياق مؤقتة",isOn:$model.settings.advanced.contextEnabled)
                    PreciseNumberControl(title:"عدد الجمل السابقة",value:Binding(get:{ Double(model.settings.advanced.contextCapacity) },set:{ model.settings.advanced.contextCapacity = Int($0) }),range:1...20,defaultValue:5,integer:true)
                    Text("المحرك: Argos المحلي السريع. زيادة الذاكرة لا تضمن تحسن الترجمة؛ تؤثر الذاكرة عند مطابقة قاعدة سياق تضيفها أدناه.").font(.footnote).foregroundColor(.secondary)
                    TextField("أسماء موثوقة إضافية، مفصولة بفواصل",text:Binding(get:{ model.settings.advanced.speakerNames },set:{ model.settings.advanced.speakerNames = String($0.prefix(2000)) }),axis:.vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection,.leftToRight)
                    Text("يمكن ترك القائمة فارغة؛ تُكتشف التسميات الواضحة تلقائيًا، وتساعد القائمة مع أسماء خاصة أو غير واضحة.").font(.footnote)
                    TextEditor(text:Binding(get:{ model.settings.advanced.terminology },set:{ model.settings.advanced.terminology = String($0.prefix(8000)) }))
                        .frame(minHeight:110).textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection,.leftToRight)
                    Text("قواعد اختيارية، سطر لكل قاعدة:\nWait! = انتظر!\nriver | Go to the bank. = اذهب إلى ضفة النهر.\nالجزء قبل | شرط وجود كلمة في السياق السابق. تُطابق القاعدة الجملة الحالية كاملة. لا تُحفظ محادثاتك على القرص.").font(.footnote).foregroundColor(.secondary)
                }
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
                    Text(model.running ? model.sessionStatus : "OCR متوقف")
                    Picker("وضع الأداء",selection:$model.settings.mode) { ForEach(PerformanceMode.allCases,id:\.self) { Text($0.title).tag($0) } }
                    Text("منطقة القراءة كنسبة من الصورة؛ الأصل أعلى اليسار. أوقف الجلسة قبل تعديلها.").font(.footnote)
                    roiControl("X",keyPath:\.x); roiControl("Y",keyPath:\.y)
                    roiControl("العرض",keyPath:\.w); roiControl("الارتفاع",keyPath:\.h)
                    Text(model.settings.roi.isValid ? "منطقة صالحة" : "المنطقة تتجاوز حدود الصورة").foregroundColor(model.settings.roi.isValid ? .secondary : .red)
                    Button("استعادة منطقة الحوار الافتراضية") { model.settings.roi = .dialogue }.disabled(model.running)
                }
                Section("Smart Reading · القراءة عند الطلب") {
                    Button("قراءة النص الظاهر في اللعبة") { model.smartRead() }
                        .disabled(!model.running || !model.streamConnected || !model.tvConnected || !model.tvDocuments || model.readingActive)
                    Text(model.readingStatus)
                    if model.tvConnected && !model.tvDocuments { Text("تحتاج هذه الميزة تحديث تطبيق التلفزيون.").font(.footnote) }
                    if model.readingActive {
                        if model.readingPages.isEmpty {
                            ProgressView()
                            if model.metrics.documentTotal>0 { Text("ترجمة الجزء \(model.metrics.documentCompleted) من \(model.metrics.documentTotal)") }
                        }
                        else {
                            Text("الصفحة \(model.readingPage+1) من \(model.readingPages.count)")
                            HStack {
                                Button("السابقة") { model.moveReadingPage(-1) }.disabled(model.readingPage == 0)
                                Spacer()
                                Button("التالية") { model.moveReadingPage(1) }.disabled(model.readingPage+1 >= model.readingPages.count)
                            }
                        }
                        Button("إغلاق القراءة والعودة للحوار") { model.closeReading() }
                    }
                    Text("يتوقف نشر الحوار مؤقتًا وتُقرأ صفحة اللعبة الظاهرة من إطار جديد فقط. لا توجد صورة مجمدة أو أرشيف مستندات. للمستند متعدد صفحات اللعبة، اعرض الصفحة المطلوبة ثم أعد القراءة.").font(.footnote).foregroundColor(.secondary)
                }
                Section { NavigationLink("المصادر والتراخيص") { LegalView() } }
            }.navigationTitle("الترجمة")
                .fileImporter(isPresented:$importing,allowedContentTypes:[.data],allowsMultipleSelection:false) { result in
                    switch result { case .success(let urls): if let url = urls.first { model.importModel(url) }; case .failure(let error): model.errorMessage = error.localizedDescription }
                }
        }.navigationViewStyle(.stack)
    }
    private func roiControl(_ title: String,keyPath: WritableKeyPath<SourceBox,Double>) -> some View {
        let maximum = keyPath == \SourceBox.x ? 1-model.settings.roi.w : keyPath == \SourceBox.y ? 1-model.settings.roi.h : keyPath == \SourceBox.w ? 1-model.settings.roi.x : 1-model.settings.roi.y
        let minimum = keyPath == \SourceBox.w || keyPath == \SourceBox.h ? 0.01 : 0.0
        return PreciseNumberControl(title:title,value:Binding(get:{ model.settings.roi[keyPath:keyPath] },set:{ model.settings.roi[keyPath:keyPath] = $0 }),range:minimum...max(minimum,maximum),step:0.01,defaultValue:SourceBox.dialogue[keyPath:keyPath]).disabled(model.running)
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
                    DisclosureGroup("تتبع علامات الترقيم · أعداد فقط") {
                        Text(model.metrics.punctuationTrace).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                        if !model.tvRenderSignature.isEmpty { Text(model.tvRenderSignature).font(.system(.caption,design:.monospaced)).textSelection(.enabled) }
                        Text("عدد الأقواس والعلامات في OCR والنص المفصول وخرج الترجمة والرسالة؛ لا يتضمن نص الحوار.").font(.footnote)
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
