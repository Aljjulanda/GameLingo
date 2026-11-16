import XCTest
import Foundation
@testable import GameLingo

final class NamesIntegrationTests: XCTestCase {
    func testNamesFileProtectionWhenRuntimeReportsIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try GameNamesStore(root:root,game:"general")
        try store.upsert(GameName(english:"Arthur",type:.person,arabic:"آرثر",source:.manual,count:1),explicit:true)
        let raw = try FileManager.default.attributesOfItem(atPath:store.file.path)[.protectionKey]
        let actual = (raw as? FileProtectionType)?.rawValue ?? raw as? String
        #if targetEnvironment(simulator)
        if actual == nil {
            let control = root.appendingPathComponent("synthetic-control")
            try Data("synthetic".utf8).write(to:control,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:control.path)
            let direct = try FileManager.default.attributesOfItem(atPath:control.path)[.protectionKey]
            guard raw == nil && direct == nil else { XCTFail("Control reports protection while names do not"); return }
            throw XCTSkip("Simulator omits file-protection metadata for both names and direct Foundation control; physical protection remains a separate check")
        }
        #endif
        XCTAssertEqual(actual,FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
    }
    func testRealArgosFourPlaceholderFormsAndSurroundingWordControls() throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        var error: NSError?
        let engine = try XCTUnwrap(GLTranslation(modelPath:folder.path,error:&error))
        let names = [("Arthur","آرثر"),("John","جون"),("Bill","بيل"),("Grace","غريس")].map { GameName(english:$0.0,type:.person,arabic:$0.1,source:.manual,count:1) }
        let fixtures = ["Arthur, wait here.","Please follow John.","I saw Bill.","Grace, open the door.","Arthur, follow John."]
        var survival: [String:Int] = [:], unchanged: [String:Int] = [:], unsafe: [String:Int] = [:]
        var probes = 0
        for source in fixtures {
            let baseline = try XCTUnwrap(engine.translate(source,error:&error))
            for form in NamePlaceholderForm.allCases {
                let plan = try XCTUnwrap(NameProtectionPlan.make(source,names:names,form:form))
                let start = ProcessInfo.processInfo.systemUptime
                let output = try XCTUnwrap(engine.translate(plan.input,error:&error))
                let restored = plan.restore(output), same = plan.contextUnchanged(output,baseline:baseline)
                var calls: [String] = []
                let actual = try ProtectedNameTranslation.run(source,names:names,form:form) { input in calls.append(input); return try XCTUnwrap(engine.translate(input,error:&error)) }
                if let restored {
                    survival[form.rawValue,default:0] += 1
                    if same { unchanged[form.rawValue,default:0] += 1 } else { unsafe[form.rawValue,default:0] += 1 }
                    XCTAssertEqual(actual,restored); XCTAssertEqual(calls.count,1)
                } else { XCTAssertEqual(actual,baseline); XCTAssertEqual(calls.count,2); XCTAssertEqual(calls.last,source) }
                let report: [String:Any] = ["form":form.rawValue,"synthetic_source":source,"baseline":baseline,"protected_output":output,"restored":restored ?? "REJECTED","survived":restored != nil,"surrounding_unchanged":same,"milliseconds":(ProcessInfo.processInfo.systemUptime-start)*1000]
                let data = try JSONSerialization.data(withJSONObject:report,options:.sortedKeys)
                print("SYNTHETIC_NAME_PROBE "+String(decoding:data,as:UTF8.self)); probes += 1
            }
        }
        XCTAssertEqual(probes,20)
        print("SYNTHETIC_NAME_FORMS survived=\(survival) context_unchanged=\(unchanged) unsafe_survivors=\(unsafe); Intel Simulator FLOAT32, not phone INT8")
    }
    func testNamesStoreBackupAndRealTranslatorCacheInvalidation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try GameNamesStore(root:root,game:"synthetic-a")
        try store.upsert(GameName(english:"Arthur",type:.person,arabic:"آرثر",source:.manual,count:1),explicit:true)
        XCTAssertEqual(try root.resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:folder)
        let loaded: Result<Void,Error> = await withCheckedContinuation { translator.load(completion:$0.resume(returning:)) }; try loaded.get()
        func translate() async throws -> TranslationDecision {
            let result: Result<TranslationDecision,Error> = await withCheckedContinuation { continuation in translator.translateDetailed("Where are you going?") { value,_ in continuation.resume(returning:value) } }
            return try result.get()
        }
        translator.configureNames(store.snapshot,protection:false)
        let first = try await translate(), cached = try await translate()
        XCTAssertEqual(first.origin,.argosInference); XCTAssertEqual(cached.origin,.argosCache)
        try store.upsert(GameName(english:"Arthur",type:.person,arabic:"آرثر المعدّل",source:.manual,count:1),explicit:true)
        translator.configureNames(store.snapshot,protection:false)
        let changed = try await translate(); XCTAssertEqual(changed.origin,.argosInference); XCTAssertEqual(changed.text,first.text)
        translator.configureNames(GameNamesSnapshot(game:"synthetic-b"),protection:false)
        let nextGame = try await translate(); XCTAssertEqual(nextGame.origin,.argosInference)
    }
    @MainActor func testNamesLibraryKeepsGamesManualEditsAndDeletedNamesSeparate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library = GameNamesLibrary(root:root)
        let name = GameName(english:"Arthur",type:.person,arabic:"آرثر",source:.manual,count:1)
        library.select("synthetic-a"); XCTAssertTrue(library.save(name))
        library.select("synthetic-b"); XCTAssertTrue(library.snapshot.entries.isEmpty)
        library.select("synthetic-a"); XCTAssertEqual(library.snapshot.entries.first?.source,.manual)
        library.remove(name); library.seed([("Arthur","من الحزمة")]); XCTAssertTrue(library.snapshot.entries.isEmpty)
        XCTAssertEqual(library.snapshot.userDeletions,1)
    }
}
