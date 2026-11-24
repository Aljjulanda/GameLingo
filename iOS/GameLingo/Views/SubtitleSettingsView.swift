import SwiftUI
import UniformTypeIdentifiers

struct SubtitleSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = 5.0
    @State private var importing = false
    private let type = ["font_size":"حجم الخط","font_weight":"وزن الخط","text_opacity":"شفافية النص","line_spacing":"تباعد الأسطر","max_width":"أقصى عرض من شاشة التلفزيون %"]
    private let outline = ["outline_width":"سمك الحدود"]
    private let shadow = ["shadow_opacity":"شفافية الظل","shadow_x":"إزاحة الظل أفقيًا","shadow_y":"إزاحة الظل رأسيًا","shadow_blur":"تمويه الظل"]
    private let background = ["background_opacity":"شفافية الخلفية","padding_x":"حشو أفقي px","padding_y":"حشو رأسي px","radius":"تدوير الزوايا px"]
    private let timing = ["reading_speed":"حروف في الثانية","min_seconds":"أقل مدة قراءة (ث)","max_seconds":"أقصى مدة قراءة (ث)","hard_seconds":"الحد النهائي (ث)","fixed_seconds":"المدة الثابتة (ث)","disappearance_grace":"مهلة اختفاء المصدر (ث)","fade_ms":"التلاشي ms","max_entries":"أقصى عدد جمل","spacing":"تباعد الجمل px","max_height":"أقصى ارتفاع %","older_opacity":"شفافية الجمل السابقة %"]
    var body: some View {
        Form {
            Section("استيراد المظهر") {
                Button("استيراد مظهر محفوظ من Windows") { importing = true }
                Text("تُحفظ الإعدادات على iPhone وتُرسل تلقائيًا إلى التلفزيون المتصل. يمكن استيراد ملف settings.json السابق لنقل مظهرك الحالي.").font(.footnote).foregroundColor(.secondary)
            }
            Section("الخط والنص") {
                Toggle("إظهار أسماء المتحدثين",isOn:$model.settings.advanced.showSpeakers)
                if model.tvConnected && !model.tvSpeakers { Text("حدّث تطبيق TV لدعم الأسماء داخل السطر.").font(.footnote).foregroundColor(.secondary) }
                if model.settings.advanced.showSpeakers {
                ColorPicker("لون اسم المتحدث",selection:Binding(get:{ Color(hex:model.settings.advanced.speakerColor) },set:{ model.settings.advanced.speakerColor = $0.hexRGB }),supportsOpacity:false)
                Button("استعادة لون المتحدث الافتراضي") { model.settings.advanced.speakerColor = "#A6C7D8" }
                }
                Picker("عائلة الخط",selection:string("font_family")) {
                    Text("افتراضي Android").tag("sans-serif")
                    Text("Serif").tag("serif")
                    Text("Monospace").tag("monospace")
                    Text("Sans Medium").tag("sans-serif-medium")
                }
                TextField("اسم عائلة خط مخصص على التلفزيون",text:string("font_family")).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("خط عريض",isOn:flag("bold"))
                numberRows(type)
                colorRow("لون النص","text_color")
                Picker("المحاذاة",selection:string("alignment")) { Text("يمين").tag("right"); Text("وسط").tag("center"); Text("يسار").tag("left") }
                Toggle("التفاف النص",isOn:flag("wrap"))
            }
            Section("الحدود والظل") {
                Toggle("حدود النص",isOn:flag("outline"))
                if model.settings.display.bool("outline") { colorRow("لون الحدود","outline_color"); numberRows(outline) }
                Toggle("ظل النص",isOn:flag("shadow"))
                if model.settings.display.bool("shadow") { colorRow("لون الظل","shadow_color"); numberRows(shadow) }
            }
            Section("الخلفية") {
                Toggle("عرض الخلفية",isOn:flag("background"))
                if model.settings.display.bool("background") {
                Toggle("الخلفية بحجم النص",isOn:flag("fit_background"))
                colorRow("لون الخلفية","background_color")
                numberRows(background)
                Toggle("إطار الخلفية",isOn:flag("border"))
                if model.settings.display.bool("border") { colorRow("لون إطار الخلفية","border_color"); numberRows(["border_width":"سمك إطار الخلفية"]) }
                }
            }
            Section("الموضع بالبكسل") {
                Picker("خطوة التحريك",selection:$step) {
                    Text("1 px").tag(1.0); Text("5 px").tag(5.0); Text("10 px").tag(10.0)
                    if ![1.0,5.0,10.0].contains(step) { Text("\(Int(step)) px").tag(step) }
                }.pickerStyle(.segmented)
                PreciseNumberControl(title:"خطوة مخصصة px",value:$step,range:1...1000,defaultValue:5,integer:true)
                VStack {
                    Button { move(0,-1) } label: { Label("أعلى",systemImage:"arrow.up") }
                    HStack {
                        Button { move(-1,0) } label: { Label("يسار",systemImage:"arrow.left") }
                        Spacer()
                        Button { move(1,0) } label: { Label("يمين",systemImage:"arrow.right") }
                    }.environment(\.layoutDirection,.leftToRight)
                    Button { move(0,1) } label: { Label("أسفل",systemImage:"arrow.down") }
                }.buttonStyle(.bordered)
                numberRows(["x":"إزاحة X px","y":"إزاحة Y px","margin":"هامش الشاشة px"])
                Button("توسيط أسفل الشاشة") { model.settings.display.set("x",.number(0)); model.settings.display.set("y",.number(0)) }
            }
            Section("الجمل الذكية والتوقيت") {
                Toggle("مدة قراءة تكيفية",isOn:flag("adaptive"))
                numberRows(timing.filter { key,_ in
                    if key == "reading_speed" { return model.settings.display.bool("adaptive") }
                    if key == "fixed_seconds" { return !model.settings.display.bool("adaptive") }
                    return true
                })
                Text("الجملة الأحدث ثابتة عند الموضع المختار، والسابقة تتكدس فوقها. تصحيح OCR لا يعيد مؤقت الجملة. التلفزيون يدير الاختفاء تلقائيًا.").font(.footnote).foregroundColor(.secondary)
            }
        }.navigationTitle("المظهر المتقدم")
                .onAppear { step = model.settings.advanced.movementStep }
                .onChange(of:step) { model.settings.advanced.movementStep = $0 }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                    do {
                        let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        model.settings.display = try TVSettings.importWire(Data(contentsOf:url))
                    } catch { model.errorMessage = error.localizedDescription }
                }
    }
    private func move(_ x: Double,_ y: Double) { model.move(x:x,y:y,step:step.isFinite ? max(1,min(1000,step)) : 5) }
    private func flag(_ key: String) -> Binding<Bool> { Binding(get:{ model.settings.display.bool(key) },set:{ model.settings.display.set(key,.bool($0)) }) }
    private func string(_ key: String) -> Binding<String> { Binding(get:{ model.settings.display.string(key) },set:{ model.settings.display.set(key,.string($0)) }) }
    private func numberRows(_ labels: [String:String]) -> some View {
        ForEach(labels.keys.sorted(),id:\.self) { key in
            if let bounds = DisplaySchema.shared.bounds[key] {
                PreciseNumberControl(title:labels[key]!,value:Binding(get:{ model.settings.display.number(key) },set:{ model.settings.display.set(key,.number($0)) }),range:bounds[0]...bounds[1],step:key.contains("seconds") || key=="disappearance_grace" ? 0.1 : key=="font_weight" ? 100 : 1,defaultValue:TVSettings().number(key),integer:["max_entries","x","y"].contains(key))
            }
        }
    }
    private func colorRow(_ title: String,_ key: String) -> some View {
        ColorPicker(title,selection:Binding(get:{ Color(hex:model.settings.display.string(key)) },set:{ model.settings.display.set(key,.string($0.hexRGB)) }),supportsOpacity:false)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(),radix:16) ?? 0xffffff
        self.init(.sRGB,red:Double((value >> 16)&255)/255,green:Double((value >> 8)&255)/255,blue:Double(value&255)/255,opacity:1)
    }
    var hexRGB: String {
        var r: CGFloat = 0,g: CGFloat = 0,b: CGFloat = 0,a: CGFloat = 0
        UIColor(self).getRed(&r,green:&g,blue:&b,alpha:&a)
        return String(format:"#%02X%02X%02X",Int(r*255),Int(g*255),Int(b*255))
    }
}
