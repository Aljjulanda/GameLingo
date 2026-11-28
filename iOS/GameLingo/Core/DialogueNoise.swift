import Foundation

/// Conservative text evidence only; no additional OCR pass or retained frames.
/// This applies to dialogue, never to the separate menu/document readers.
enum DialogueNoise {
    /// Geometry corroborates known vehicle lettering. Stability by itself never
    /// promotes such a label into speech. Punctuated/labelled speech survives.
    static func vehicleLettering(_ line: OCRLine, roi: SourceBox, knownNames: String) -> Bool {
        let text = DialogueText.normalized(line.text)
        guard line.box.isValid, line.box.w < roi.w*0.30, line.box.h < roi.h*0.28,
              !text.contains(":"), text == text.uppercased(),
              text.last.map({ !".!?؟…".contains($0) }) == true else { return false }
        let labels: Set<String> = ["POLICE","SHERIFF","TAXI","AMBULANCE","PARAMEDIC","PARAMEDICS","FIRE DEPARTMENT","LOS SANTOS POLICE","LOS SANTOS CUSTOMS","SECURITY","DIAL 911","DOWNTOWN CAB CO"]
        let names = Set(knownNames.split(separator:",").map { DialogueText.normalized(String($0)).uppercased() })
        return labels.contains(text) && !names.contains(text)
    }
    private static let plate = try! NSRegularExpression(pattern:
        "^(?:[A-Z]{1,4}[- .]?\\d{2,7}[A-Z]{0,3}|\\d{1,7}[- .]?[A-Z]{1,4}|[A-Z]{1,3}\\d{1,3}[- .]?[A-Z]{1,3}|\\d[A-Z]{2,4}\\d{2,4}|[A-Z]{1,3}[- ]\\d{2,5}[- ][A-Z]{1,3})$")
    private static let hud = try! NSRegularExpression(pattern:
        "^(?:HP|AMMO|FPS|XP|LEVEL|SCORE|LAP|DISTANCE|SPEED)\\s*[:=]?\\s*\\d+(?:[.,]\\d+)?(?:\\s*(?:/\\s*\\d+|M|KM|MPH|KM/H))?$|^\\d+(?:[.,]\\d+)?\\s*(?:MPH|KM/H|FPS)$")
    private static let signs: Set<String> = ["NO PARKING","SPEED LIMIT","ONE WAY","FOR SALE","EXIT ONLY","DO NOT ENTER","AUTHORIZED PERSONNEL ONLY","GAS STATION"]
    // Do not classify short spoken numeric references as registration plates.
    private static let spoken: Set<String> = ["ROOM","UNIT","BUS","ROUTE","FLOOR","LEVEL","SECTOR","WAIT","GO","TAKE","GIVE","GET","NEED","HAVE","IM"]

    static func rejects(_ source: String, spokenNumber: Bool = false) -> Bool {
        var text = DialogueText.normalized(source)
        guard !text.isEmpty else { return true }
        // Strip an inline speaker for classification of its body, so adding a
        // known label cannot turn a registration number into dialogue.
        let parts = text.split(separator:":",maxSplits:1,omittingEmptySubsequences:false)
        if parts.count == 2, !parts[1].trimmingCharacters(in:.whitespaces).isEmpty,
           !parts[0].isEmpty, parts[0].count <= 40,
           parts[0].allSatisfy({ $0.isLetter || $0.isWhitespace || "'-’".contains($0) }) {
            text = parts[1].trimmingCharacters(in:.whitespaces)
        }
        let upper = text.uppercased()
        let range = NSRange(upper.startIndex...,in:upper)
        if hud.firstMatch(in:upper,range:range) != nil { return true }
        if text == upper && signs.contains(upper) { return true }
        let digits = text.filter(\.isNumber).count
        guard digits > 0 else { return false }
        if !text.contains(where: \.isLetter) {
            return !(spokenNumber && text.range(of:"^[+-]?[0-9]{1,8}(?:[.,][0-9]{1,3})?[.!?]?$",options:.regularExpression) != nil)
        }
        guard text.count <= 20 else { return false }
        let words = DialogueText.exactWords(upper).map { $0.uppercased() }
        if words.contains(where:{ spoken.contains($0) }) { return false }
        return plate.firstMatch(in:upper,range:range) != nil
    }
}
