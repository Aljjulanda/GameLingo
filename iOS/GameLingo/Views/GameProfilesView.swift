import SwiftUI

struct GameProfilesView: View {
    @EnvironmentObject var model: AppModel
    @State private var title = ""
    var body: some View {
        Form {
            Section("اللعبة النشطة") {
                ForEach(model.gameProfiles) { profile in
                    Button { model.selectGame(profile.id) } label: {
                        Label(profile.title,systemImage:model.currentGame == profile.id ? "checkmark.circle.fill" : "circle")
                    }
                }
                TextField("اسم لعبة جديدة دون حزمة",text:$title)
                Button("إنشاء واختيار") { model.addGame(title:title); title = "" }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Text("تبديل اللعبة يوقف الجلسة ويلغي النتائج الجارية؛ ابدأها من جديد بعد الاختيار.").font(.footnote)
            }
            Section("ملف الإعدادات") {
                if let profile = model.gameProfiles.first(where:{$0.id == model.currentGame}) {
                    Text(profile.title)
                    Toggle("استخدام إعدادات هذه اللعبة",isOn:Binding(get:{profile.enabled},set:{model.changeProfile($0 ? "enable" : "disable")}))
                    Button("استعادة الإعدادات الافتراضية") { model.changeProfile("reset") }
                    Button("التراجع عن آخر تعديل") { model.changeProfile("undo") }.disabled(profile.previous == nil)
                    Text("يحفظ النموذج والحزمة والمظهر والمناطق ووجهة العرض والقوائم. التعطيل يحتفظ بالملف ويستخدم الافتراضي. تبقى الأسماء وتصحيحاتك في مخازنها الأصلية.").font(.footnote)
                }
            }
            Section("ترجمة القوائم · مستقلة عن الحوار") {
                Toggle("تفعيل القوائم المسجلة",isOn:$model.gameOptions.menusEnabled)
                if model.tvConnected && !model.tvMenus { Text("حدّث GameLingo TV لعرض القوائم بمحاذاة الأصل.").font(.footnote) }
                NavigationLink("تسجيل قائمة من إطار اللعبة") { GameFrameEditorView(menuSetup:true) }
                Text("سجل كل قائمة صراحةً بثلاثة نصوص ثابتة مميزة ومواقعها. القيم والأعداد تُقرأ من الإطار الحالي. عند ضعف التطابق لا تظهر ترجمة القائمة.").font(.footnote)
                ForEach(model.gameOptions.allowedMenus) { menu in
                    NavigationLink(menu.title) { MenuAppearanceEditor(menu:menu) }
                }.onDelete { indices in model.gameOptions.allowedMenus.remove(atOffsets:indices) }
            }
        }.navigationTitle("ملفات الألعاب")
    }
}

struct MenuAppearanceEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var menu: AllowedMenu
    var body: some View {
        Form {
            TextField("اسم القائمة",text:$menu.title)
            Toggle("تفعيل",isOn:$menu.enabled)
            Picker("جهة العربية",selection:$menu.appearance.side) { Text("يمين الأصل").tag("right"); Text("يسار الأصل").tag("left") }
            Slider(value:$menu.appearance.gap,in:0...0.15) { Text("المسافة") }
            PreciseNumberControl(title:"حجم خط القائمة",value:$menu.appearance.fontSize,range:10...72,defaultValue:22)
            Toggle("خلفية",isOn:$menu.appearance.background)
            Toggle("مطابقة لون الحروف من البث",isOn:$menu.appearance.matchColor)
            ColorPicker("اللون اليدوي / الاحتياطي",selection:Binding(get:{Color(hex:menu.appearance.color)},set:{menu.appearance.color = $0.hexRGB}),supportsOpacity:false)
            Toggle("حد للوضوح",isOn:$menu.appearance.outline); Toggle("ظل",isOn:$menu.appearance.shadow)
            Text("اللون تقدير للحروف بعد فك البث، وقد يختلف عن TV وHDR. لا يطابق خط اللعبة الأصلي.").font(.footnote)
            ForEach(Array(menu.anchors.enumerated()),id:\.offset) { _,anchor in Text(anchor.text) }
            Button("حفظ") { model.saveMenu(menu); dismiss() }
            Button("إلغاء",role:.cancel) { dismiss() }
            NavigationLink("تسجيل دلائل ومنطقة بديلة") { GameFrameEditorView(menuSetup:true,replacing:menu) }
        }.navigationTitle("إعداد القائمة")
    }
}
