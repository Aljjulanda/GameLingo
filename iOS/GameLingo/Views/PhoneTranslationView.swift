import SwiftUI

struct PhoneTranslationView: View {
    @EnvironmentObject var model: AppModel
    @State private var showFrame = true
    var body: some View {
        VStack {
            Toggle("معاينة صورة اللعبة ومحاذاة القوائم",isOn:$showFrame)
                .padding(.horizontal).onChange(of:showFrame) { model.framePreview($0) }
            Text("العرض داخل GameLingo. يحتاج مصدر إطار PS5؛ لا يحتاج اتصال TV في وضعي الآيفون وكليهما.").font(.caption).foregroundColor(.secondary).padding(.horizontal)
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if showFrame, let frame = model.previewFrame { Image(uiImage:frame).resizable().scaledToFit() }
                    TimelineView(.periodic(from:.now,by:0.15)) { _ in
                        let now = ProcessInfo.processInfo.systemUptime
                        ZStack {
                            if model.localMenuUntil > now, showFrame, let frame = model.previewFrame {
                                MenuItemsOverlay(items:model.localMenuItems,appearance:model.localMenuAppearance,frameSize:frame.size)
                            }
                            let state = model.localSubtitles
                            let texts = state.preview ? [LocalSubtitleState.sample] : state.document.map{[$0]} ?? state.entries.filter{$0.until > now}.map(\.text)
                            VStack(spacing:8) { ForEach(Array(texts.enumerated()),id:\.offset) { _,text in
                                Text(text).font(.system(size:max(12,model.settings.display.number("font_size")*geometry.size.width/600),weight:model.settings.display.bool("bold") ? .bold : .regular))
                                    .foregroundColor(Color(hex:model.settings.display.string("text_color"))).opacity(model.settings.display.number("text_opacity")/100)
                                    .multilineTextAlignment(model.settings.display.string("alignment") == "left" ? .leading : model.settings.display.string("alignment") == "right" ? .trailing : .center)
                                    .padding(.horizontal,model.settings.display.number("padding_x")*0.4).padding(.vertical,model.settings.display.number("padding_y")*0.4)
                                    .background(model.settings.display.bool("background") ? Color(hex:model.settings.display.string("background_color")).opacity(model.settings.display.number("background_opacity")/100) : .clear)
                                    .cornerRadius(model.settings.display.number("radius"))
                                    .shadow(color:model.settings.display.bool("shadow") ? Color(hex:model.settings.display.string("shadow_color")) : .clear,radius:model.settings.display.number("shadow_blur")*0.4)
                            } }
                            .frame(maxWidth:geometry.size.width*model.settings.display.number("max_width")/100)
                            .position(x:geometry.size.width*(0.5+model.settings.display.number("x")/1920),y:geometry.size.height*(0.88+model.settings.display.number("y")/1080))
                        }
                    }
                }
            }
            if !model.gameOptions.destination.phoneEnabled { Text("اختر الآيفون فقط أو كليهما من إعدادات الترجمة المرئية.").font(.footnote) }
        }.navigationTitle("ترجمة الآيفون")
            .onAppear { model.framePreview(showFrame) }.onDisappear { model.framePreview(false) }
    }
}

struct MenuItemsOverlay: View {
    var items: [MenuOverlayItem], appearance: MenuAppearance, frameSize: CGSize
    var body: some View {
        GeometryReader { geometry in
            let viewport = VideoViewport(frameWidth:frameSize.width,frameHeight:frameSize.height,viewWidth:geometry.size.width,viewHeight:geometry.size.height).rect
            ForEach(items) { item in
                let left = appearance.side == "left"
                Text(item.translated).font(.system(size:max(10,appearance.fontSize*viewport.w/1000)))
                    .foregroundColor(Color(hex:appearance.matchColor ? item.color ?? appearance.color : appearance.color))
                    .padding(3).background(appearance.background ? Color.black.opacity(0.7) : .clear)
                    .shadow(color:appearance.shadow || appearance.outline ? .black : .clear,radius:appearance.outline ? 1 : 2)
                    .frame(width:max(60,viewport.w*0.26),alignment:left ? .trailing : .leading)
                    .position(x:viewport.x+viewport.w*(left ? item.box.x-appearance.gap-0.13 : item.box.x+item.box.w+appearance.gap+0.13),y:viewport.y+viewport.h*(item.box.y+item.box.h/2))
            }
        }.environment(\.layoutDirection,.leftToRight)
    }
}
