import Foundation

struct BenchmarkReading {
    var content: DialogueContent, box: SourceBox, confidence: Double
}

@main struct QualityPipelineBenchmark {
    static func main() throws {
        let enabled = CommandLine.arguments.contains("enabled")
        #if QUALITY_CURRENT
        var quality = QualitySettings()
        if enabled {
            for flag in [QualityFlag.stageCues,.speakerClassification,.speakerGeometry,.lineLimits,.punctuationRepair,.punctuationTrace,.arabicParagraphDirection] { quality[flag] = true }
        }
        #endif
        func rows(_ texts: [String]) -> [OCRLine] {
            texts.enumerated().map { i,text in OCRLine(text:text,box:SourceBox(x:0.25,y:0.72+Double(i)*0.034,w:0.5,h:0.025),confidence:0.95) }
        }
        let fixtures: [[[OCRLine]]] = [
            [rows(["Arthur: We need to leave now."]),rows(["Arthur: We need to leave now."]),rows(["Arthur: We need to leave now and find John."]),rows(["John: Where are you going?"]),[],[],[],rows(["Arthur: We need to leave now."])],
            [rows(["[Arthur] Wait here."]),rows(["[Arthur] Wait here."]),rows(["[the wind settles] We should go."])],
            [rows(["[laughs] We should leave."]),rows(["[laughs] We should leave."]),rows(["(sighs)"])],
            [rows(["Settings","Options"]),rows(["Settings","Options"]),rows(["HP 100","Ammo 12","Press A"])],
            [rows(["We need to leave now.","Right now.","Go!","Wait!"]),rows(["We need to leave now.","Right now.","Go!","Wait!"])],
            [rows(["Arthur: We need to leave now.","The guards are on their way.","I can hear them outside.","Take the money and follow me.","We will meet at the bridge."])],
            [rows(["We need to leave this place.","Right now.","Come on.","Stay close.","This way.","Let's go."]),rows(["We need to leave this place.","Right now.","Come on.","Stay close.","This way.","Let's go."])],
            [rows(["Go!"]),rows(["No!"]),rows(["Wait?"]),rows(["Run."])],
            [rows(["Mr. Morgan, wait.","Where are you going?"]),rows(["Mr. Morgan, wait.","Where are you going?"])],
            [[OCRLine(text:"Arthur",box:SourceBox(x:0.26,y:0.70,w:0.10,h:0.038)),OCRLine(text:"We need to leave now.",box:SourceBox(x:0.38,y:0.78,w:0.4,h:0.03))]]
        ]
        var canonical: [[String]] = [], durations: [Double] = [], traces = 0
        var perFixture = Array(repeating:[Double](),count:fixtures.count)
        for repeatIndex in 0..<101 {
            var streams: [[String]] = []
            for (fixtureIndex,stream) in fixtures.enumerated() {
                #if QUALITY_CURRENT
                var selector = DialogueSelection()
                #else
                var selector = LegacySelection()
                #endif
                var tracker = DialogueTracker(), stability = PublicationStability()
                var identities: [String:Int] = [:], messages: [String] = []
                func identity(_ value: String) -> Int {
                    if let id = identities[value] { return id }
                    let id = identities.count; identities[value] = id; return id
                }
                for (index,lines) in stream.enumerated() {
                    let start = ProcessInfo.processInfo.systemUptime
                    #if QUALITY_CURRENT
                    let actual = DialogueObservation.resolve(lines,roi:.dialogue,knownNames:"Arthur,John",selector:&selector,quality:quality)
                    let reading = BenchmarkReading(content:actual.content,box:actual.box,confidence:actual.confidence)
                    #else
                    let reading = legacyResolve(lines,selector:&selector)
                    #endif
                    let now = Double(index)*0.5
                    switch tracker.observe(text:reading.content.text,box:reading.box,now:now,frameMilliseconds:Int64(now*1000),speaker:reading.content.speaker,confidence:reading.confidence) {
                    case .unchanged: break
                    case .gone(let id): messages.append("gone:\(identity(id))")
                    case .dialogue(var job,let previous):
                        if let previous { messages.append("previous:\(identity(previous))") }
                        if stability.shouldPublish(job) {
                            // Explicit synchronous stub isolates post-OCR work.
                            // Neither a model nor the asynchronous worker runs.
                            var output = "نص اختبار."
                            #if QUALITY_CURRENT
                            job.cue = reading.content.cue
                            let input = reading.content.engineText ?? job.text
                            output = input.isEmpty && job.cue != nil ? job.cue! : SourceGuidedPunctuation.repair(output,source:input,enabled:quality[.punctuationRepair]).text
                            #endif
                            var wire = TVProtocol.subtitle(job,arabic:output,now:Int64(now*1000)+1)
                            #if QUALITY_CURRENT
                            wire = TVProtocol.qualityFields(wire,settings:quality,origin:.argosInference)
                            if quality[.punctuationTrace] { traces += SubtitlePresentation.punctuation(reading.content.text).count+SubtitlePresentation.punctuation(output).count }
                            #endif
                            wire["id"] = identity(job.id)
                            messages.append(String(decoding:try TVProtocol.encode(wire),as:UTF8.self))
                            stability.didPublish(job)
                        }
                    }
                    if repeatIndex > 0 {
                        let duration = (ProcessInfo.processInfo.systemUptime-start)*1000
                        durations.append(duration); perFixture[fixtureIndex].append(duration)
                    }
                }
                streams.append(messages)
            }
            if repeatIndex == 0 { canonical = streams }
            else { precondition(streams == canonical,"Non-deterministic fixture output") }
        }
        durations.sort()
        let fixtureTimings: [[String:Any]] = perFixture.enumerated().map { index,values in
            let sorted = values.sorted()
            return ["fixture":index,"observations":sorted.count,"median_ms":sorted[sorted.count/2],"p95_ms":sorted[Int(Double(sorted.count-1)*0.95)]]
        }
        let result: [String:Any] = ["enabled":enabled,"fixture_streams":canonical,"observations":durations.count,"median_ms":durations[durations.count/2],"p95_ms":durations[Int(Double(durations.count-1)*0.95)],"fixture_timings":fixtureTimings,"trace_work":traces]
        print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
    }
}
