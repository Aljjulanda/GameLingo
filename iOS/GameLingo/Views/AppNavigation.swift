import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View { HomeContent(model:model,library:model.packLibrary) }
}

private struct HomeContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: GamePackLibrary
    @State private var showingCurrentMenu = false
    private var readiness: TranslationReadiness {
        TranslationReadiness(modelReady:model.modelAvailable,
            hasConsole:model.consoles.contains { $0.id == model.settings.selectedConsoleID },
            validRegion:model.settings.roi.isValid,importing:library.busy,pairing:model.pairing,
            destination:model.gameOptions.destination,tvConnected:model.tvConnected)
    }
    var body: some View {
        Form {
            Section {
                Label(model.running ? (model.streamConnected ? "بث PS5 متصل" : "بانتظار بث PS5") : readiness.title,
                      systemImage:model.running ? "waveform.path" : readiness.canStart ? "checkmark.circle" : "circle.dashed")
                    .font(.headline).accessibilityIdentifier("home.readiness")
                if model.running { Text(model.sessionStatus).font(.subheadline).foregroundColor(.secondary) }
                TranslationSessionButton(running:model.running,canStart:readiness.canStart) {
                    if model.running { model.stop() }
                    else { model.feedback.requestAuthorizationIfNeeded(); model.start() }
                }
                .accessibilityIdentifier("home.session")
                if !model.running { nextStep }
                if !model.running && !readiness.canFinishSetup {
                    NavigationLink("الإعداد خطوة بخطوة") { SetupGuideView() }
                        .accessibilityIdentifier("home.setup")
                }
            } header: { Text("الترجمة اليومية") } footer: {
                Text("شغّل PS5 باليد. تبقى صورة اللعب الأصلية على HDMI؛ يقرأ التطبيق البث الثانوي.")
            }
            if model.loginRequired { PS5LoginSection() }
            if model.menuSuggestionVisible {
                Section("قد تكون هذه قائمة") {
                    Button("قراءة القائمة وترجمتها") { model.translateCurrentMenu(); showingCurrentMenu = true }
                    Text("اقتراح من منطقة الحوار؛ اضغط لقراءة إطار جديد. تُترجم القوائم المدعومة تلقائيًا.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            if model.qualityCaptureActive || model.learningConsent {
                Section("التعلم المحلي التلقائي") {
                    if model.qualityCaptureActive {
                        Label("تسجيل نصوص الاختبار جارٍ",systemImage:"record.circle").foregroundColor(.red)
                        Button("إيقاف التسجيل المحلي") { model.qualityCapture() }
                    }
                    if model.learningConsent {
                        Text("التعلم يعمل تلقائيًا لهذه الجلسة.")
                        Button("إيقاف جمع أمثلة التحسين") { model.learningConsent = false }
                    }
                }
            }
            Section("مكان عرض الترجمة") {
                DestinationPicker(selection:$model.gameOptions.destination,identifier:"home.destination")
                if model.gameOptions.destination.phoneEnabled {
                    NavigationLink { PhoneTranslationView() } label: { Label("فتح شاشة الترجمة على الآيفون",systemImage:"iphone") }
                    Text("تظهر العربية داخل GameLingo؛ لا يلزم اقتران تلفزيون.").font(.footnote).foregroundColor(.secondary)
                }
                if model.gameOptions.destination.tvEnabled {
                    Label(model.tvConnected ? "التلفزيون متصل" : "التلفزيون غير متصل",systemImage:model.tvConnected ? "checkmark.circle" : "tv")
                    if !model.tvConnected {
                        NavigationLink("إعداد اتصال التلفزيون") { ConnectionView(scope:.television) }
                        Text(model.gameOptions.destination.phoneEnabled ? "يمكن متابعة الترجمة على الآيفون أثناء تجهيز التلفزيون." : "يمكن بدء البث الآن؛ لن تظهر العربية على التلفزيون حتى يتصل.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
            Section("الأجهزة المطلوبة") {
                Text(model.networkStatus).font(.footnote).foregroundColor(.secondary)
                NavigationLink { ConnectionView(scope:.console) } label: {
                    VStack(alignment:.leading,spacing:4) {
                        Label("مصدر الصورة · PS5",systemImage:"gamecontroller")
                        Text(model.consoles.first(where:{$0.id == model.settings.selectedConsoleID})?.name ?? "اختر جهازًا محفوظًا أو سجّل جهازك")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                if !model.modelReady {
                    NavigationLink("تجهيز نموذج الترجمة المحلي") { LocalModelView() }
                }
            }
            Section("اختصارات") {
                NavigationLink { AppearanceOverviewView() } label: { Label("مظهر الترجمة",systemImage:"textformat.size") }
                Button {
                    model.translateCurrentMenu(); showingCurrentMenu = true
                } label: { Label("ترجمة القائمة الحالية",systemImage:"list.bullet.rectangle").fixedSize(horizontal:false,vertical:true) }
                    .disabled(!model.running || !model.modelReady || !model.streamConnected || model.readingActive)
                CurrentReadingSection()
            }
            Section {
                LabeledContent("الإعداد النشط",value:model.gameProfiles.first(where:{$0.id == model.currentGame})?.title ?? "عام")
                Text("تعمل الترجمة العامة دون إضافة لعبة. ملفات الألعاب تخصيص اختياري.").font(.footnote).foregroundColor(.secondary)
            }
        }.navigationTitle("الرئيسية")
            .sheet(isPresented:$showingCurrentMenu) { NavigationStack { CurrentMenuView() } }
    }
    @ViewBuilder private var nextStep: some View {
        switch readiness.nextStep {
        case .model: NavigationLink("تنزيل النموذج أو تحميل المثبت") { LocalModelView() }
        case .console: NavigationLink("اختيار PS5 أو تسجيله") { ConnectionView(scope:.console) }
        case .region: NavigationLink("تصحيح منطقة الحوار") { DialogueSettingsView() }
        case .importing: NavigationLink("عرض تقدم استيراد الحزمة") { GamePackLibraryView(library:library) }
        case .pairing: Text("انتظر اكتمال تسجيل الجهاز.").foregroundColor(.secondary)
        case .ready: EmptyView()
        }
    }
}

struct PS5LoginSection: View {
    @EnvironmentObject var model: AppModel
    @State private var pin = ""
    var body: some View {
        Section("PS5 يطلب رمز تسجيل الدخول") {
            SecureField("رمز من 4 أرقام",text:$pin).keyboardType(.numberPad)
            Button("إرسال الرمز") {
                do { try model.remote.loginPIN(pin); model.loginRequired = false; pin = "" }
                catch { model.errorMessage = error.localizedDescription }
            }
        }
    }
}

struct CurrentReadingSection: View {
    @EnvironmentObject var model: AppModel
    private var canRead: Bool { model.running && model.streamConnected && model.tvConnected && model.tvDocuments && !model.readingActive }
    var body: some View {
        Button { model.smartRead() } label: { Label("قراءة النص الظاهر",systemImage:"doc.text.viewfinder") }
            .disabled(!canRead).accessibilityIdentifier("home.readText")
        if model.readingActive {
            Text(model.readingStatus)
            if model.readingPages.isEmpty {
                ProgressView("جارٍ إعداد القراءة…")
                if model.metrics.documentTotal > 0 { Text("ترجمة الجزء \(model.metrics.documentCompleted) من \(model.metrics.documentTotal)") }
            }
            else {
                Text("الصفحة \(model.readingPage+1) من \(model.readingPages.count)")
                HStack {
                    Button("السابقة") { model.moveReadingPage(-1) }.disabled(model.readingPage == 0)
                    Spacer()
                    Button("التالية") { model.moveReadingPage(1) }.disabled(model.readingPage+1 >= model.readingPages.count)
                }.buttonStyle(.bordered)
            }
            Button("إغلاق القراءة والعودة للحوار") { model.closeReading() }
        } else {
            if model.readingStatus != "القراءة مغلقة" { Text(model.readingStatus).font(.footnote) }
            Text(!model.running ? "ابدأ الترجمة لقراءة مستند أو نص طويل من إطار جديد." : !model.tvConnected || !model.tvDocuments ? "قراءة المستندات تحتاج حاليًا تلفزيونًا متصلًا يدعم القراءة." : !model.streamConnected ? "بانتظار اتصال بث PS5." : "تتوقف بطاقات الحوار مؤقتًا أثناء القراءة.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

struct GamesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("اللعبة والإعدادات المرتبطة بها") {
                LabeledContent("الحالي",value:model.gameProfiles.first(where:{$0.id == model.currentGame})?.title ?? "عام")
                NavigationLink { GameProfilesView() } label: { Label("اختيار لعبة وملفها وقوائمها",systemImage:"gamecontroller") }
                Text("الملفات اختيارية. لا تحتاج حزمة أو قالبًا لبدء ترجمة الحوار.").font(.footnote).foregroundColor(.secondary)
            }
            Section("مناطق القراءة والقوائم") {
                NavigationLink("تحديد منطقة الحوار على الصورة") { GameFrameEditorView() }
                NavigationLink("تسجيل قالب قائمة اختياري") { GameFrameEditorView(menuSetup:true) }
                NavigationLink("القائمة الحالية دون قالب") { CurrentMenuView() }
                Text("من الرئيسية اطلب ترجمة القائمة الظاهرة دون تسجيلها. القوالب اختيارية للتعرف التلقائي على قوائم معروفة.").font(.footnote).foregroundColor(.secondary)
            }
            Section("الترجمات والأسماء") {
                NavigationLink("مكتبة ترجمات الألعاب") { GamePackLibraryView(library:model.packLibrary) }.accessibilityIdentifier("gamePacks.library")
                NavigationLink("أسماء اللعبة") { GameNamesView(library:model.namesLibrary) }
                NavigationLink("تصحيحاتي والحوارات الأخيرة") { CorrectionsView(library:model.correctionsLibrary) }
                Text("تتبع الأسماء والتصحيحات نطاق اللعبة المختارة؛ اختر اللعبة قبل إضافة تعديل خاص بها.").font(.footnote).foregroundColor(.secondary)
            }
        }.navigationTitle("الألعاب")
    }
}

struct AppSettingsView: View {
    @State private var search = ""
    private var pages: [SettingsPage] { SettingsPage.allCases.filter { $0.matches(search) } }
    var body: some View {
        List {
            if pages.isEmpty {
                VStack(alignment:.leading,spacing:8) {
                    Label("لا توجد إعدادات مطابقة",systemImage:"magnifyingglass")
                    Text("جرّب: خط، تلفزيون، نموذج، خلفية، أو تشخيص.").font(.footnote).foregroundColor(.secondary)
                    Button("مسح البحث") { search = "" }
                }
            } else {
                ForEach(pages) { page in
                    NavigationLink { destination(page) } label: { Label(page.title,systemImage:page.symbol).padding(.vertical,4) }
                }
            }
        }.navigationTitle("الإعدادات").searchable(text:$search,prompt:"ابحث عن إعداد")
    }
    @ViewBuilder private func destination(_ page: SettingsPage) -> some View {
        switch page {
        case .devices: ConnectionView()
        case .appearance: AppearanceOverviewView()
        case .translation: TranslationPreferencesView()
        case .menus: CurrentMenuView()
        case .model: LocalModelView()
        case .advanced: AdvancedSettingsView()
        case .experiments: BackgroundExperimentView()
        case .improvement: LocalImprovementView()
        case .diagnostics: DiagnosticsSettingsView()
        case .help: HelpView()
        }
    }
}

struct TranslationPreferencesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("اللغات المدعومة") {
                LabeledContent("من",value:"الإنجليزية")
                LabeledContent("إلى",value:"العربية")
                Text("الترجمة محلية بعد تثبيت النموذج؛ لا يلزم اشتراك أو خدمة سحابية.").font(.footnote).foregroundColor(.secondary)
            }
            Section("الجلسة") {
                Picker("وضع الأداء",selection:$model.settings.mode) {
                    ForEach(PerformanceMode.allCases,id:\.self) { Text($0.title).tag($0) }
                }
                Toggle("تعتيم الشاشة أثناء الجلسة",isOn:$model.settings.dimScreen)
            }
            SessionNotificationSettings(feedback:model.feedback)
        }.navigationTitle("الترجمة واللغة")
    }
}

struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Section("القراءة والترجمة") {
                NavigationLink("منطقة الحوار والأداء") { DialogueSettingsView() }
                NavigationLink("السياق والمصطلحات") { ContextSettingsView() }
            }
            QualitySettingsSection()
        }.navigationTitle("إعدادات متقدمة")
    }
}

struct DiagnosticsSettingsView: View {
    var body: some View {
        Form {
            Section { NavigationLink("قياسات الجلسة واسترداد الاتصال") { PerformanceView() } }
            QualitySettingsSection(diagnostics:true)
        }.navigationTitle("التشخيص والقياسات")
    }
}

struct HelpView: View {
    var body: some View {
        Form {
            Section("ابدأ من الرئيسية") {
                NavigationLink("فتح دليل الإعداد العملي") { SetupGuideView() }
                Text("اختر مكان عرض العربية، وجهّز النموذج المحلي، ثم اختر PS5 أو سجّله مرة واحدة بحساب البث الثاني. شغّل الجهاز باليد واضغط بدء الترجمة.")
                Text("للآيفون فقط: لا تحتاج اقتران تلفزيون. للتلفزيون: افتح إعداد الاتصال وامسح رمز QR أو استخدم العنوان والرمز يدويًا.")
            }
            Section("أثناء اللعب") {
                Text("أبقِ التطبيق في المقدمة. تجربة الخلفية اختيارية ولا تضمن استمرار الترجمة أثناء القفل. لإيقاف الجلسة واستردادها التلقائي اضغط إيقاف الترجمة من الرئيسية.")
                Text("يمكن تخصيص مناطق القراءة والأسماء والتصحيحات من الألعاب. الإعدادات المتقدمة لا تلزم للاستخدام اليومي.")
            }
            Section { NavigationLink("المصادر والتراخيص") { LegalView() } }
        }.navigationTitle("المساعدة")
    }
}

struct AppearanceOverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("معاينة المظهر") {
                Text(LocalSubtitleState.sample)
                    .font(.system(.title3,weight:model.settings.display.bool("bold") ? .bold : .regular))
                    .foregroundColor(Color(hex:model.settings.display.string("text_color")))
                    .multilineTextAlignment(.center).frame(maxWidth:.infinity)
                    .padding().background(Color.black).cornerRadius(12)
                    .accessibilityLabel("عينة نص عربية؛ افتح العرض الفعلي لمعاينة المقاس والموضع")
                Text("عينة للون والوزن. لمراجعة المقاس والموضع والتأثيرات على الوجهة المختارة، شغّل المعاينة الفعلية أدناه.").font(.footnote).foregroundColor(.secondary)
                Button(model.previewActive ? "إيقاف المعاينة الفعلية" : "تشغيل المعاينة الفعلية") { model.preview(!model.previewActive) }
                NavigationLink("فتح عرض الآيفون") { PhoneTranslationView() }
            }
            Section("الأنماط") {
                Menu("اختيار نمط…") {
                    Button("كلاسيكي") { model.settings.display.preset("Classic") }
                    Button("سينمائي") { model.settings.display.preset("Cinema") }
                    Button("ألعاب") { model.settings.display.preset("Gaming") }
                    Button("بسيط") { model.settings.display.preset("Minimal") }
                }
                Text("تطبيق نمط يعيد قيم المظهر والموضع والتوقيت إلى إعدادات النمط. فتح الصفحة وحده لا يغير مظهرك.").font(.footnote).foregroundColor(.secondary)
            }
            Section { NavigationLink("تخصيص دقيق واستيراد المظهر") { SubtitleSettingsView() } }
        }.navigationTitle("المظهر")
    }
}

struct TranslationSessionButton: View {
    var running: Bool
    var canStart: Bool
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    private var title: String { running ? "إيقاف الترجمة" : "بدء الترجمة" }
    private var symbol: String { running ? "stop.fill" : "play.fill" }
    var body: some View {
        Button(action:action) {
            Group {
                if textSize.isAccessibilitySize {
                    VStack(spacing:8) {
                        Image(systemName:symbol).accessibilityHidden(true)
                        Text(title).fixedSize(horizontal:false,vertical:true)
                    }
                } else {
                    Label(title,systemImage:symbol).fixedSize(horizontal:false,vertical:true)
                }
            }
            .font(.headline).multilineTextAlignment(.center)
            .foregroundColor(.white)
            .frame(maxWidth:.infinity,minHeight:44).padding(.vertical,8)
        }
        .buttonStyle(.borderedProminent).tint(running ? .red : .teal)
        .disabled(!running && !canStart).accessibilityLabel(title)
    }
}

struct DestinationPicker: View {
    @Binding var selection: DisplayDestination
    var identifier: String
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        if textSize.isAccessibilitySize {
            // Separate rows keep the full option and selection visible instead
            // of squeezing the menu value beside a large Arabic field label.
            ForEach(DisplayDestination.allCases,id:\.self) { destination in
                Button { selection = destination } label: {
                    HStack(alignment:.top,spacing:12) {
                        Image(systemName:selection == destination ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        Text(destination.title).multilineTextAlignment(.leading)
                            .fixedSize(horizontal:false,vertical:true)
                        Spacer(minLength:0)
                    }.frame(minHeight:44).padding(.vertical,4).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityValue(selection == destination ? "محدد" : "غير محدد")
                .accessibilityAddTraits(selection == destination ? .isSelected : [])
                .accessibilityIdentifier(identifier+"."+destination.rawValue)
            }
        } else {
            Picker("وجهة العرض",selection:$selection) {
                ForEach(DisplayDestination.allCases,id:\.self) { Text($0.title).tag($0) }
            }.accessibilityIdentifier(identifier)
        }
    }
}
