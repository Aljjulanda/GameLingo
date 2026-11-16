import XCTest
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif
@testable import LingoCore

final class PackDatabaseTests: XCTestCase {
    private func fixture(_ rows: [(String,String,String)], extraSQL: String? = nil) throws -> (URL,PackManifest) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:folder) }
        let file = folder.appendingPathComponent("translations.sqlite")
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(file.path,&db),SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db,PackDatabase.table,nil,nil,nil),SQLITE_OK)
        for sql in PackDatabase.indexes.values { XCTAssertEqual(sqlite3_exec(db,sql,nil,nil,nil),SQLITE_OK) }
        XCTAssertEqual(sqlite3_exec(db,"PRAGMA user_version=1",nil,nil,nil),SQLITE_OK)
        for (index,row) in rows.enumerated() {
            var statement: OpaquePointer?; XCTAssertEqual(sqlite3_prepare_v2(db,"INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,1)",-1,&statement,nil),SQLITE_OK)
            let values = ["0x\(index)","key\(index)",row.0,PackLookupKey.normalized(row.0),row.1,row.2,"synthetic","[]"]
            for (i,value) in values.enumerated() { value.withCString { _ = sqlite3_bind_text(statement,Int32(i+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) } }
            XCTAssertEqual(sqlite3_step(statement),SQLITE_DONE); sqlite3_finalize(statement)
        }
        if let extraSQL { XCTAssertEqual(sqlite3_exec(db,extraSQL,nil,nil,nil),SQLITE_OK) }
        let manifest = PackManifest(formatVersion:1,schemaVersion:1,gameId:"fixture",gameTitle:"Synthetic fixture",sourceLanguage:"en",targetLanguage:"ar",packVersion:"1",recordCount:rows.count,usableCount:rows.count,categories:Array(Set(rows.map{$0.2})),attribution:"Synthetic tests",permission:"Original synthetic tests",builtAt:"2026-11-14",arabicOrder:"logical",databaseSha256:String(repeating:"0",count:64),speakerNames:[])
        return (file,manifest)
    }
    func testSeededSamplesUseValidatedSourcesAndExistingLookup() throws {
        let (file,_) = try fixture([("Move now.","تحرك الآن.","dialogue"),("Read it.","اقرأها.","general"),("Options","الخيارات","menu")])
        let db = try PackDatabase(url:file)
        let first = try db.sampleSources()
        XCTAssertEqual(first,try db.sampleSources()); XCTAssertEqual(first.count,2)
        XCTAssertFalse(first.contains("Options"))
        for source in first { XCTAssertNotNil(try db.lookup(source,category:"dialogue").text) }
    }
    func testIndexedExactNormalizedAndIdentifierLookup() throws {
        let (file,manifest) = try fixture([("Move now.","تحرك الآن.","dialogue"),("Read the letter.","اقرأ الرسالة.","general"),("Open inventory.","افتح الحقيبة.","menu")])
        let db = try PackDatabase(url:file); try db.validateContents(manifest:manifest)
        XCTAssertEqual(try db.lookup("Move now.",category:"dialogue").kind,.exact)
        XCTAssertEqual(try db.lookup("  MOVE\nnow!",category:"dialogue").text,"تحرك الآن.")
        XCTAssertEqual(try db.lookup("Move now.",category:"document").kind,.missing)
        XCTAssertEqual(try db.lookup("Read the letter.",category:"document").text,"اقرأ الرسالة.")
        XCTAssertEqual(try db.lookupIdentifier("0x0"),["تحرك الآن."])
        XCTAssertEqual(try db.lookup("Open inventory.",category:"document").text,"افتح الحقيبة.")
        XCTAssertNil(try db.lookup("Open inventory.",category:"dialogue").text)
    }
    func testAmbiguityRejectsAllDifferentTranslations() throws {
        let (file,_) = try fixture([("Move now.","تحرك الآن.","dialogue"),("Move now.","انطلق الآن.","dialogue")])
        XCTAssertEqual(try PackDatabase(url:file).lookup("Move now.",category:"dialogue").kind,.ambiguous)
    }
    func testSemanticChangesAndMissingOCRCharacterFallBack() throws {
        let (file,_) = try fixture([("We will go left and collect 10 coins.","سنذهب يسارًا ونجمع 10 قطع.","dialogue")])
        let db = try PackDatabase(url:file)
        for source in ["We will not go left and collect 10 coins.","We will go right and collect 10 coins.","We will go left and collect 11 coins.","He will go left and collect 10 coins.","We will go left and colect 10 coins."] {
            XCTAssertNil(try db.lookup(source,category:"dialogue").text)
        }
    }
    func testUntrustedSchemaViewsAndTriggersAreRejected() throws {
        for sql in ["CREATE VIEW stolen AS SELECT * FROM entries","CREATE VIEW sqliteevil AS SELECT * FROM entries","CREATE TRIGGER surprise AFTER INSERT ON entries BEGIN DELETE FROM entries; END","CREATE TABLE extra(value TEXT)"] {
            let (file,_) = try fixture([("Move.","تحرك.","dialogue")],extraSQL:sql)
            XCTAssertThrowsError(try PackDatabase(url:file))
        }
    }
    func testRecordCountAndManifestVersionsAreValidated() throws {
        let (file,original) = try fixture([("Move.","تحرك.","dialogue")]); var manifest = original
        manifest.recordCount = 2
        XCTAssertThrowsError(try PackDatabase(url:file).validateContents(manifest:manifest))
        manifest = original; manifest.formatVersion = 9; XCTAssertThrowsError(try manifest.validate())
        manifest = original; manifest.gameId = "../outside"; XCTAssertThrowsError(try manifest.validate())
    }
}
