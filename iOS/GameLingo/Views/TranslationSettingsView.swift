import SwiftUI
import UniformTypeIdentifiers

struct LocalModelView: View {
    @EnvironmentObject var model: AppModel
    @State private var importing = false
    var body: some View {
        Form {
            Section("الإنجليزية إلى العربية · دون إنترنت") {
                if model.modelReady { Label("النموذج مثبت وجاهز",systemImage:"checkmark.circle.fill") }
                Text(model.modelStatus)
                ModelDownloadProgress(service:model.modelDownload)
                if model.modelBusy { ProgressView() }
                if !model.modelReady {
                    Button("تنزيل النموذج أو استئناف تنزيله") { model.downloadModel() }
                        .disabled(model.modelBusy || model.running)
                }
                if model.modelBusy { Button("إيقاف التنزيل أو التثبيت") { model.cancelModelDownload() } }
                Text("تنزيل مرة واحدة، نحو 88.5 م.ب. بعد التثبيت تُجرى الترجمة على الآيفون دون خدمة سحابية أو اشتراك.").font(.footnote).foregroundColor(.secondary)
            }
            Section {
                DisclosureGroup("استيراد وإدارة النموذج") {
                    Button("استيراد حزمة .argosmodel") { importing = true }.disabled(model.modelBusy || model.running)
                    Button("تحميل النموذج المثبت") { model.loadModel() }.disabled(model.modelBusy || model.running)
                    if model.modelReady {
                        Button("إعادة تنزيل النموذج") { model.downloadModel() }.disabled(model.modelBusy || model.running)
                    }
                    Button("حذف النموذج",role:.destructive) { model.removeModel() }.disabled(model.modelBusy || model.running)
                    Text("Argos EN–AR هو النموذج المعتمد. تُفحص الحزمة قبل تثبيتها. راجع المصادر والتراخيص قبل إعادة توزيعها.").font(.footnote).foregroundColor(.secondary)
                }
            }
        }.navigationTitle("النموذج")
            .fileImporter(isPresented:$importing,allowedContentTypes:[.data],allowsMultipleSelection:false) { result in
                switch result { case .success(let urls): if let url = urls.first { model.importModel(url) }; case .failure(let error): model.errorMessage = error.localizedDescription }
            }
    }
}

struct LocalImprovementView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("تحسين محلي خارج اللعب · اختياري") {
                Toggle("أوافق على جمع أمثلة نصية محليًا لهذه الجلسة",isOn:$model.learningConsent)
                Text("بالتفعيل تُحفظ نصوص الحوار والسياق ومرجع الحزمة على الآيفون فقط: 200 مثال، 7 أيام، بلا صور أو رفع. لا تدريب مستمر للأوزان. ينفذ العامل دورة من 10 أمثلة بعد إيقاف اللعب، ويعتمد فقط ما يطابق مرجع حزمة حرفيًا مع فحوص OCR والسياق والأعداد والنفي. الامتناع متوقع عند الشك.").font(.footnote)
                Text(model.improvementStatus).font(.caption)
                Button("تشغيل دورة الآن خارج اللعب") { model.runImprovement() }.disabled(model.running || !model.modelReady || !model.learningConsent)
                Button("تصدير بيانات التحسين المحلية") { model.exportImprovement() }
                if let file = model.improvementExport { ShareLink(item:file) { Label("مشاركة التصدير",systemImage:"square.and.arrow.up") } }
                Button("حذف الخام والاقتراحات",role:.destructive) { model.improvementWorker.deleteCollected(); model.improvementExport = nil }
                Button("التراجع عن الذاكرة المعتمدة",role:.destructive) { model.improvementWorker.rollback(); model.improvementExport = nil }
                Text("إيقاف الجمع يترك المعتمد يعمل لنفس اللعبة والنص والسياق فقط. لا يُعدل تصحيحك الصريح. زيادة التغطية لا تثبت تحسن جملة جديدة غير مغطاة.").font(.footnote)
            }
        }.navigationTitle("التحسين المحلي")
    }
}

struct BackgroundExperimentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("تشغيل الجلسة والخلفية") {
                Toggle("تجربة الصوت الصامت في الخلفية",isOn:$model.settings.advanced.backgroundAudio)
                    .onChange(of:model.settings.advanced.backgroundAudio) { _ in model.updateBackgroundExperiment() }
                Text(model.sessionStatus)
                Text(model.audioStatus).font(.footnote)
                Text("اختياري وتجريبي. لا يشغّل صوت PS5 ولا يعرض الفيديو. قد يعلّق iOS التطبيق أو يمنع الاستئناف أثناء القفل. نجاح التجربة يُقاس بوصول جمل جديدة إلى TCL؛ ظهور جلسة صوت لا يثبت ذلك.").font(.footnote).foregroundColor(.secondary)
            }
        }.navigationTitle("تجربة الخلفية")
    }
}

struct ContextSettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("ذاكرة السياق والمصطلحات") {
                Text("تُحفظ ضمن ملف الإعداد النشط؛ اختر اللعبة من قسم الألعاب قبل تخصيصها.").font(.footnote).foregroundColor(.secondary)
                Toggle("ذاكرة سياق مؤقتة",isOn:$model.settings.advanced.contextEnabled)
                if model.settings.advanced.contextEnabled {
                PreciseNumberControl(title:"عدد الجمل السابقة",value:Binding(get:{ Double(model.settings.advanced.contextCapacity) },set:{ model.settings.advanced.contextCapacity = Int($0) }),range:1...20,defaultValue:5,integer:true)
                Text("المحرك: Argos المحلي السريع. زيادة الذاكرة لا تضمن تحسن الترجمة؛ تؤثر الذاكرة عند مطابقة قاعدة سياق تضيفها أدناه.").font(.footnote).foregroundColor(.secondary)
                }
                TextField("أسماء موثوقة إضافية، مفصولة بفواصل",text:Binding(get:{ model.settings.advanced.speakerNames },set:{ model.settings.advanced.speakerNames = String($0.prefix(2000)) }),axis:.vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection,.leftToRight)
                Text("يمكن ترك القائمة فارغة؛ تُكتشف التسميات الواضحة تلقائيًا، وتساعد القائمة مع أسماء خاصة أو غير واضحة.").font(.footnote)
                TextEditor(text:Binding(get:{ model.settings.advanced.terminology },set:{ model.settings.advanced.terminology = String($0.prefix(8000)) }))
                    .frame(minHeight:110).textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection,.leftToRight)
                Text("قواعد اختيارية، سطر لكل قاعدة:\nWait! = انتظر!\nriver | Go to the bank. = اذهب إلى ضفة النهر.\nالجزء قبل | شرط وجود كلمة في السياق السابق. تُطابق القاعدة الجملة الحالية كاملة. لا تُحفظ محادثاتك على القرص.").font(.footnote).foregroundColor(.secondary)
            }
        }.navigationTitle("السياق والمصطلحات")
    }
}

struct DialogueSettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("قراءة الحوار") {
                Text(model.running ? model.sessionStatus : "OCR متوقف")
                Picker("وضع الأداء",selection:$model.settings.mode) { ForEach(PerformanceMode.allCases,id:\.self) { Text($0.title).tag($0) } }
                Text("منطقة القراءة كنسبة من الصورة؛ الأصل أعلى اليسار. أوقف الجلسة قبل تعديلها.").font(.footnote)
                roiControl("X",keyPath:\.x); roiControl("Y",keyPath:\.y)
                roiControl("العرض",keyPath:\.w); roiControl("الارتفاع",keyPath:\.h)
                Text(model.settings.roi.isValid ? "منطقة صالحة" : "المنطقة تتجاوز حدود الصورة").foregroundColor(model.settings.roi.isValid ? .secondary : .red)
                Button("استعادة منطقة الحوار الافتراضية") { model.settings.roi = .dialogue }.disabled(model.running)
            }
        }.navigationTitle("قراءة الحوار المتقدمة")
    }
    private func roiControl(_ title: String,keyPath: WritableKeyPath<SourceBox,Double>) -> some View {
        let maximum = keyPath == \SourceBox.x ? 1-model.settings.roi.w : keyPath == \SourceBox.y ? 1-model.settings.roi.h : keyPath == \SourceBox.w ? 1-model.settings.roi.x : 1-model.settings.roi.y
        let minimum = keyPath == \SourceBox.w || keyPath == \SourceBox.h ? 0.01 : 0.0
        return PreciseNumberControl(title:title,value:Binding(get:{ model.settings.roi[keyPath:keyPath] },set:{ model.settings.roi[keyPath:keyPath] = $0 }),range:minimum...max(minimum,maximum),step:0.01,defaultValue:SourceBox.dialogue[keyPath:keyPath]).disabled(model.running)
    }
}
