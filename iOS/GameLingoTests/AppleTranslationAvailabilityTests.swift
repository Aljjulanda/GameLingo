import XCTest
import Translation
import Foundation
@testable import GameLingo

final class AppleTranslationAvailabilityTests: XCTestCase {
    @MainActor func testActualEnglishArabicAvailabilityWithoutDownloading() async throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("Translation availability API requires iOS 18; no engine option or download was added") }
        let completed = expectation(description:"Actual Apple English-Arabic availability response")
        let task = Task { @MainActor in
            let status = await LanguageAvailability().status(from:Locale.Language(identifier:"en"),to:Locale.Language(identifier:"ar"))
            guard !Task.isCancelled else { return }
            let value: String
            switch status {
            case .installed: value = "installed"
            case .supported: value = "supported-not-installed"
            case .unsupported: value = "unsupported"
            @unknown default: value = "unknown"
            }
            // No session or language download is requested; no dialogue is used.
            let report = ["runtime":ProcessInfo.processInfo.operatingSystemVersionString,"pair":"en-ar","status":value,"scope":"actual test runtime only; physical iPhone availability unverified"]
            do {
                let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                let attachment = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
                attachment.name = "Apple-Translation-availability"; attachment.lifetime = .keepAlways; self.add(attachment)
                print("APPLE_TRANSLATION_AVAILABILITY "+String(decoding:data,as:UTF8.self))
            } catch { XCTFail("Could not encode the public availability result") }
            XCTAssertNotEqual(value,"unknown","A new OS status needs explicit handling before any engine option")
            completed.fulfill()
        }
        defer { task.cancel() }
        await fulfillment(of:[completed],timeout:30)
        // A timeout is a failed probe, never proof of unsupported Arabic.
    }
}
