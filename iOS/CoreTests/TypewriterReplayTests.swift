import XCTest
@testable import LingoCore

final class TypewriterReplayTests: XCTestCase {
    private func data(_ sources: [(String,Double,CaptureStage)]) throws -> Data {
        var data = Data()
        for (index,item) in sources.enumerated() {
            let record = QualityCaptureRecord(eventID:"synthetic-\(index)",lines:[CaptureLine(text:item.0,box:SourceBox(x:0.25,y:0.78,w:0.5,h:0.035),confidence:0.95)],parsed:"",engineInput:"",engineOutput:"",origin:nil,stage:item.2,timestamp:item.1)
            data.append(try JSONEncoder().encode(record)); data.append(10)
        }
        return data
    }
    private var known: QualitySettings {
        var value = QualitySettings(); value[.typewriter] = true; value.rememberTypewriter(game:"synthetic-typewriter"); return value
    }
    func testPublicationRecordIsNotASecondOCRRead() throws {
        let input = try data([("Please wait here",0,.observation),("Please wait here",0.1,.published)])
        XCTAssertTrue(try QualityReplay.run(input,quality:known,game:"synthetic-typewriter",translate:{_ in "stub"}).isEmpty)
        let repeated = try data([("Please wait here",0,.observation),("Please wait here",0.5,.observation)])
        var inputs: [String] = []
        XCTAssertEqual(try QualityReplay.run(repeated,quality:known,game:"synthetic-typewriter",translate:{ inputs.append($0); return "stub" }),["stub"])
        XCTAssertEqual(inputs,["Please wait here"],"One early stub call, one published event")
    }
    func testInterruptedFastDialogueIsOrderedAndTerminalIsImmediate() throws {
        let input = try data([("Please wait here",0,.observation),("Run!",0.5,.observation),("Run!",1,.observation)])
        XCTAssertEqual(try QualityReplay.run(input,quality:known,game:"synthetic-typewriter",translate:{"stub:"+$0}),["stub:Please wait here","stub:Run!"])
    }
    func testUnknownGameOffAndZeroWaitKeepLegacyFixtureOutputs() throws {
        let input = try data([("Please wait here",0,.observation),("Run!",0.5,.observation)])
        let baseline = try QualityReplay.run(input,translate:{"stub:"+$0})
        XCTAssertEqual(try QualityReplay.run(input,quality:known,game:"different-game",translate:{"stub:"+$0}),baseline)
        var off = known; off[.typewriter] = false
        XCTAssertEqual(try QualityReplay.run(input,quality:off,game:"synthetic-typewriter",translate:{"stub:"+$0}),baseline)
        off[.typewriter] = true; off.settleSeconds = 0
        XCTAssertEqual(try QualityReplay.run(input,quality:off,game:"synthetic-typewriter",translate:{"stub:"+$0}),baseline)
    }
    func testContinuousGrowthReleasesLatestAtMaximumSettlingDeadline() throws {
        let input = try data((0...6).map{("We should"+String(repeating:" go",count:$0),Double($0)*0.5,.observation)})
        XCTAssertEqual(try QualityReplay.run(input,quality:known,game:"synthetic-typewriter",translate:{"stub:"+$0}),["stub:We should"+String(repeating:" go",count:6)])
    }
}
