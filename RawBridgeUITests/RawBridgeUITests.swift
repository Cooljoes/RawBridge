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

    func testCollapseAndExpandIndexedFormat() throws {
        let device = XCUIDevice.shared
        let originalOrientation = device.orientation
        if UIDevice.current.userInterfaceIdiom == .pad { device.orientation = .portrait }
        defer {
            if UIDevice.current.userInterfaceIdiom == .pad && originalOrientation.isValidInterfaceOrientation {
                device.orientation = originalOrientation
            }
        }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let refresh = app.buttons["refreshLibrary"]
        try XCTSkipUnless(refresh.waitForExistence(timeout: 8), "Requires existing Photos access.")
        refresh.tap()
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "libraryTile-"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 30))
        let name = String(tiles.firstMatch.identifier.dropFirst("libraryTile-".count))
        let group = app.buttons["formatSection-" + name].firstMatch
        let tile = app.buttons["libraryTile-" + name].firstMatch
        for x in [0.97, 0.5, 0.04] {
            group.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.94)).tap()
            XCTAssertTrue(tile.waitForNonExistence(timeout: 5))
            XCTAssertTrue(refresh.exists, "A header tap opened a photo")
            group.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.06)).tap()
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
        }
        XCTAssertGreaterThanOrEqual(group.frame.height, 44)
        app.buttons["Select"].tap()
        let export = app.buttons["Export"]
        XCTAssertFalse(export.isEnabled)
        group.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.94)).tap()
        XCTAssertFalse(export.isEnabled, "A header tap selected a photo")
        XCTAssertTrue(refresh.exists)
        group.tap()
        app.buttons["Done"].tap()
        tile.tap()
        XCTAssertTrue(app.navigationBars.buttons["Export"].waitForExistence(timeout: 10))
    }

    func testHeaderBelowExpandedPhotoGrid() throws {
        let app = XCUIApplication()
        app.launch()
        let refresh = app.buttons["refreshLibrary"]
        try XCTSkipUnless(refresh.waitForExistence(timeout: 8), "Requires existing Photos access.")
        refresh.tap()
        let headers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "formatSection-"))
        let second = headers.element(boundBy: 1)
        try XCTSkipUnless(second.waitForExistence(timeout: 15), "Requires two photo formats.")
        let nextName = String(second.identifier.dropFirst("formatSection-".count))
        let tiles = app.buttons["libraryTile-" + nextName].firstMatch
        let scroll = app.scrollViews.firstMatch
        // Bring the boundary below the preceding expanded grid into view.
        for _ in 0..<25 {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 60)
            if viewport.contains(CGPoint(x: second.frame.midX, y: second.frame.midY)) { break }
            let below = second.frame.midY > viewport.maxY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.8 : 0.3))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.3 : 0.8))
            start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(second.isHittable)
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.06)).tap()
        XCTAssertTrue(refresh.exists, "The previous grid intercepted the next format header")
        XCTAssertTrue(tiles.waitForExistence(timeout: 5))
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.94)).tap()
        XCTAssertTrue(refresh.exists)
        XCTAssertTrue(tiles.waitForNonExistence(timeout: 5))
    }

    func testPullToRefreshSettlesWithExpandedAndCollapsedGroups() throws {
        let app = XCUIApplication()
        app.launch()
        let refresh = app.buttons["refreshLibrary"]
        try XCTSkipUnless(refresh.waitForExistence(timeout: 8), "Requires existing Photos access.")
        let header = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "formatSection-")).firstMatch
        if !header.waitForExistence(timeout: 3) {
            refresh.tap()
            XCTAssertTrue(header.waitForExistence(timeout: 30))
        }
        let scroll = app.scrollViews.firstMatch
        func pullAndCheckReturn() {
            let restingY = header.frame.minY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.27))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.84))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                refresh.isEnabled && abs(header.frame.minY - restingY) <= 4
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 8), .completed,
                           "The first format header stayed displaced after release")
        }
        pullAndCheckReturn()
        let name = String(header.identifier.dropFirst("formatSection-".count))
        let picker = app.buttons["formatPicker"]
        if picker.exists {
            picker.tap()
            app.buttons[name].tap()
        }
        header.tap()
        let tile = app.buttons["libraryTile-" + name].firstMatch
        XCTAssertTrue(tile.waitForNonExistence(timeout: 5))
        pullAndCheckReturn()
        pullAndCheckReturn()
        XCTAssertFalse(tile.exists, "Refreshing reopened a collapsed group")
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
        XCTAssertTrue(app.buttons["JPEG"].exists)
        app.buttons["NEF"].tap()
        let solo = app.buttons["libraryTile-NEF"].firstMatch
        try XCTSkipUnless(solo.waitForExistence(timeout: 5), "Install the optional standalone Nikon fixture.")
        XCTAssertFalse(app.buttons["libraryTile-JPEG + NEF"].firstMatch.exists)
        picker.tap()
        app.buttons["JPEG + NEF"].tap()
        let tile = app.buttons["libraryTile-JPEG + NEF"].firstMatch
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
