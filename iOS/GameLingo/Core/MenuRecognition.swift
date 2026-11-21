import Foundation

struct MenuAnchor: Codable, Equatable {
    var text: String
    var box: SourceBox
    var valid: Bool { box.isValid && text.count >= 3 && text.count <= 100 && !text.contains(where: { $0.isNumber }) }
}
struct MenuAppearance: Codable, Equatable {
    var side = "right"
    var gap = 0.012
    var fontSize = 22.0
    var background = true
    var matchColor = false
    var color = "#FFFFFF"
    var outline = true
    var shadow = true
    var valid: Bool { ["right","left"].contains(side) && gap.isFinite && (0...0.15).contains(gap) && fontSize.isFinite && (10...72).contains(fontSize) && color.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil }
}
struct AllowedMenu: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var enabled = true
    var region: SourceBox
    var anchors: [MenuAnchor]
    var appearance = MenuAppearance()
    var valid: Bool {
        UUID(uuidString:id) != nil && !title.isEmpty && title.count <= 80 && region.isValid && appearance.valid &&
        (3...12).contains(anchors.count) && anchors.allSatisfy { $0.valid && region.contains($0.box) } &&
        Set(anchors.map { MenuRecognition.key($0.text) }).count == anchors.count &&
        anchors.contains { !MenuRecognition.generic.contains(MenuRecognition.key($0.text)) }
    }
}
extension SourceBox {
    func contains(_ other: SourceBox, tolerance: Double = 0.001) -> Bool {
        other.x >= x-tolerance && other.y >= y-tolerance && other.x+other.w <= x+w+tolerance && other.y+other.h <= y+h+tolerance
    }
    func clamped() -> SourceBox {
        let width = w.isFinite ? min(1,max(0.02,w)) : 0.68, height = h.isFinite ? min(1,max(0.02,h)) : 0.28
        return SourceBox(x:x.isFinite ? min(1-width,max(0,x)) : 0,y:y.isFinite ? min(1-height,max(0,y)) : 0,w:width,h:height)
    }
}
enum MenuRecognition {
    static let generic: Set<String> = ["settings","options","inventory","back","resume","continue","map","exit","save","load","start","yes","no"]
    static func key(_ value: String) -> String { DialogueText.normalized(value).lowercased() }
    static func match(_ menu: AllowedMenu, lines: [OCRLine]) -> Bool {
        guard menu.enabled, menu.valid else { return false }
        let sorted = lines.filter { menu.region.contains($0.box) && $0.confidence >= 0.8 }.sorted { a,b in abs(a.box.y-b.box.y) < 0.008 ? a.box.x < b.box.x : a.box.y < b.box.y }
        var used = Set<Int>(), indices: [Int] = []
        let anchors = menu.anchors.sorted { a,b in abs(a.box.y-b.box.y) < 0.008 ? a.box.x < b.box.x : a.box.y < b.box.y }
        for anchor in anchors {
            let candidates = sorted.indices.filter { !used.contains($0) && key(sorted[$0].text) == key(anchor.text) && abs(sorted[$0].box.x-anchor.box.x) <= 0.025 && abs(sorted[$0].box.y-anchor.box.y) <= 0.025 && abs(sorted[$0].box.h-anchor.box.h) <= 0.02 }
            guard candidates.count == 1, let index = candidates.first else { return false }
            used.insert(index); indices.append(index)
        }
        return indices == indices.sorted()
    }
    static func recognized(_ menus: [AllowedMenu], lines: [OCRLine]) -> AllowedMenu? {
        let matches = menus.filter { match($0,lines:lines) }
        return matches.count == 1 ? matches.first : nil
    }
}

struct MenuOverlayItem: Codable, Equatable, Identifiable {
    var id: String
    var source: String
    var translated: String
    var box: SourceBox
    var color: String?
}

/// Letterboxed, aspect-fit geometry shared by touch editing and preview overlays.
struct VideoViewport {
    var frameWidth: Double, frameHeight: Double, viewWidth: Double, viewHeight: Double
    var rect: SourceBox {
        guard frameWidth > 0, frameHeight > 0, viewWidth > 0, viewHeight > 0 else { return SourceBox(x:0,y:0,w:0,h:0) }
        let scale = min(viewWidth/frameWidth,viewHeight/frameHeight)
        let w = frameWidth*scale, h = frameHeight*scale
        return SourceBox(x:(viewWidth-w)/2,y:(viewHeight-h)/2,w:w,h:h)
    }
    func normalized(x: Double, y: Double) -> (Double,Double)? {
        let r = rect
        guard r.w > 0, r.h > 0, x >= r.x, y >= r.y, x <= r.x+r.w, y <= r.y+r.h else { return nil }
        return ((x-r.x)/r.w,(y-r.y)/r.h)
    }
}
