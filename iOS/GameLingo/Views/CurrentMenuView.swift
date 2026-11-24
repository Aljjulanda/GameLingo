import SwiftUI

struct CurrentMenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingFrame = false
    private var canRead: Bool { model.running && model.modelReady && model.streamConnected && !model.readingActive }
    private var appearance: Binding<MenuAppearance> {
        Binding(get:{model.gameOptions.currentMenuAppearance ?? MenuAppearance()},set:{model.gameOptions.currentMenuAppearance = $0})
    }
    var body: some View {
        Form {
            Section {
                Button(model.currentMenuReadout.active ? "إعادة قراءة القائمة الحالية" : "ترجمة القائمة الحالية") { model.translateCurrentMenu() }
                    .disabled(!canRead)
                Text(model.currentMenuReadout.status)
                if !canRead { Text("ابدأ الترجمة من الرئيسية، وانتظر بث PS5، وأغلق قراءة المستند إن كانت مفتوحة.").font(.footnote) }
                if model.currentMenuReadout.pending > 0 {
                    ProgressView("عناصر قيد الترجمة: \(model.currentMenuReadout.pending)")
                }
                if model.currentMenuReadout.withheld > 0 {
                    Text("بعض العناصر لا تتسع بجوار الأصل أو لم تجتز التحقق. راجع النص الكامل هنا؛ جرّب تغيير الجهة أو تصغير خط القائمة.").font(.footnote)
                }
                Text("قراءة عند الطلب للعناصر الواضحة، بلا قالب أو ملف لعبة خاص. قد يفوت OCR نصًا غير واضح؛ أعد الطلب عند الانتقال خارج المنطقة المقروءة. افتح قائمة اللعبة قبل الطلب وأغلق هذه القراءة عند الرجوع للعب.").font(.footnote).foregroundColor(.secondary)
            }
            Section("العناصر الظاهرة") {
                if model.currentMenuReadout.sources.isEmpty { Text("ستظهر هنا عناصر الإطار الجديد وترجمتها.").foregroundColor(.secondary) }
                ForEach(Array(model.currentMenuReadout.sources.enumerated()),id:\.offset) { _,line in
                    VStack(alignment:.leading,spacing:8) {
                        Text(line.text).font(.subheadline).foregroundColor(.secondary)
                            .environment(\.layoutDirection,.leftToRight).textSelection(.enabled)
                        if let item = model.currentMenuReadout.items.first(where:{$0.source == line.text}) {
                            Text(item.translated).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                        } else if model.currentMenuReadout.rejectedSources.contains(line.text) {
                            Text("تعذرت ترجمة موثوقة؛ راجع الأصل أو أعد الطلب. لم تُعرض نتيجة قد تغير المعنى.").font(.footnote)
                        } else { Text("بانتظار الترجمة…").font(.footnote) }
                    }.padding(.vertical,4)
                }
            }
            Section("المحاذاة بجوار الأصل") {
                Picker("الجهة",selection:appearance.side) { Text("يمين الأصل").tag("right"); Text("يسار الأصل").tag("left") }
                PreciseNumberControl(title:"الفجوة كنسبة من الصورة",value:appearance.gap,range:0...0.15,step:0.005,defaultValue:0.012)
                PreciseNumberControl(title:"حجم خط القائمة",value:appearance.fontSize,range:10...72,defaultValue:22)
                Toggle("خلفية للوضوح",isOn:appearance.background)
                Toggle("حد للنص",isOn:appearance.outline)
                Toggle("ظل",isOn:appearance.shadow)
                Toggle("تقدير لون الحروف من البث",isOn:appearance.matchColor)
                ColorPicker("اللون اليدوي والاحتياطي",selection:Binding(get:{Color(hex:appearance.wrappedValue.color)},set:{appearance.wrappedValue.color = $0.hexRGB}),supportsOpacity:false)
                Text("الألوان تقريبية؛ لا تطابق مضمونًا للخط أو HDR. تُعرض العناصر التي تتسع فقط بجوار الأصل، والنص الكامل في القائمة أعلاه.").font(.footnote).foregroundColor(.secondary)
                if model.gameOptions.destination.phoneEnabled {
                    Toggle("معاينة الصورة ومحاذاة العربية",isOn:$showingFrame)
                        .onChange(of:showingFrame) { model.framePreview($0) }
                    if showingFrame {
                        GeometryReader { _ in
                            ZStack {
                                Color.black
                                if let frame = model.previewFrame {
                                    Image(uiImage:frame).resizable().scaledToFit()
                                    MenuItemsOverlay(items:model.localMenuItems,appearance:model.localMenuAppearance,frameSize:frame.size)
                                } else { Text("بانتظار صورة البث").foregroundColor(.white) }
                            }
                        }.frame(height:220).environment(\.layoutDirection,.leftToRight)
                    }
                }
                if model.gameOptions.destination.tvEnabled && (!model.tvConnected || !model.tvMenus) {
                    Text("المحاذاة على التلفزيون تحتاج اتصالًا ومستقبلًا يدعم القوائم. تبقى قائمة القراءة هنا متاحة.").font(.footnote)
                }
            }
            Section {
                Button("إغلاق القائمة والعودة للحوار") { model.closeCurrentMenu(); dismiss() }
            }
        }.navigationTitle("القائمة الحالية")
            .onDisappear { model.framePreview(false); model.closeCurrentMenu() }
    }
}
