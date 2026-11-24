import Foundation

enum DisplayDestination: String, Codable, CaseIterable {
    case phone, television, both
    var phoneEnabled: Bool { self != .television }
    var tvEnabled: Bool { self != .phone }
    var title: String { switch self { case .phone: return "الآيفون فقط"; case .television: return "التلفزيون فقط"; case .both: return "كلاهما" } }
}

struct GameOptions: Codable, Equatable {
    var display = TVSettings()
    var dialogueRegion = SourceBox.dialogue
    var manualDialogueRegion = false
    var menuRegion = SourceBox(x:0.05,y:0.1,w:0.9,h:0.8)
    var destination = DisplayDestination.television
    var modelID = "argos-en_ar-1.0"
    var packEnabled = true
    var advanced = AdvancedSettings()
    var quality = QualitySettings()
    var menusEnabled = false
    var allowedMenus: [AllowedMenu] = []
    var currentMenuAppearance: MenuAppearance?
    var suggestMenus: Bool?
    var valid: Bool { dialogueRegion.isValid && menuRegion.isValid && modelID == "argos-en_ar-1.0" && allowedMenus.count <= 32 && allowedMenus.allSatisfy(\.valid) && (currentMenuAppearance?.valid ?? true) }
}

struct GameProfile: Codable, Identifiable {
    var id: String
    var title: String
    var enabled = true
    var options = GameOptions()
    var previous: GameOptions?
    var effective: GameOptions { enabled ? options : GameOptions() }
}

/// Separate from names/corrections: migration never rewrites either existing store.
/// One bounded, atomic file contains the profiles and one undo per game.
final class GameProfileStore {
    private(set) var profiles: [GameProfile] = []
    private let file: URL
    init(root: URL) throws {
        file = root.appendingPathComponent("profiles-v1.json")
        if FileManager.default.fileExists(atPath:file.path) {
            profiles = try JSONDecoder().decode([GameProfile].self,from:UserDataFile.read(file))
            guard profiles.count <= 64, Set(profiles.map(\.id)).count == profiles.count,
                  profiles.allSatisfy({ UserDataFile.validGame($0.id) && !$0.title.isEmpty && $0.title.count <= 100 && $0.options.valid && ($0.previous?.valid ?? true) }) else { throw LingoError.invalid("ملفات الألعاب غير صالحة؛ حُفظ الأصل دون تغيير") }
        }
    }
    func profile(_ id: String) -> GameProfile? { profiles.first { $0.id == id } }
    private func commit(_ next: [GameProfile]) throws { try UserDataFile.write(JSONEncoder().encode(next),to:file); profiles = next }
    func ensure(_ id: String, title: String, migration: GameOptions? = nil, packEnabled: Bool = true) throws {
        guard UserDataFile.validGame(id), !title.isEmpty, title.count <= 100, profiles.count < 64 || profile(id) != nil else { throw LingoError.invalid("معرّف أو اسم اللعبة غير صالح") }
        guard profile(id) == nil else { return }
        var value = GameProfile(id:id,title:title)
        value.options.packEnabled = packEnabled
        // Only the first selected scope receives the legacy global configuration.
        if profiles.isEmpty, let migration, migration.valid { value.options = migration }
        try commit(profiles+[value])
    }
    func update(_ id: String, options: GameOptions) throws {
        guard options.valid, let index = profiles.firstIndex(where:{ $0.id == id }) else { throw LingoError.invalid("إعدادات اللعبة غير صالحة") }
        var before = profiles[index].options, after = options
        // Wire revisions belong to the connection's monotonic style clock, not
        // to user intent. Rebasing a saved game must not consume its undo.
        before.display.revision = 0; after.display.revision = 0
        guard before != after else { return }
        var next = profiles; next[index].previous = next[index].options; next[index].options = options; try commit(next)
    }
    func enable(_ id: String, _ value: Bool) throws { guard let index = profiles.firstIndex(where:{$0.id == id}) else { return }; var next = profiles; next[index].enabled = value; try commit(next) }
    func rename(_ id: String, _ title: String) throws {
        guard !title.isEmpty, title.count <= 100, let index = profiles.firstIndex(where:{$0.id == id}) else { throw LingoError.invalid("اسم اللعبة غير صالح") }
        var next = profiles; next[index].title = title; try commit(next)
    }
    func reset(_ id: String) throws { try update(id,options:GameOptions()) }
    func undo(_ id: String) throws { if let previous = profile(id)?.previous { try update(id,options:previous) } }
}
