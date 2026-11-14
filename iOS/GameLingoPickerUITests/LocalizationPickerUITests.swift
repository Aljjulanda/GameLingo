import XCTest
import Vision
import CoreGraphics

final class LocalizationPickerUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier:"dev.gamelingo.ios")
    // prepare-simulator.py provisions an iPhone 16 (393pt width). The document
    // provider renders in another process, absent from the AUT's AX hierarchy.
    // Recognize the actual visible label and tap screen coordinates, then require
    // the delegate-delivered filename in the AUT. No picker acceptance is mocked.
    private var screenHeight: CGFloat = 852
    private var headerY: CGFloat = 0.115
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages","(ar)","-AppleLocale","ar_OM"]
        app.launch()
        app.tabBars.buttons["الترجمة"].tap()
        let library = app.buttons["gamePacks.library"]
        XCTAssertTrue(library.waitForExistence(timeout:15)); library.tap()
        XCTAssertTrue(app.buttons["gamePacks.import"].waitForExistence(timeout:15))
    }
    override func tearDownWithError() throws {
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string:app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        app.terminate()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<20 { if element.isHittable { return }; app.swipeUp() }
    }
    private func importButton() -> XCUIElement {
        let button = app.buttons["gamePacks.import"]
        for _ in 0..<20 { if button.isHittable { break }; app.swipeDown() }
        return button
    }
    private func waitFinished(filename: String) {
        let summary = app.staticTexts["gamePacks.fileSummary"]
        let finished = NSPredicate { [self] _,_ in
            summary.exists && summary.label.contains(filename) && app.buttons["gamePacks.import"].isEnabled && app.buttons["gamePacks.import"].isHittable
        }
        expectation(for:finished,evaluatedWith:app); waitForExpectations(timeout:40)
        XCTAssertFalse(app.staticTexts["gamePacks.importStatus"].label.isEmpty)
    }
    private func screenCoordinate(_ point: CGPoint) -> XCUICoordinate {
        let origin = app.frame.origin
        return app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:point.x*393-origin.x,dy:point.y*screenHeight-origin.y))
    }
    private func visiblePickerText() throws -> [(String,CGRect)] {
        let shot = XCUIScreen.main.screenshot(), image = try XCTUnwrap(shot.image.cgImage)
        screenHeight = CGFloat(image.height)/CGFloat(image.width)*393
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]; request.usesLanguageCorrection = false
        request.customWords = ["GameLingo","GLPicker","glpack","unknownformat","no-extension"]
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text.lowercased().filter{$0.isLetter || $0.isNumber},observation.boundingBox)
        }
    }
    private func waitForNativePicker() throws {
        for _ in 0..<30 {
            let text = try visiblePickerText()
            if let title = text.first(where:{ $0.0.contains("gamelingo") && $0.1.midY > 0.82 }) {
                headerY = 1-title.1.midY
                print("PICKER_NATIVE_HEADER_VISIBLE frame=\(app.frame)")
                return
            }
            Thread.sleep(forTimeInterval:0.25)
        }
        XCTFail("Native provider did not render its folder header")
    }
    private func pickerFilePoint(_ ext: String) throws -> CGPoint {
        try waitForNativePicker()
        // Tap the status-bar clock to return the provider's scroll view to top.
        screenCoordinate(CGPoint(x:0.15,y:0.025)).tap()
        Thread.sleep(forTimeInterval:0.3)
        let aliases: [String]
        switch ext {
        case "": aliases = ["extension"]
        case "po": aliases = ["popo","glpickerpo"]
        case "7z": aliases = ["7z","72"]
        case "glpack": aliases = ["glpack","gipack"]
        case "unknownformat": aliases = ["unknownformat","unknownforrnat"]
        default: aliases = [ext]
        }
        for _ in 0..<12 {
            let text = try visiblePickerText()
            print("PICKER_VISIBLE_LABELS "+text.map{$0.0}.joined(separator:" | "))
            if let item = text.first(where:{ row in row.1.midY < 0.80 && row.1.midY > 0.11 && aliases.contains(where:{row.0.contains($0)}) }) {
                return CGPoint(x:item.1.midX,y:1-item.1.midY)
            }
            screenCoordinate(CGPoint(x:0.5,y:0.74)).press(forDuration:0.05,thenDragTo:screenCoordinate(CGPoint(x:0.5,y:0.40)))
        }
        XCTFail("Visible picker label not found: "+ext)
        return CGPoint(x:0.5,y:0.5)
    }
    func testNativePickerSelectsAllFixtureExtensionsAndCanCancel() throws {
        for ext in ["exe","zip","glpack","rar","7z","xml","json","csv","txt","po","unknownformat",""] {
            importButton().tap()
            let name = ext.isEmpty ? "GLPicker-no-extension" : "GLPicker-"+ext
            let point = try pickerFilePoint(ext)
            let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "Picker-"+name; screenshot.lifetime = .keepAlways; add(screenshot)
            screenCoordinate(point).tap()
            waitFinished(filename:ext.isEmpty ? name : name+"."+ext)
            print("PICKER_SELECTION_VERIFIED "+(ext.isEmpty ? "extensionless" : ext))
        }
        let previous = app.staticTexts["gamePacks.fileSummary"].label
        importButton().tap()
        try waitForNativePicker()
        screenCoordinate(CGPoint(x:0.20,y:headerY)).tap()
        expectation(for:NSPredicate { [self] _,_ in app.buttons["gamePacks.import"].isHittable },evaluatedWith:app)
        waitForExpectations(timeout:15)
        XCTAssertEqual(app.staticTexts["gamePacks.fileSummary"].label,previous)
        XCTAssertTrue(app.staticTexts["gamePacks.importStatus"].label.hasPrefix("أُلغي اختيار"))
    }
    func testSandboxFolderImportsWithoutSystemPicker() {
        let file = app.buttons["gamePacks.inbox.GLPicker-json.json"]
        reveal(file); XCTAssertTrue(file.isHittable); file.tap()
        // Return to the status above the library after choosing the sandbox file.
        _ = importButton()
        waitFinished(filename:"GLPicker-json.json")
        XCTAssertTrue(app.staticTexts["gamePacks.importStatus"].label.hasPrefix("تم استيراد"))
    }
}
