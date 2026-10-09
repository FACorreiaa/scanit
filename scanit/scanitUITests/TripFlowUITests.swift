import XCTest

/// BACKLOG IOS-003: a trip starts with and without a limit, and the last store is preselected.
final class TripFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testStartWithLimitThenWithoutAndStoreIsRemembered() throws {
        // First trip: new store, €60 limit.
        app.buttons["openStartTrip"].tap()
        let storeName = app.textFields["storeName"]
        XCTAssertTrue(storeName.waitForExistence(timeout: 5), "first use goes straight to a store name")
        storeName.typeText("Lidl")
        app.textFields["limit"].tap()
        app.textFields["limit"].typeText("60")
        snapshot("1-start-sheet-first-use")
        app.buttons["startTrip"].tap()

        XCTAssertTrue(app.staticTexts["Lidl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'left'")).firstMatch.exists,
                      "a limited trip shows how much is left")
        snapshot("2-active-trip-with-limit")

        // Cancel it.
        app.buttons["More"].tap()
        app.buttons["Cancel trip"].firstMatch.tap()
        app.sheets.buttons["Cancel trip"].firstMatch.tap()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5))

        // Second trip: Lidl is preselected, no limit.
        app.buttons["openStartTrip"].tap()
        XCTAssertTrue(app.buttons["Lidl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Lidl"].isSelected, "the last store is preselected")
        XCTAssertFalse(app.textFields["storeName"].exists)
        XCTAssertTrue(app.buttons["Last €60.00"].exists || app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Last'")).firstMatch.exists,
                      "the last limit is offered as a chip")
        snapshot("3-start-sheet-returning")
        app.buttons["startTrip"].tap()

        XCTAssertTrue(app.staticTexts["Lidl"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'left'")).firstMatch.exists,
                       "a trip without a limit shows no limit bar")
        snapshot("4-active-trip-no-limit")
    }

    /// Kept in the result bundle for visual review (`xcresulttool export attachments`).
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
