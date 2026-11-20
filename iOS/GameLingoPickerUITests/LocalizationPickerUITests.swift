import XCTest
import Vision
import CoreGraphics

final class LocalizationPickerUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier:"dev.gamelingo.ios")
    // prepare-simulator.py provisions an iPhone 16 (393pt width). The document
    // provider renders in another process, absent from the AUT's AX hierarchy.
    // Recognize the actual visible label and tap screen coordinates, then require
    // the delegate-delivered filename in the AUT. No picker acceptance is mocked.
    // Independent simctl PNG: iPhone16 English provider More=(364,97)pt.
    // The earlier OCR-derived header ordinate injected y40 into the status bar.
    private let headerY: CGFloat = 97.0/852
    private var screenshotPixels = CGSize.zero
    private var listPresentation = false
    private func diagnosticScreen(_ name: String) {
        // A CI-side simctl watcher captures the actual provider independently
        // of XCTest's screenshot attachment XPC, which failed on this runtime.
        print("PICKER_DIAGNOSTIC "+name)
        Thread.sleep(forTimeInterval:3)
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Only the system provider menu uses English, which Vision supports on
        // the pinned runtime. GameLingo's Arabic UI and RTL rendering stay tested
        // by the native presentation fixtures, separately from file selection.
        app.launchArguments = ["-AppleLanguages","(en)","-AppleLocale","en_US"]
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
    private func waitFinished(filename: String) throws {
        var dismissed = false, clearFrames = 0
        for _ in 0..<60 {
            let labels = try visiblePickerText()
            let header = labels.contains { $0.0.contains("gamelingo") && $0.1.midY > 0.82 }
            if !header { clearFrames += 1 } else { clearFrames = 0 }
            if clearFrames >= 2 { dismissed = true; break }
            Thread.sleep(forTimeInterval:0.25)
        }
        XCTAssertTrue(dismissed,"Native provider did not dismiss after thumbnail tap")
        guard dismissed else { return }
        let summary = app.staticTexts["gamePacks.fileSummary"]
        let finished = NSPredicate { [self] _,_ in
            summary.exists && summary.label.contains(filename) && app.buttons["gamePacks.import"].isEnabled && app.buttons["gamePacks.import"].isHittable
        }
        expectation(for:finished,evaluatedWith:app); waitForExpectations(timeout:40)
        XCTAssertFalse(app.staticTexts["gamePacks.importStatus"].label.isEmpty)
    }
    private func screenCoordinate(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset:CGVector(dx:point.x,dy:point.y))
    }
    private func visiblePickerText() throws -> [(String,CGRect)] {
        // Match the image coordinate space to the XCUIApplication target. The
        // screen-wide screenshot RPC also repeatedly crashed on this runtime.
        let shot = app.screenshot(), image = try XCTUnwrap(shot.image.cgImage)
        screenshotPixels = CGSize(width:image.width,height:image.height)
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
                print("PICKER_NATIVE_HEADER_VISIBLE frame=\(app.frame) pixels=\(screenshotPixels) titleBox=\(title.1)")
                return
            }
            Thread.sleep(forTimeInterval:0.25)
        }
        XCTFail("Native provider did not render its folder header")
    }
    private func pickerFilePoints(_ ext: String) throws -> (thumbnail: CGPoint, caption: CGPoint) {
        try waitForNativePicker()
        if !listPresentation {
            // Files owns its presentation and hit regions. Use its actual List
            // command instead of guessing the hit area of a Quick Look thumbnail.
            // Use the button position in the independently captured actual
            // provider, not the erroneous y40 OCR-derived title coordinate.
            diagnosticScreen("before-view-menu")
            screenCoordinate(CGPoint(x:364.0/393,y:headerY)).tap()
            diagnosticScreen("after-view-menu")
            var listPoint: CGPoint?
            for _ in 0..<10 {
                let labels = try visiblePickerText()
                print("PICKER_VIEW_MENU "+labels.map{$0.0}.joined(separator:" | "))
                if let row = labels.first(where:{["list","قائمة"].contains($0.0)}) {
                    listPoint = CGPoint(x:row.1.midX,y:1-row.1.midY); break
                }
                Thread.sleep(forTimeInterval:0.25)
            }
            // Preserve the host PNG even if XCTest cannot encode an attachment.
            diagnosticScreen("view-menu-result")
            screenCoordinate(try XCTUnwrap(listPoint,"Files List command not visible")).tap()
            listPresentation = true
            try waitForNativePicker()
        }
        // Tap the status-bar clock to return the provider's scroll view to top.
        screenCoordinate(CGPoint(x:0.15,y:0.025)).tap()
        Thread.sleep(forTimeInterval:1.0)
        let aliases: [String]
        switch ext {
        case "": aliases = ["extension"]
        case "po": aliases = ["popo","glpickerpo"]
        case "7z": aliases = ["7z7z","7272","glpicker7z","glpicker72"]
        case "glpack": aliases = ["glpackglpack","gipackgipack","glpickerglpack","glpickergipack"]
        case "unknownformat": aliases = ["unknownformat","unknownforrnat","unknoformat"]
        default: aliases = [ext+ext,"glpicker"+ext]
        }
        func target(_ rows: [(String,CGRect)]) -> CGRect? {
            rows.first(where:{ row in row.1.midY < 0.80 && row.1.midY > 0.11 && aliases.contains(where:{row.0.contains($0)}) })?.1
        }
        for _ in 0..<20 {
            let text = try visiblePickerText()
            print("PICKER_VISIBLE_LABELS "+text.map{$0.0}.joined(separator:" | "))
            if let first = target(text) {
                // AUT idle does not include the remote provider's deceleration.
                // Confirm a stable label in a second screen frame before tapping.
                Thread.sleep(forTimeInterval:0.35)
                guard let box = target(try visiblePickerText()), abs(first.midY-box.midY) < 0.006, abs(first.midX-box.midX) < 0.01 else { continue }
                // In List presentation the visible filename is inside its row.
                // No assumptions about preview size or thumbnail offsets.
                let point = CGPoint(x:box.midX,y:1-box.midY)
                if point.y < 0.21 {
                    screenCoordinate(CGPoint(x:0.5,y:0.35)).press(forDuration:0.05,thenDragTo:screenCoordinate(CGPoint(x:0.5,y:0.52)))
                    Thread.sleep(forTimeInterval:1.0)
                    continue
                }
                print("PICKER_THUMBNAIL_TAP \(ext) \(point)")
                return (point,CGPoint(x:box.midX,y:1-box.midY))
            }
            screenCoordinate(CGPoint(x:0.5,y:0.74)).press(forDuration:0.05,thenDragTo:screenCoordinate(CGPoint(x:0.5,y:0.40)))
            Thread.sleep(forTimeInterval:1.0)
        }
        XCTFail("Visible picker label not found: "+ext)
        return (CGPoint(x:0.5,y:0.5),CGPoint(x:0.5,y:0.5))
    }
    func testNativePickerSelectsAllFixtureExtensionsAndCanCancel() throws {
        for ext in ["exe","zip","glpack","rar","7z","xml","json","csv","txt","po","unknownformat",""] {
            importButton().tap()
            let name = ext.isEmpty ? "GLPicker-no-extension" : "GLPicker-"+ext
            let points = try pickerFilePoints(ext)
            diagnosticScreen("before-file-"+name)
            screenCoordinate(points.thumbnail).tap()
            Thread.sleep(forTimeInterval:1.0)
            // The recorded XML preview stayed in Files after a correctly placed
            // thumbnail tap. Files also exposes the filename as a selection hit
            // target. Try that visible caption once, only while the provider is
            // still on screen. Acceptance still requires the delegate-delivered
            // exact filename below; no extension, import or cancel check is skipped.
            if try visiblePickerText().contains(where:{ $0.0.contains("gamelingo") && $0.1.midY > 0.82 }) {
                print("PICKER_CAPTION_TAP \(ext) \(points.caption)")
                diagnosticScreen("before-caption-"+name)
                screenCoordinate(points.caption).tap()
            }
            try waitFinished(filename:ext.isEmpty ? name : name+"."+ext)
            print("PICKER_SELECTION_VERIFIED "+(ext.isEmpty ? "extensionless" : ext))
        }
        let previous = app.staticTexts["gamePacks.fileSummary"].label
        importButton().tap()
        try waitForNativePicker()
        let cancelLabels = try visiblePickerText()
        XCTAssertTrue(cancelLabels.contains(where:{$0.0 == "cancel" && $0.1.midY > 0.82}),"Native Cancel command not visible")
        screenCoordinate(CGPoint(x:304.0/393,y:headerY)).tap()
        expectation(for:NSPredicate { [self] _,_ in app.buttons["gamePacks.import"].isHittable },evaluatedWith:app)
        waitForExpectations(timeout:15)
        XCTAssertEqual(app.staticTexts["gamePacks.fileSummary"].label,previous)
        XCTAssertTrue(app.staticTexts["gamePacks.importStatus"].label.hasPrefix("أُلغي اختيار"))
    }
    func testSandboxFolderImportsWithoutSystemPicker() throws {
        let file = app.buttons["gamePacks.inbox.GLPicker-json.json"]
        reveal(file); XCTAssertTrue(file.isHittable); file.tap()
        // Return to the status above the library after choosing the sandbox file.
        _ = importButton()
        try waitFinished(filename:"GLPicker-json.json")
        XCTAssertTrue(app.staticTexts["gamePacks.importStatus"].label.hasPrefix("تم استيراد"))
    }
}
