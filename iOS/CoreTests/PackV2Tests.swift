import XCTest
@testable import LingoCore
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

final class PackV2Tests: XCTestCase {
    private func fixture(_ rows: [(String,String)]) throws -> (URL,PackManifest) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("original.sqlite")
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path,&db),SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in [PackDatabase.table]+PackDatabase.indexes.values.sorted()+["PRAGMA user_version=1"] {
            XCTAssertEqual(sqlite3_exec(db,sql,nil,nil,nil),SQLITE_OK)
        }
        for (index,row) in rows.enumerated() {
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(db,"INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,1)",-1,&statement,nil),SQLITE_OK)
            for (column,text) in ["id\(index)","source\(index)",row.0,PackLookupKey.normalized(row.0),row.1,"dialogue","synthetic","[]"].enumerated() {
                XCTAssertEqual(text.withCString {sqlite3_bind_text(statement,Int32(column+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))},SQLITE_OK)
            }
            XCTAssertEqual(sqlite3_step(statement),SQLITE_DONE); sqlite3_finalize(statement)
        }
        return (url,PackManifest(formatVersion:1,schemaVersion:1,gameId:"synthetic",gameTitle:"Synthetic pack",sourceLanguage:"en",targetLanguage:"ar",packVersion:"1",recordCount:rows.count,usableCount:rows.count,categories:["dialogue"],attribution:"Authored tests",permission:"Authored tests",builtAt:"2026-11-20",arabicOrder:"logical",databaseSha256:String(repeating:"0",count:64)))
    }
    private func upgrade(_ url: URL, _ original: PackManifest) throws -> (URL,PackManifest) {
        let source = try PackDatabase(url:url); try source.validateContents(manifest:original)
        let output = url.deletingLastPathComponent().appendingPathComponent("quality.sqlite")
        var manifest = original; manifest.schemaVersion = 2
        manifest.quality = try PackV2Builder.build(from:source,to:output)
        try manifest.validate(); try PackDatabase(url:output).validateContents(manifest:manifest)
        return (output,manifest)
    }
    private func mutate(_ url: URL, _ sql: String) {
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path,&db),SQLITE_OK)
        defer { sqlite3_close(db) }; XCTAssertEqual(sqlite3_exec(db,sql,nil,nil,nil),SQLITE_OK)
    }
    func testV1RemainsReadableAndV2AllOffMatchesEveryLegacyResult() throws {
        let (original,manifest) = try fixture([("Arthur: ~z~Stay~n~here.","Arthur: <C>ابق هنا.</C>"),("Where are you going?","إلى أين تذهب؟")])
        let bytes = try Data(contentsOf:original)
        let legacy = try PackDatabase(url:original), (output,_) = try upgrade(original,manifest), candidate = try PackDatabase(url:output)
        for source in ["Arthur: ~z~Stay~n~here.","Where are you going?","WHERE ARE YOU GOING?","Stay here.","Not present."] {
            let before = try legacy.lookup(source,category:"dialogue"), after = try candidate.lookup(source,category:"dialogue")
            XCTAssertEqual(after.kind,before.kind); XCTAssertEqual(after.text,before.text)
        }
        XCTAssertEqual(try Data(contentsOf:original),bytes)
        XCTAssertNil(try legacy.lookup("Stay here.",category:"dialogue",quality:PackQualityOptions(markup:true,labels:true,punctuation:true)).text)
    }
    func testIndependentProfilesAndRollbackDoNotShareCachedResults() throws {
        let (original,manifest) = try fixture([("Arthur: ~z~Stay~n~here.","Arthur: <C>ابق هنا.</C>")])
        let (output,report) = try upgrade(original,manifest), db = try PackDatabase(url:output)
        XCTAssertEqual(report.quality?.rawUsable,1); XCTAssertEqual(report.quality?.cleaned,1)
        XCTAssertEqual(report.quality?.speakerNames,["Arthur"])
        let samples = try db.sampleSources(quality:PackQualityOptions(markup:true,labels:true))
        XCTAssertEqual(samples,["Stay here."])
        XCTAssertNotNil(try db.lookup(try XCTUnwrap(samples.first),category:"dialogue",quality:PackQualityOptions(markup:true,labels:true)).text)
        XCTAssertEqual(try db.lookup("Stay here.",category:"dialogue",quality:PackQualityOptions(markup:true,labels:true)).text,"ابق هنا.")
        XCTAssertNil(try db.lookup("Stay here.",category:"dialogue").text)
        XCTAssertEqual(try db.lookup("Arthur: Stay here.",category:"dialogue",quality:PackQualityOptions(markup:true)).text,"Arthur: ابق هنا.")
        XCTAssertEqual(try db.lookup("~z~Stay~n~here.",category:"dialogue",quality:PackQualityOptions(labels:true)).text,"<C>ابق هنا.</C>")
        XCTAssertEqual(try db.lookup("Arthur: ~z~Stay~n~here.",category:"dialogue").text,"Arthur: <C>ابق هنا.</C>")
    }
    func testPunctuationTierRequiresV2AndFlagAndRejectsAmbiguity() throws {
        let (original,manifest) = try fixture([("Where, now?","إلى أين الآن؟"),("Wait, here?","أأنتظر هنا؟"),("Wait here!","انتظر هنا!")])
        let (output,_) = try upgrade(original,manifest), db = try PackDatabase(url:output)
        let enabled = PackQualityOptions(punctuation:true)
        XCTAssertNil(try db.lookup("Where now:",category:"dialogue").text)
        let match = try db.lookup("Where now:",category:"dialogue",quality:enabled)
        XCTAssertEqual(match.kind,.punctuationless); XCTAssertEqual(match.text,"إلى أين الآن؟")
        XCTAssertEqual(try db.lookup("Wait; here:",category:"dialogue",quality:enabled).kind,.ambiguous)
        XCTAssertEqual(try db.lookup("Wait here!",category:"dialogue",quality:enabled).kind,.exact)
        XCTAssertNil(try db.lookup("Where now:",category:"dialogue").text)
        XCTAssertNil(try PackDatabase(url:original).lookup("Where now:",category:"dialogue",quality:enabled).text)
    }
    func testAmbiguousNormalizedTierNeverFallsThroughToPunctuation() throws {
        let (original,manifest) = try fixture([("Stay here.","ابق هنا."),("STAY HERE!","انتظر هنا!")])
        let (output,_) = try upgrade(original,manifest)
        let result = try PackDatabase(url:output).lookup("stay here",category:"dialogue",quality:PackQualityOptions(punctuation:true))
        XCTAssertEqual(result.kind,.ambiguous); XCTAssertNil(result.text)
    }
    func testArabicLabelRemovalRequiresAnIndependentExactAlignedNamePair() throws {
        let (original,manifest) = try fixture([("Arthur: Stay here.","آرثر: ابق هنا."),("Arthur","آرثر"),("John: Stay here.","جون: ابق هنا.")])
        let (output,_) = try upgrade(original,manifest), db = try PackDatabase(url:output)
        let options = PackQualityOptions(labels:true)
        // Two label-stripped rows now share the same key but different targets;
        // ambiguity must remain a rejection, never a random pick.
        XCTAssertEqual(try db.lookup("Stay here.",category:"dialogue",quality:options).kind,.ambiguous)
        var variants: [String:String] = [:]
        try db.forEachRawRow { _,row,_ in
            if let label = PackQualityPolicy.label(row.source), let value = try db.qualityVariants(row).first(where:{$0.0 == 2})?.1 { variants[label.name] = value.target }
        }
        XCTAssertEqual(variants["Arthur"],"ابق هنا."); XCTAssertEqual(variants["John"],"جون: ابق هنا.")
        XCTAssertEqual(try db.lookup("Arthur: Stay here.",category:"dialogue").text,"آرثر: ابق هنا.")
    }
    func testDerivedRowsKeysAndReportsAreValidatedNotTrusted() throws {
        for sql in ["UPDATE quality_variants SET target='تغيير غير موثوق' WHERE profile=1", "DELETE FROM quality_variants WHERE profile=3", "UPDATE entries SET punctuationless='wrong'", "INSERT INTO quality_variants SELECT 99,profile,source,normalized,target,flags,usable,punctuationless FROM quality_variants WHERE profile=1"] {
            let (original,manifest) = try fixture([("Arthur: Stay here.","<C>ابق هنا.</C>")])
            let (output,upgraded) = try upgrade(original,manifest)
            mutate(output,sql); XCTAssertThrowsError(try PackDatabase(url:output).validateContents(manifest:upgraded))
        }
        let (original,manifest) = try fixture([("Arthur: Stay here.","<C>ابق هنا.</C>")])
        let (output,upgraded) = try upgrade(original,manifest)
        var wrong = upgraded; wrong.quality?.cleaned = 0
        XCTAssertThrowsError(try PackDatabase(url:output).validateContents(manifest:wrong))
        XCTAssertThrowsError(try PackDatabase(url:output).validateContents(manifest:manifest))
    }
    func testCancelledUpgradeLeavesOriginalAndRemovesOnlyNewOutput() throws {
        let (original,manifest) = try fixture([("Stay here.","ابق هنا.")])
        let bytes = try Data(contentsOf:original), source = try PackDatabase(url:original)
        try source.validateContents(manifest:manifest)
        let output = original.deletingLastPathComponent().appendingPathComponent("cancelled.sqlite")
        XCTAssertThrowsError(try PackV2Builder.build(from:source,to:output,check:{throw CancellationError()}))
        XCTAssertFalse(FileManager.default.fileExists(atPath:output.path)); XCTAssertEqual(try Data(contentsOf:original),bytes)
        XCTAssertThrowsError(try PackV2Builder.build(from:source,to:original))
        XCTAssertEqual(try Data(contentsOf:original),bytes)
    }
}
