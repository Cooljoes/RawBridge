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
        let refresh = app.buttons["refreshLibrary"]
        try XCTSkipUnless(refresh.waitForExistence(timeout: 5), "Grant access to the simulator fixture library.")
        refresh.tap()
        let picker = app.buttons["formatPicker"]
        let refreshFinished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: refresh)
        guard XCTWaiter.wait(for: [refreshFinished], timeout: 90) == .completed,
              picker.waitForExistence(timeout: 10) else {
            XCTFail("The manual refresh did not display the format filter.")
            return
        }
        picker.tap()
        app.buttons["RAW only"].tap()
        let solo = app.buttons["libraryTile-raw"].firstMatch
        try XCTSkipUnless(solo.waitForExistence(timeout: 5), "Install the optional standalone Nikon fixture.")
        XCTAssertFalse(app.buttons["libraryTile-jpegRAW"].firstMatch.exists)
        picker.tap()
        app.buttons["JPEG + RAW"].tap()
        let tile = app.buttons["libraryTile-jpegRAW"].firstMatch
        try XCTSkipUnless(tile.waitForExistence(timeout: 5), "Install the optional Nikon pair.")
        XCTAssertFalse(solo.exists)
        XCTAssertTrue(tile.label.localizedCaseInsensitiveContains(".NEF"), tile.label)
        XCTAssertFalse(tile.label.localizedCaseInsensitiveContains(".JPG"), tile.label)
        tile.tap()
        let rawPreview = app.buttons[".NEF"]
        XCTAssertTrue(rawPreview.waitForExistence(timeout: 8))
        rawPreview.tap()
        let rawFilename = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] %@", ".nef")).firstMatch
        XCTAssertTrue(rawFilename.waitForExistence(timeout: 8))
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
        let share = app.buttons["Share"]
        let pickerDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !closePicker.exists && share.isHittable
        }, object: nil)
        guard XCTWaiter.wait(for: [pickerDismissed], timeout: 20) == .completed else {
            XCTFail("The Files picker did not return control to the export sheet.")
            return
        }
        share.tap()
        // "Save to Files" also exists on the underlying export view.
        let activity = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR identifier == %@", "AirDrop", "ActivityListView")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 30))
    }
}
