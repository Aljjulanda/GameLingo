import SwiftUI

struct GameFrameEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var menuSetup = false
    var replacing: AllowedMenu?
    @State private var box = SourceBox.dialogue
    @State private var dragStart: SourceBox?
    @State private var resize = false
    @State private var menuTitle = ""
    @State private var anchors = Set<Int>()
    @State private var captured = false
    @State private var capturedLines: [OCRLine] = []
    @State private var capturedFrame: UIImage?
    var body: some View {
        ScrollView {
            VStack(spacing:12) {
                Text(menuSetup ? "حدد منطقة القائمة ثم التقط إطارًا واختر دلائل ثابتة مميزة." : "اسحب الإطار لتحريكه، أو فعّل تغيير الحجم ثم اسحب. الإحداثيات تخص صورة البث كاملة، بما فيها الأشرطة السوداء.").font(.footnote)
                GeometryReader { geometry in
                    ZStack {
                        Color.black
                        if let frame = captured ? capturedFrame : model.previewFrame {
                            let viewport = VideoViewport(frameWidth:frame.size.width,frameHeight:frame.size.height,viewWidth:geometry.size.width,viewHeight:geometry.size.height).rect
                            Image(uiImage:frame).resizable().scaledToFit()
                            Rectangle().stroke(.yellow,lineWidth:2)
                                .background(Color.yellow.opacity(0.08))
                                .frame(width:box.w*viewport.w,height:box.h*viewport.h)
                                .position(x:viewport.x+(box.x+box.w/2)*viewport.w,y:viewport.y+(box.y+box.h/2)*viewport.h)
                                .gesture(DragGesture().onChanged { value in
                                    guard !captured, viewport.w > 0, viewport.h > 0 else { return }
                                    if dragStart == nil { dragStart = box }
                                    var updated = dragStart!
                                    if resize { updated.w += value.translation.width/viewport.w; updated.h += value.translation.height/viewport.h }
                                    else { updated.x += value.translation.width/viewport.w; updated.y += value.translation.height/viewport.h }
                                    box = updated.clamped()
                                }.onEnded { _ in dragStart = nil })
                        } else { Text("ابدأ جلسة PS5 لإحضار إطار اللعبة").foregroundColor(.white) }
                    }
                }.frame(height:260).environment(\.layoutDirection,.leftToRight)
                Toggle("تغيير العرض والارتفاع بالسحب",isOn:$resize).disabled(captured)
                HStack {
                    Button("افتراضي") { box = menuSetup ? GameOptions().menuRegion : .dialogue; captured = false }
                    Button("إلغاء") { dismiss() }
                    if !menuSetup { Button("حفظ المنطقة") { model.saveRegion(box,menu:false); dismiss() } }
                }.buttonStyle(.bordered)
                if !menuSetup {
                    Button("تحرير منطقة الحوار بالريموت على TV") { model.startTVRegionEditing() }.disabled(!model.tvConnected)
                } else {
                    TextField("اسم القائمة",text:$menuTitle).textFieldStyle(.roundedBorder)
                    Button("التقاط إطار Setup الحالي") {
                        anchors = []; captured = false; model.captureMenuSetup(box)
                    }.disabled(!model.running)
                    Text("لا يُحفظ إطار اللعب على القرص. اختر على الأقل ثلاثة نصوص ثابتة دون أعداد؛ تجنب الاكتفاء بكلمات عامة مثل Settings.").font(.footnote)
                    ForEach(Array(capturedLines.enumerated()),id:\.offset) { index,line in
                        Toggle(line.text,isOn:Binding(get:{anchors.contains(index)},set:{if $0 { anchors.insert(index) } else { anchors.remove(index) }}))
                            .disabled(line.confidence < 0.8 || !MenuAnchor(text:line.text,box:line.box).valid)
                    }
                    Button("حفظ القائمة المسموح بها") {
                        var menu = AllowedMenu(title:menuTitle,region:box,anchors:anchors.sorted().map { MenuAnchor(text:capturedLines[$0].text,box:capturedLines[$0].box) })
                        if let replacing { menu.id = replacing.id; menu.appearance = replacing.appearance; menu.enabled = replacing.enabled }
                        guard menu.valid else { model.errorMessage = "الدلائل غير كافية أو غير مميزة"; return }
                        model.saveMenu(menu); dismiss()
                    }.disabled(!captured || menuTitle.isEmpty || anchors.count < 3)
                }
            }.padding()
        }.navigationTitle(menuSetup ? "Setup القوائم" : "منطقة الحوار")
            .onAppear { box = replacing?.region ?? (menuSetup ? model.gameOptions.menuRegion : model.settings.roi); menuTitle = replacing?.title ?? ""; model.framePreview(true) }
            .onDisappear { model.framePreview(false) }
            .onChange(of:model.setupLines) { lines in
                guard menuSetup, !lines.isEmpty else { return }
                capturedLines = lines; capturedFrame = model.previewFrame; captured = true
            }
    }
}
