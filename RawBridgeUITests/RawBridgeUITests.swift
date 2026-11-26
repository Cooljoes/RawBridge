import XCTest
import UIKit

final class RawBridgeUITests: XCTestCase {
    func testSettingsAndIntegrity() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["RawBridge"].waitForExistence(timeout: 8))
        app.buttons["Settings"].tap()
        app.buttons["Verify integrity"].tap()
        XCTAssertTrue(app.buttons["Choose camera card original"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose exported file"].exists)
    }

    func testChineseSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.switches["允许从 iCloud 下载原片"].waitForExistence(timeout: 5))
    }

    func testNikonPairDetailAndExportOptionsWhenFixtureIsInstalled() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let tile = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "iss030e122639")).firstMatch
        try XCTSkipUnless(tile.waitForExistence(timeout: 4), "Optional simulator Nikon pair is not installed.")
        tile.tap()
        let rawPreview = app.buttons["RAW"]
        XCTAssertTrue(rawPreview.waitForExistence(timeout: 8))
        rawPreview.tap()
        XCTAssertTrue(app.staticTexts["iss030e122639.NEF"].firstMatch.waitForExistence(timeout: 8))
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["Export"].tap()
        XCTAssertTrue(app.buttons["RAW + JPEG"].waitForExistence(timeout: 5))
        app.buttons["RAW + JPEG"].tap()
        app.buttons["Save to Files"].tap()
        let closePicker = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Cancel", "Close"])).firstMatch
        guard closePicker.waitForExistence(timeout: 60) else {
            XCTFail("Files did not finish presenting its document picker.")
            return
        }
        closePicker.tap()
        app.buttons["Prepare for sharing"].tap()
        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 15))
        share.tap()
        let activity = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR label == %@ OR identifier == %@", "Save to Files", "AirDrop", "ActivityListView")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 30))
    }
}
