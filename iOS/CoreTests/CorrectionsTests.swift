import XCTest
@testable import LingoCore

final class CorrectionsTests: XCTestCase {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func testExplicitSaveReloadExactNormalizedAndAmbiguity() throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at:root) }
        let store = try GameCorrectionsStore(root:root,game:"synthetic")
        XCTAssertFalse(FileManager.default.fileExists(atPath:store.file.path),"Opening a store must not persist dialogue")
        try store.save(source:"Wait here.",target:"انتظر هنا.")
        var lookup = CorrectionLookup(store.snapshot)
        XCTAssertEqual(lookup.lookup("Wait here."),"انتظر هنا.")
        XCTAssertEqual(lookup.lookup("  WAIT   here.  "),"انتظر هنا.")
        XCTAssertEqual(lookup.lookup("Wait here!"),"انتظر هنا.","Use the existing normalized-key semantics")
        XCTAssertNil(lookup.lookup("Wait there."),"No fuzzy correction matching")
        let version = store.snapshot.version
        try store.save(source:"Wait here.",target:"انتظر هنا.")
        XCTAssertEqual(store.snapshot.version,version,"An unchanged explicit save does not invalidate caches")
        try store.save(source:"WAIT HERE.",target:"ابق هنا.")
        lookup = CorrectionLookup(store.snapshot)
        XCTAssertEqual(lookup.lookup("WAIT HERE."),"ابق هنا.","Exact wins over a normalized collision")
        XCTAssertNil(lookup.lookup("wait here."),"Conflicting normalized targets cannot select arbitrarily")
        XCTAssertEqual(try GameCorrectionsStore(root:root,game:"synthetic").snapshot,store.snapshot)
        let removed = try XCTUnwrap(store.snapshot.entries.first)
        try store.remove(removed.id)
        XCTAssertThrowsError(try store.save(source:removed.source,target:"تعديل قديم",id:removed.id))
        XCTAssertNotEqual(CorrectionLookup(store.snapshot).lookup(removed.source),removed.target)
    }
    func testScopeRolesImportExportAndAtomicRejection() throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at:root) }
        let shared = try GameCorrectionsStore(root:root.appendingPathComponent("general"),game:"general",general:true)
        let game = try GameCorrectionsStore(root:root.appendingPathComponent("games"),game:"general")
        try shared.save(source:"Follow me.",target:"اتبعني.")
        XCTAssertThrowsError(try game.importData(JSONEncoder().encode(shared.snapshot)))
        XCTAssertTrue(game.snapshot.entries.isEmpty)
        let file = try shared.export()
        XCTAssertEqual(file.lastPathComponent,"general.json")
        let incomingRoot = root.appendingPathComponent("incoming")
        let incoming = try GameCorrectionsStore(root:incomingRoot,game:"general",general:true)
        try incoming.importData(UserDataFile.read(file))
        XCTAssertEqual(CorrectionLookup(incoming.snapshot).lookup("Follow me."),"اتبعني.")
        try incoming.save(source:"Follow me.",target:"سر خلفي.")
        let prior = shared.snapshot, id = prior.entries[0].id
        try shared.importData(JSONEncoder().encode(incoming.snapshot))
        XCTAssertEqual(shared.snapshot.entries[0].id,id)
        XCTAssertEqual(shared.snapshot.entries[0].target,"سر خلفي.")
        var invalid = incoming.snapshot; invalid.entries.append(invalid.entries[0])
        let unchanged = shared.snapshot
        XCTAssertThrowsError(try shared.importData(JSONEncoder().encode(invalid)))
        XCTAssertEqual(shared.snapshot,unchanged)
        invalid.entries = incoming.snapshot.entries; invalid.entries[0].normalized = "forged"
        XCTAssertThrowsError(try shared.importData(JSONEncoder().encode(invalid)))
        XCTAssertThrowsError(try shared.save(source:"bad\0source",target:"نص"))
        XCTAssertThrowsError(try shared.save(source:"Valid",target:"\u{202E}نص"))
        XCTAssertThrowsError(try GameCorrectionsStore(root:root,game:"../outside"))
        #if os(iOS) || os(macOS)
        XCTAssertEqual(try file.deletingLastPathComponent().resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
        #endif
    }
    func testRecentPublishedLinesStayBoundedInRAMAndClearOnStopOrScope() {
        var recent = RecentPublishedLines(); recent.select("game/a")
        for index in 0..<25 { recent.published(RecentPublishedLine(id:String(index),scope:"game/a",source:"Synthetic \(index)",target:"نص",origin:.argosInference)) }
        XCTAssertEqual(recent.entries.count,20); XCTAssertEqual(recent.entries.first?.id,"5")
        recent.published(RecentPublishedLine(id:"24",scope:"game/a",source:"Synthetic 24",target:"تعديل",origin:.userCorrection))
        XCTAssertEqual(recent.entries.count,20); XCTAssertEqual(recent.entries.last?.target,"تعديل")
        recent.published(RecentPublishedLine(id:"late",scope:"game/b",source:"Ignored",target:"نص",origin:.rule))
        XCTAssertEqual(recent.entries.count,20)
        recent.select("game/b"); XCTAssertTrue(recent.entries.isEmpty)
        recent.published(RecentPublishedLine(id:"1",scope:"game/b",source:"New",target:"نص",origin:.rule))
        recent.clear(); XCTAssertTrue(recent.entries.isEmpty)
        XCTAssertTrue(RecentPublishedLines().entries.isEmpty,"App restart has no persisted recent history")
    }
}
