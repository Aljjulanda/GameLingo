import XCTest
@testable import LingoCore

final class GameNamesTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func name(_ english: String = "Arthur", _ arabic: String = "آرثر", _ source: GameNameSource = .manual) -> GameName { GameName(english:english,type:.person,arabic:arabic,source:source,count:1) }
    func testLearningThresholdsDistinctEventsAndNoHUDOrDialogueInference() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at:folder) }
        let store = try GameNamesStore(root:folder,game:"synthetic")
        XCTAssertTrue(try store.learn("Arthur",form:.colon,confidence:0.9,eventID:"1"))
        XCTAssertEqual(store.snapshot.entries.first?.count,1)
        XCTAssertFalse(try store.learn("Arthur",form:.colon,confidence:0.9,eventID:"1"))
        XCTAssertFalse(try store.learn("John",form:.bracket,confidence:0.9,eventID:"2"))
        XCTAssertFalse(try store.learn("John",form:.bracket,confidence:0.9,eventID:"2"))
        XCTAssertTrue(try store.learn("John",form:.bracket,confidence:0.9,eventID:"3"))
        XCTAssertEqual(store.snapshot.entries.first{$0.english == "John"}?.count,2)
        for value in ["Music","Laughing","Health","Objective","Wait","PS5","2026","We should go"] {
            XCTAssertFalse(try store.learn(value,form:.colon,confidence:1,eventID:value),value)
        }
        XCTAssertFalse(try store.learn("Dutch",form:.colon,confidence:0.7,eventID:"4"))
        XCTAssertFalse(try store.learn("Morgan",form:.colon,confidence:1,eventID:"5",colonThreshold:2))
        XCTAssertTrue(try store.learn("Morgan",form:.colon,confidence:1,eventID:"6",colonThreshold:2))
        XCTAssertEqual(try GameNamesStore(root:folder,game:"synthetic").snapshot,store.snapshot)
        XCTAssertTrue(try store.learn("Dutch",form:.colon,confidence:1,eventID:"evidence-id-never-persisted"))
        XCTAssertFalse(String(decoding:try Data(contentsOf:store.file),as:UTF8.self).contains("evidence-id-never-persisted"))
    }
    func testManualSpellingPriorityBlocklistAndGameIsolation() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at:folder) }
        let store = try GameNamesStore(root:folder,game:"a")
        try store.upsert(name("Arthur","ارثور",.auto)); try store.upsert(name("Arthur","آرثر",.pack))
        XCTAssertEqual(store.snapshot.entries.first?.arabic,"آرثر")
        try store.upsert(name("Arthur","آرثر اليدوي"),explicit:true)
        try store.upsert(name("Arthur","تغيير",.pack))
        _ = try store.learn("Arthur",form:.colon,confidence:1,eventID:"id")
        XCTAssertEqual(store.snapshot.entries.first?.arabic,"آرثر اليدوي"); XCTAssertEqual(store.snapshot.entries.first?.source,.manual)
        let other = try GameNamesStore(root:folder,game:"b"); XCTAssertTrue(other.snapshot.entries.isEmpty)
        try store.remove("Arthur"); XCTAssertEqual(store.snapshot.userDeletions,1)
        XCTAssertFalse(try store.learn("Arthur",form:.colon,confidence:1,eventID:"new"))
        try store.upsert(name("Arthur","من الحزمة",.pack)); XCTAssertTrue(store.snapshot.entries.isEmpty)
        try store.upsert(name(),explicit:true); XCTAssertEqual(store.snapshot.entries.count,1)
        XCTAssertTrue(store.snapshot.blocked.isEmpty); XCTAssertEqual(store.snapshot.userDeletions,1)
    }
    func testImportExportProtectionBackupPolicyAndInvalidScopes() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at:folder) }
        XCTAssertThrowsError(try GameNamesStore(root:folder,game:"../outside"))
        let store = try GameNamesStore(root:folder,game:"general")
        try store.upsert(name(),explicit:true); try store.upsert(name("John","جون"),explicit:true); try store.remove("John")
        var incoming = GameNamesSnapshot(game:"general"); incoming.entries = [name("Arthur","تغيير",.pack),name("John","جون",.auto),name("Dutch","داتش",.pack)]
        try store.importData(JSONEncoder().encode(incoming))
        XCTAssertEqual(store.snapshot.entries.first{$0.id == "arthur"}?.arabic,"آرثر")
        XCTAssertNil(store.snapshot.entries.first{$0.id == "john"}); XCTAssertNotNil(store.snapshot.entries.first{$0.id == "dutch"})
        let file = try store.export(); XCTAssertEqual(file.lastPathComponent,"general.json")
        #if os(iOS) || os(macOS)
        XCTAssertEqual(try folder.resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
        #endif
        incoming.game = "other"; XCTAssertThrowsError(try store.importData(JSONEncoder().encode(incoming)))
        incoming.game = "general"; incoming.entries = [name(),name()]; XCTAssertThrowsError(try store.importData(JSONEncoder().encode(incoming)))
    }
    func testCountsDoNotInvalidateOutputButSpellingDoes() throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at:folder) }
        let store = try GameNamesStore(root:folder,game:"general")
        try store.upsert(name()); let version = store.snapshot.version
        _ = try store.learn("Arthur",form:.colon,confidence:1,eventID:"1")
        XCTAssertEqual(store.snapshot.version,version)
        try store.upsert(name("Arthur","آرثر آخر"),explicit:true); XCTAssertGreaterThan(store.snapshot.version,version)
    }
    func testDeterministicEditableTransliteration() {
        for (source,target) in [("Arthur","آرثر"),("John","جون"),("Shawn","شاون"),("Theo","ثيو"),("Chad","تشاد"),("Phil","فيل"),("Lee","لي"),("Cooper","كوبير"),("47","٤٧")] {
            XCTAssertEqual(NameTransliteration.arabic(source),target,source)
        }
    }
    func testSeparateLabelConfidenceIsNotBorrowedFromDialogueBody() throws {
        var q = QualitySettings(); q[.speakerClassification] = true
        let lines = [OCRLine(text:"Arthur",box:SourceBox(x:0.35,y:0.72,w:0.1,h:0.02),confidence:0.4),OCRLine(text:"We must leave now.",box:SourceBox(x:0.30,y:0.76,w:0.4,h:0.03),confidence:0.99)]
        let reading = try XCTUnwrap(StructuredDialogue.resolve(lines,roi:.dialogue,knownNames:"Arthur",quality:q))
        XCTAssertEqual(reading.content.speaker,"Arthur"); XCTAssertEqual(reading.content.speakerConfidence,0.4)
        let folder = root(); defer { try? FileManager.default.removeItem(at:folder) }
        let store = try GameNamesStore(root:folder,game:"general")
        XCTAssertFalse(try store.learn("Arthur",form:.separate,confidence:reading.content.speakerConfidence ?? 0,eventID:"1"))
        XCTAssertTrue(store.snapshot.entries.isEmpty)
    }
    func testChangedPlaceholderAutomaticallyUsesUnprotectedTranslation() throws {
        let source = "Arthur, wait.", names = [name()]
        for form in NamePlaceholderForm.allCases {
            var inputs: [String] = []
            let output = ProtectedNameTranslation.run(source,names:names,form:form) { text in inputs.append(text); return text == source ? "آرثر، انتظر." : "علامة مختلفة" }
            XCTAssertEqual(output,"آرثر، انتظر."); XCTAssertEqual(inputs.count,2); XCTAssertEqual(inputs.last,source)
        }
        var inputs: [String] = []
        _ = ProtectedNameTranslation.run(source,names:names,form:nil) { text in inputs.append(text); return "آرثر، انتظر." }
        XCTAssertEqual(inputs,[source],"OFF has one unchanged engine call")
    }
    func testFourPlaceholderFormsCountFormOrderAndContextGuards() throws {
        for form in NamePlaceholderForm.allCases {
            let plan = try XCTUnwrap(NameProtectionPlan.make("Arthur, follow John.",names:[name(),name("John","جون")],form:form))
            let a = form.marker(0), b = form.marker(1)
            XCTAssertEqual(plan.restore(a+"، اتبع "+b+"."),"آرثر، اتبع جون.")
            XCTAssertTrue(plan.contextUnchanged(a+"، اتبع "+b+".",baseline:"آرثر، اتبع جون."))
            XCTAssertFalse(plan.contextUnchanged(a+"، "+b+".",baseline:"آرثر، اتبع جون."),"Surviving markers do not justify word deletion")
            for invalid in [a+" "+a+" "+b,b+" "+a,a.lowercased()+" "+b,a+" "+b+" GLNAME9",a+" missing","هنا"+a+" "+b] { XCTAssertNil(plan.restore(invalid)) }
        }
    }
    func testCommonWordNamesNeedMidCapitalOrVocativeAndNoPartialMatches() {
        let names = [name("Bill","بيل"),name("Grace","غريس")]
        for source in ["Bill is expensive.","bill, wait.","grace is important.","The billing office is closed.","Willow is here.","\"Bill is expensive.\"","Go. Bill is expensive."] {
            XCTAssertNil(NameProtectionPlan.make(source,names:names,form:.letters),source)
        }
        for source in ["Bill, wait.","I saw Bill.","Please wait for Grace.","Grace!"] {
            XCTAssertNotNil(NameProtectionPlan.make(source,names:names,form:.letters),source)
        }
        XCTAssertNil(NameProtectionPlan.make("GLNAME is a literal.",names:names,form:.letters))
    }
}
