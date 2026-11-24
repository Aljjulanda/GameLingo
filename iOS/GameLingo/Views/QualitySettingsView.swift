import SwiftUI

struct QualitySettingsSection: View {
    var diagnostics = false
    @EnvironmentObject var model: AppModel
    @State private var consent = false
    var body: some View {
        Section(diagnostics ? "أدوات التشخيص الاختيارية" : "جودة القراءة والترجمة") {
            // Show only implemented units. Later units add their flags here
            // after their tests pass; the storage enum alone is not a feature.
            ForEach(diagnostics ? [QualityFlag.measurement,.provenanceMarker,.punctuationTrace,.sessionCapture] : [QualityFlag.stageCues,.speakerClassification,.speakerGeometry,.visionNames,.learnNames,.corrections,.packMarkup,.packPunctuation,.packLabels,.punctuationRepair,.commandPunctuation,.lineLimits,.arabicParagraphDirection],id:\.rawValue) { flag in
                Toggle(flag.title,isOn:Binding(get:{model.quality[flag]},set:{model.quality[flag] = $0}))
            }
            if !diagnostics {
            DisclosureGroup("متقدم") {
                Stepper("تنبيه غياب المطابقة: \(model.quality.noHitThreshold) حوار",value:$model.quality.noHitThreshold,in:1...1000)
                Stepper("ارتفاع الاسم: \(model.quality.nameHeightRatio,specifier:"%.2f")",value:$model.quality.nameHeightRatio,in:0.8...2,step:0.1)
                Stepper("فجوة الاسم: \(model.quality.nameGapRatio,specifier:"%.2f")",value:$model.quality.nameGapRatio,in:0.5...3,step:0.1)
                Stepper("تداخل الاسم: \(model.quality.nameOverlap,specifier:"%.2f")",value:$model.quality.nameOverlap,in:0...0.75,step:0.05)
                Stepper("إزاحة الاسم الجانبية: \(model.quality.nameLeftOffset,specifier:"%.2f")",value:$model.quality.nameLeftOffset,in:0...0.3,step:0.02)
                Stepper("تعلّم Name: بعد \(model.quality.colonNameThreshold) مرات",value:$model.quality.colonNameThreshold,in:1...10)
                Stepper("تعلّم الاسم المنفصل بعد \(model.quality.otherNameThreshold) مرات",value:$model.quality.otherNameThreshold,in:1...10)
                Stepper("أسطر الحوار المرتبط بمتحدث: \(model.quality.anchoredLineCap)",value:$model.quality.anchoredLineCap,in:3...5)
                    .disabled(!model.quality[.lineLimits])
                Stepper("أسطر الحوار دون متحدث: \(model.quality.fallbackLineCap)",value:$model.quality.fallbackLineCap,in:4...6)
                    .disabled(!model.quality[.lineLimits])
            }
            Button("استعادة جميع إعدادات الجودة الافتراضية") { model.quality = QualitySettings() }
            Text("يشمل الاسترجاع خيارات الجودة وأدوات التشخيص. لا يغير الاقتران أو تصحيحاتك المحفوظة.").font(.footnote).foregroundColor(.secondary)
            }
            if diagnostics {
            if model.qualityCaptureActive {
                Label("تسجيل نصوص الاختبار محليًا قيد التشغيل",systemImage:"record.circle").foregroundColor(.red)
                Button("إيقاف تسجيل الاختبار") { model.qualityCapture() }
            } else if model.quality[.sessionCapture] { Button("تسجيل جلسة اختبار محلية…") { consent = true } }
            if let file = model.qualityCaptureFile {
                ShareLink("تصدير تسجيل الاختبار",item:file)
                Button("حذف تسجيل الاختبار",role:.destructive) { model.qualityCapture(delete:true) }
            }
            Text("التسجيل مغلق افتراضيًا. لا يُستأنف بعد إغلاق التطبيق، ويتوقف عند إيقاف الترجمة. الحد 4 م.ب. أو 30 دقيقة؛ يُحذف عند فتح التطبيق بعد يوم. لا رفع تلقائي ولا نسخ احتياطي.").font(.footnote)
            }
        }
        .confirmationDialog("يتضمن التسجيل نصوص OCR والحوار والترجمة. يُحفظ محليًا للحصر والاختبار فقط، وقد يكشف محتوى اللعبة عند مشاركته.",isPresented:$consent,titleVisibility:.visible) {
            Button("أوافق · بدء التسجيل المحلي") { model.qualityCapture(start:true) }
            Button("إلغاء",role:.cancel) {}
        }
    }
}
