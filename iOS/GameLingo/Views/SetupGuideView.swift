import SwiftUI

/// A live checklist using the existing installers and pairing screens. There is
/// no migration or persisted "finished" flag that can reset a working setup.
struct SetupGuideView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View { SetupGuideContent(model:model,library:model.packLibrary,finish:{ dismiss() }) }
}

private struct SetupGuideContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: GamePackLibrary
    var finish: () -> Void
    private var console: ConsoleCredentials? { model.consoles.first { $0.id == model.settings.selectedConsoleID } }
    private var readiness: TranslationReadiness {
        TranslationReadiness(modelReady:model.modelReady,hasConsole:console != nil,
            validRegion:model.settings.roi.isValid,importing:library.busy,pairing:model.pairing,
            destination:model.gameOptions.destination,tvConnected:model.tvConnected)
    }
    var body: some View {
        Form {
            Section("1. أين تريد عرض العربية؟") {
                Picker("وجهة العرض",selection:$model.gameOptions.destination) {
                    ForEach(DisplayDestination.allCases,id:\.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("setup.destination")
                Text(model.gameOptions.destination == .phone ? "الآيفون مستقل عن اقتران التلفزيون. تحتاج مصدر صورة PS5 في كل الحالات." : "اختر الآيفون فقط إذا أردت البدء دون تلفزيون.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section("2. جهّز الترجمة المحلية") {
                status(model.modelReady ? "النموذج جاهز" : model.modelStatus,complete:model.modelReady)
                NavigationLink(model.modelReady ? "إدارة النموذج" : "تنزيل النموذج أو استيراده") { LocalModelView() }
                Text("إنجليزية إلى عربية، بلا اشتراك. بعد تثبيت النموذج تعمل الترجمة دون إنترنت.").font(.footnote).foregroundColor(.secondary)
            }
            Section("3. اختر مصدر الصورة") {
                status(console.map { "PS5 محفوظ · \($0.name)" } ?? "لم يُختر PS5 بعد",complete:console != nil)
                NavigationLink(console == nil ? "اختيار PS5 أو تسجيله" : "عرض الجهاز المحفوظ") { ConnectionView(scope:.console) }
                Text("التسجيل مرة واحدة بحساب البث الثاني؛ شغّل PS5 باليد. إذا كان الجهاز محفوظًا، لا تعِد تسجيله.").font(.footnote).foregroundColor(.secondary)
            }
            if model.gameOptions.destination.tvEnabled {
                Section("4. اتصال التلفزيون") {
                    status(model.tvConnected ? "التلفزيون متصل" : "التلفزيون غير متصل",complete:model.tvConnected)
                    NavigationLink("فتح اتصال التلفزيون") { ConnectionView(scope:.television) }
                    Text(model.gameOptions.destination == .both ? "يمكن إكمال الإعداد والبدء على الآيفون، ثم توصيل التلفزيون لاحقًا." : "افتح GameLingo TV، ثم امسح رمزه أو استخدم الاتصال اليدوي. لا يلزم تكرار اقتران محفوظ يعمل.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            if !model.settings.roi.isValid {
                Section("منطقة القراءة تحتاج تصحيحًا") {
                    NavigationLink("ضبط منطقة الحوار داخل الصورة") { DialogueSettingsView() }
                }
            }
            Section {
                Button("إنهاء الإعداد") { finish() }
                    .frame(maxWidth:.infinity,minHeight:44).buttonStyle(.borderedProminent)
                    .disabled(!readiness.canFinishSetup).accessibilityIdentifier("setup.finish")
                if !readiness.canStart { Text(readiness.title).font(.footnote).foregroundColor(.secondary) }
                Text("ابدأ الترجمة من الرئيسية بعد الإعداد. لا تحتاج إنشاء ملف لعبة.").font(.footnote).foregroundColor(.secondary)
            }
        }.navigationTitle("إعداد خطوة بخطوة")
    }
    private func status(_ title: String,complete: Bool) -> some View {
        Label(title,systemImage:complete ? "checkmark.circle.fill" : "circle")
            .accessibilityLabel((complete ? "مكتمل: " : "غير مكتمل: ")+title)
    }
}
