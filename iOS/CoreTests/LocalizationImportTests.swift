import XCTest
@testable import LingoCore

final class LocalizationImportTests: XCTestCase {
    private func parsed(_ text: String, _ format: LocalizationFileFormat) throws -> ParsedLocalization {
        let control = LocalizationImportControl()
        return try EnglishArabicMatcher.match(LocalizationAdapters.parse(Data(text.utf8),format:format,control:control),control:control)
    }
    func testSignaturesDoNotUseExtensions() {
        let samples: [(Data,LocalizationFileFormat)] = [
            (Data([0x50,0x4b,3,4]),.zip),(Data([0x52,0x61,0x72,0x21,0x1a,7,1,0]),.rar),
            (Data([0x37,0x7a,0xbc,0xaf,0x27,0x1c]),.sevenZip),(Data([0x4d,0x5a,0,0]),.pe),
            (Data("UnityFS\0".utf8),.unity),(Data("TKEY".utf8),.gxt2),
            (Data("{broken json".utf8),.json),(Data("<broken xml".utf8),.xml),
            (Data("msgid \"Hi\"\nmsgstr \"مرحبا\"".utf8),.po),
            (Data("source,target\nHello,مرحبا".utf8),.csv),(Data([0xff,0,0xff]),.binary),(Data(),.empty)]
        for (data,expected) in samples { XCTAssertEqual(LocalizationFormatDetector.detect(data),expected) }
    }
    func testJSONExplicitPairsAndParallelLanguageMaps() throws {
        let value = try parsed(#"{"game_id":"example","attribution":"Original author","license":"Custom terms","entries":[{"id":"1","source":"Move now.","target":"تحرك الآن."}]}"#,.json)
        XCTAssertEqual(value.records.first?.target,"تحرك الآن."); XCTAssertEqual(value.metadata["license"],"Custom terms")
        let maps = try parsed(#"{"en":{"abc":"Move now."},"ar":{"abc":"تحرك الآن.","other":"نص"}}"#,.json)
        XCTAssertEqual(maps.records.first?.id,"abc")
        XCTAssertThrowsError(try parsed(#"{"MENU_PLAY":"ابدأ","0x00001234":"تحرك"}"#,.json))
    }
    func testJSONMalformedDepthAndNoRecords() throws {
        for text in ["{broken",String(repeating:"[",count:33)+"0"+String(repeating:"]",count:33)] {
            XCTAssertThrowsError(try parsed(text,.json))
        }
        XCTAssertThrowsError(try parsed("{}",.json))
        XCTAssertThrowsError(try LocalizationFormatDetector.decodeText(Data([0xff,0x80])))
    }
    func testCSVQuotesNewlinesAndTSV() throws {
        let csv = "id,source,target\r\n1,\"Hello, friend.\",\"مرحبا، يا صديقي.\"\r\n"
        XCTAssertEqual(try parsed(csv,.csv).records.first?.source,"Hello, friend.")
        XCTAssertEqual(try parsed("en\tar\nMove now.\tتحرك الآن.\n",.csv).records.count,1)
        XCTAssertEqual(try parsed("source;target\nMove now.;تحرك الآن.\n",.csv).records.count,1)
        XCTAssertThrowsError(try parsed("source,target\n\"unclosed,نص",.csv))
        XCTAssertThrowsError(try parsed("source,source\nA,B",.csv))
        XCTAssertThrowsError(try parsed("source,target\nA,B,C",.csv))
    }
    func testPOContextFuzzyPluralAndAttribution() throws {
        let po = "# Copyright Original Team\nmsgid \"\"\nmsgstr \"Language: ar\\n\"\n\nmsgctxt \"scene\"\nmsgid \"Move \"\n\"now.\"\nmsgstr \"تحرك الآن.\"\n\n#, fuzzy\nmsgid \"Wait.\"\nmsgstr \"انتظر.\"\n\nmsgid \"Coin\"\nmsgid_plural \"Coins\"\nmsgstr[0] \"عملة\"\n"
        let value = try parsed(po,.po)
        XCTAssertEqual(value.records.count,1); XCTAssertEqual(value.records[0].source,"Move now.")
        XCTAssertTrue(value.metadata["attribution"]?.contains("Original Team") == true)
        XCTAssertEqual(value.rejected,2)
    }
    func testXMLPairsCDATAAndUTF16() throws {
        let xml = "<localization game_id=\"test\" license=\"Original license\"><entry id=\"1\"><source><![CDATA[Move now.]]></source><target>تحرك الآن.</target></entry></localization>"
        let value = try parsed(xml,.xml); XCTAssertEqual(value.records.count,1); XCTAssertEqual(value.metadata["license"],"Original license")
        var utf16 = Data([0xff,0xfe]); utf16.append(try XCTUnwrap(xml.data(using:.utf16LittleEndian)))
        XCTAssertEqual(LocalizationFormatDetector.detect(utf16),.xml)
        XCTAssertEqual(try LocalizationAdapters.parse(utf16,format:.xml,control:LocalizationImportControl()).records.count,1)
    }
    func testXMLRejectsEntitiesNestedMarkupAndDuplicateFields() {
        for text in [
            "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><x>&e;</x>",
            "<x><entry><source>Move <b>now</b>.</source><target>تحرك</target></entry></x>",
            "<x><entry><source>Move</source><source>Wait</source><target>تحرك</target></entry></x>",
            "<unclosed>"] {
            XCTAssertThrowsError(try parsed(text,.xml))
        }
    }
    func testMatcherRejectsAmbiguityDuplicatesAndPresentationForms() throws {
        let parsed = ParsedLocalization(records:[
            .init(id:"1",source:"Move.",target:"تحرك."),.init(id:"2",source:"Move.",target:"تحرك."),
            .init(id:"3",source:"Wait!",target:"انتظر."),.init(id:"4",source:"Wait!",target:"توقف."),
            .init(id:"5",source:"Hello.",target:"ﺍﻟﻌﺮﺑﻴﺔ"),.init(id:"6",source:"Only English",target:"No Arabic")])
        let value = try EnglishArabicMatcher.match(parsed,control:LocalizationImportControl())
        XCTAssertEqual(value.records.count,1); XCTAssertEqual(value.rejected,5)
        var conflict = parsed; conflict.records.append(.init(id:"1",source:"Other.",target:"آخر."))
        XCTAssertThrowsError(try EnglishArabicMatcher.match(conflict,control:LocalizationImportControl()))
    }
    func testCancellationAndDeadlineAreCooperative() {
        let control = LocalizationImportControl(); control.cancel()
        XCTAssertThrowsError(try control.check())
        XCTAssertThrowsError(try LocalizationAdapters.parse(Data("{}".utf8),format:.json,control:control))
        XCTAssertThrowsError(try LocalizationImportControl(seconds:-1).check())
    }
    func testBoundedPrefixMayEndInsideArabicScalar() {
        var data = Data("source,target\nHello,".utf8); data.append(Data("م".utf8).prefix(1))
        XCTAssertEqual(LocalizationFormatDetector.detect(data),.csv)
    }
}
