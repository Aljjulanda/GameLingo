import SwiftUI

struct QualitySettingsSection: View {
    @EnvironmentObject var model: AppModel
    @State private var consent = false
    var body: some View {
        Section("إصلاحات الجودة") {
            // Show only implemented units. Later units add their flags here
            // after their tests pass; the storage enum alone is not a feature.
            ForEach([QualityFlag.measurement,.provenanceMarker,.punctuationTrace],id:\.rawValue) { flag in
                Toggle(flag.title,isOn:Binding(get:{model.quality[flag]},set:{model.quality[flag] = $0}))
            }
            DisclosureGroup("متقدم") {
                Stepper("تنبيه غياب المطابقة: \(model.quality.noHitThreshold) حوار",value:$model.quality.noHitThreshold,in:1...1000)
            }
            Button("استعادة الافتراضي") { model.quality = QualitySettings() }
            if model.qualityCaptureActive {
                Label("تسجيل نصوص الاختبار محليًا قيد التشغيل",systemImage:"record.circle").foregroundColor(.red)
                Button("إيقاف تسجيل الاختبار") { model.qualityCapture() }
            } else { Button("تسجيل جلسة اختبار محلية…") { consent = true } }
            if let file = model.qualityCaptureFile {
                ShareLink("تصدير تسجيل الاختبار",item:file)
                Button("حذف تسجيل الاختبار",role:.destructive) { model.qualityCapture(delete:true) }
            }
            Text("التسجيل مغلق افتراضيًا. لا يُستأنف بعد إغلاق التطبيق، ويتوقف عند إيقاف الترجمة. الحد 4 م.ب. أو 30 دقيقة؛ يُحذف عند فتح التطبيق بعد يوم. لا رفع تلقائي ولا نسخ احتياطي.").font(.footnote)
        }
        .confirmationDialog("يتضمن التسجيل نصوص OCR والحوار والترجمة. يُحفظ محليًا للحصر والاختبار فقط، وقد يكشف محتوى اللعبة عند مشاركته.",isPresented:$consent,titleVisibility:.visible) {
            Button("أوافق · بدء التسجيل المحلي") { model.qualityCapture(start:true) }
            Button("إلغاء",role:.cancel) {}
        }
    }
}
