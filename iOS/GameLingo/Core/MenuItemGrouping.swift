import Foundation

enum MenuItemGrouping {
    /// Join only a close continuation with the same left edge. Widely spaced
    /// rows, columns and values remain independent current-frame observations.
    static func rows(_ input: [OCRLine], maximumCharacters: Int = 120, minimumWrapLength: Int = 0) -> [OCRLine] {
        let sorted = input.sorted { a,b in abs(a.box.y-b.box.y) < 0.008 ? a.box.x < b.box.x : a.box.y < b.box.y }
        var groups: [[OCRLine]] = []
        for line in sorted {
            if let group = groups.last, let previous = group.last, let first = group.first,
               group.count < 3, first.text.count >= minimumWrapLength, abs(first.box.x-line.box.x) < 0.008,
               line.box.y >= previous.box.y+previous.box.h,
               line.box.y-previous.box.y-previous.box.h <= min(0.008,previous.box.h*0.25),
               previous.box.w >= line.box.w*0.7, !previous.text.hasSuffix(":"),
               (minimumWrapLength == 0 ? first.text.count : group.reduce(0,{$0+$1.text.count}))+line.text.count <= maximumCharacters {
                groups[groups.count-1].append(line)
            } else { groups.append([line]) }
        }
        return groups.map { group in OCRLine(text:group.map(\.text).joined(separator:" "),box:StructuredDialogue.union(group),confidence:group.map(\.confidence).min() ?? 0) }
    }
}
