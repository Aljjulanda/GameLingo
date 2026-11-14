import XCTest

final class LocalizationPickerUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier:"dev.gamelingo.ios")
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
    func testNativePickerSelectsAllFixtureExtensionsAndCanCancel() {
        for ext in ["exe","zip","glpack","rar","7z","xml","json","csv","txt","unknownformat"] {
            importButton().tap()
            let name = "GLPicker-"+ext
            let file = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@",name)).firstMatch
            XCTAssertTrue(file.waitForExistence(timeout:30),"Missing picker file: "+name)
            XCTAssertTrue(file.isEnabled,"Picker disabled arbitrary extension: "+ext)
            file.tap()
            waitFinished(filename:name+"."+ext)
        }
        let previous = app.staticTexts["gamePacks.fileSummary"].label
        importButton().tap()
        let cancel = app.buttons.matching(NSPredicate(format:"label IN %@",["Cancel","إلغاء"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:15)); cancel.tap()
        XCTAssertTrue(importButton().waitForExistence(timeout:15))
        XCTAssertEqual(app.staticTexts["gamePacks.fileSummary"].label,previous)
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
