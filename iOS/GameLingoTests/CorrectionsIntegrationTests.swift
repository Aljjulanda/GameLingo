import XCTest
@testable import GameLingo

final class CorrectionsIntegrationTests: XCTestCase {
    private func result(_ translator: OfflineTranslator, _ source: String) async throws -> TranslationDecision {
        let value: Result<TranslationDecision,Error> = await withCheckedContinuation { continuation in
            translator.translateDetailed(source) { result,_ in continuation.resume(returning:result) }
        }
        return try value.get()
    }
    func testCorrectionBypassesMissingModelAndRollbackCannotReuseIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try GameCorrectionsStore(root:root,game:"synthetic")
        let translator = OfflineTranslator(folder:root.appendingPathComponent("no-model"))
        XCTAssertFalse(translator.installed)
        try store.save(source:"We should leave.",target:"حان وقت الرحيل.")
        translator.configureCorrections(store.snapshot,enabled:true)
        let corrected = try await result(translator,"WE SHOULD LEAVE.")
        XCTAssertEqual(corrected.origin,.userCorrection); XCTAssertEqual(corrected.text,"حان وقت الرحيل.")
        translator.configureCorrections(store.snapshot,enabled:false)
        do { _ = try await result(translator,"WE SHOULD LEAVE."); XCTFail("OFF must use the unavailable legacy engine, never the saved correction") } catch { XCTAssertFalse(error is CancellationError) }
        translator.configureCorrections(store.snapshot,enabled:true)
        try store.remove(store.snapshot.entries[0].id)
        translator.configureCorrections(store.snapshot,enabled:true)
        do { _ = try await result(translator,"WE SHOULD LEAVE."); XCTFail("Deleted correction cannot survive in a cache") } catch { XCTAssertFalse(error is CancellationError) }
    }
    func testRealArgosCacheIsInvalidatedAcrossCorrectionEditDeleteFlagAndScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try GameCorrectionsStore(root:root,game:"synthetic")
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:folder)
        let loaded: Result<Void,Error> = await withCheckedContinuation { translator.load(completion:$0.resume(returning:)) }; try loaded.get()
        let source = "Where are you going?"
        translator.configureCorrections(store.snapshot,enabled:false)
        let original = try await result(translator,source)
        let cached = try await result(translator,source)
        XCTAssertEqual(original.origin,.argosInference); XCTAssertEqual(cached.origin,.argosCache)
        try store.save(source:source,target:"إلى أين تتجه؟")
        translator.configureCorrections(store.snapshot,enabled:true)
        let edit = try await result(translator,source); XCTAssertEqual(edit.origin,.userCorrection)
        XCTAssertEqual(edit.text,"إلى أين تتجه؟")
        try store.save(source:source,target:"أين وجهتك؟")
        translator.configureCorrections(store.snapshot,enabled:true)
        let changed = try await result(translator,source); XCTAssertEqual(changed.text,"أين وجهتك؟")
        translator.configureCorrections(store.snapshot,enabled:false)
        let off = try await result(translator,source)
        XCTAssertEqual(off.origin,.argosInference); XCTAssertEqual(off.text,original.text)
        translator.configureCorrections(CorrectionsSnapshot(game:"other"),enabled:true)
        let other = try await result(translator,source)
        XCTAssertEqual(other.origin,.argosInference); XCTAssertEqual(other.text,original.text)
        try store.remove(store.snapshot.entries[0].id)
        translator.configureCorrections(store.snapshot,enabled:true)
        let removed = try await result(translator,source)
        XCTAssertEqual(removed.origin,.argosInference); XCTAssertEqual(removed.text,original.text)
    }
    @MainActor func testRecentLibraryExplicitSaveScopeAndStopSemantics() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library = CorrectionsLibrary(root:root)
        library.select("a")
        let line = RecentPublishedLine(id:"published",scope:library.snapshot.scopeKey,source:"Wait here.",target:"انتظر هنا.",origin:.argosInference)
        let beforeStop = library.historyToken
        library.published(line,token:beforeStop)
        XCTAssertEqual(library.recent.count,1); XCTAssertTrue(library.snapshot.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:try XCTUnwrap(library.store).file.path))
        XCTAssertTrue(library.save(source:line.source,target:"ابق هنا."))
        library.clearRecent(); XCTAssertTrue(library.recent.isEmpty); XCTAssertEqual(library.snapshot.entries.count,1)
        library.published(line,token:beforeStop)
        XCTAssertTrue(library.recent.isEmpty,"A queued callback from before Stop cannot refill the cleared list")
        library.select("b"); XCTAssertTrue(library.recent.isEmpty); XCTAssertTrue(library.snapshot.entries.isEmpty)
        library.published(line,token:library.historyToken); XCTAssertTrue(library.recent.isEmpty,"A late publication from the previous game cannot enter the new scope")
        library.select("a"); XCTAssertEqual(library.snapshot.entries.first?.target,"ابق هنا.")
        library.published(line,token:beforeStop); XCTAssertTrue(library.recent.isEmpty,"Returning to the same game cannot revive a prior session callback")
        XCTAssertTrue(CorrectionsLibrary(root:root).recent.isEmpty,"Recent dialogue never survives an app/library restart")
        library.select(nil); XCTAssertTrue(library.save(source:"General",target:"عام"))
        library.select("general"); XCTAssertTrue(library.snapshot.entries.isEmpty)
    }
}
