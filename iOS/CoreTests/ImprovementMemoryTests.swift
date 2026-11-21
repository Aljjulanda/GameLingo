import XCTest
@testable import LingoCore

final class ImprovementMemoryTests: XCTestCase {
    func example() -> ImprovementExample { ImprovementExample(game:"game-a",source:"Do not take 11 coins.",context:"Arthur|We must leave.",confidence:0.95,observations:2,trustedTarget:"لا تأخذ 11 قطعة نقدية.",authority:"pack-exact:fixture") }
    func testSelfAgreementOCRNoiseNumbersNegationAndConflictsCannotPass() {
        let example = example()
        XCTAssertNil(ImprovementGate.rejection(example,candidate:example.trustedTarget!,existing:[]))
        var selfAgreement = example; selfAgreement.authority = "model-self"
        XCTAssertNotNil(ImprovementGate.rejection(selfAgreement,candidate:example.trustedTarget!,existing:[]))
        var noisy = example; noisy.confidence = 0.7
        XCTAssertNotNil(ImprovementGate.rejection(noisy,candidate:example.trustedTarget!,existing:[]))
        XCTAssertNotNil(ImprovementGate.rejection(example,candidate:"خذ 11 قطعة نقدية.",existing:[]))
        var wrongReference = example; wrongReference.trustedTarget = "خذ 12 قطعة نقدية."
        XCTAssertNotNil(ImprovementGate.rejection(wrongReference,candidate:wrongReference.trustedTarget!,existing:[]))
        wrongReference.trustedTarget = "خذ 11 قطعة نقدية."
        XCTAssertNotNil(ImprovementGate.rejection(wrongReference,candidate:wrongReference.trustedTarget!,existing:[]))
        let conflict = ApprovedMemoryEntry(id:UUID().uuidString,game:example.game,source:example.source,context:example.context,target:"مختلف",authority:example.authority!,model:example.model)
        XCTAssertNotNil(ImprovementGate.rejection(example,candidate:example.trustedTarget!,existing:[conflict]))
    }
    func testConsentBoundedCycleIsolationRetentionAndRollbackPreserveExplicitCorrections() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try ImprovementMemoryStore(root:root)
        let example = example()
        try store.observe(example,consent:false); XCTAssertTrue(store.raw.isEmpty)
        try store.observe(example,consent:true)
        XCTAssertTrue(try store.record(example,candidate:example.trustedTarget!))
        XCTAssertFalse(try store.record(example,candidate:example.trustedTarget!))
        let snapshot = ImprovedMemorySnapshot(entries:store.approved)
        XCTAssertEqual(snapshot.lookup(game:example.game,source:example.source,context:example.context),example.trustedTarget)
        XCTAssertNil(snapshot.lookup(game:"game-b",source:example.source,context:example.context))
        XCTAssertNil(snapshot.lookup(game:example.game,source:example.source,context:"another speaker"))
        XCTAssertNil(snapshot.lookup(game:example.game,source:"Do take 11 coins.",context:example.context))
        let exported = try store.export(); XCTAssertTrue(FileManager.default.fileExists(atPath:exported.path))
        try store.deleteCollected(); XCTAssertFalse(FileManager.default.fileExists(atPath:exported.path)); XCTAssertEqual(store.approved.count,1)
        try store.rollbackApproved(); XCTAssertTrue(store.approved.isEmpty)
        var old = example; old.created = Date(timeIntervalSince1970:0)
        try store.observe(old,consent:true); try store.prune(); XCTAssertTrue(store.raw.isEmpty)
    }
}
