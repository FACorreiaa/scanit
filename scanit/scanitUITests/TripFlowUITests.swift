import XCTest

/// End-to-end trip flows on the simulator. The camera is replaced by `SimulatedScanner`
/// (`-ui-testing` + `UITEST_SCAN_CODES`), everything else is the real app on a throwaway store.
@MainActor
final class TripFlowUITests: XCTestCase {
    private var app = XCUIApplication()
    private let milk = "5601234567892"
    private let bread = "4006381333931"

    override nonisolated func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Each test launches explicitly: XCTest's setUp is nonisolated, and an async `@MainActor`
    /// setUp crashes on some Xcode 26 runtimes (see LuminaVaultClient's ci.yml).
    private func launch(extraArguments: [String] = []) {
        app.launchArguments = ["-ui-testing"] + extraArguments
        app.launchEnvironment["UITEST_SCAN_CODES"] = "\(milk),\(bread)"
        app.launch()
    }

    /// IOS-003: a trip starts with and without a limit, and the last store is preselected.
    func testStartWithLimitThenWithoutAndStoreIsRemembered() throws {
        launch()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5))
        snapshot("0-empty-trip")
        startTrip(newStore: "Lidl", limit: "60")
        XCTAssertTrue(app.staticTexts["Lidl"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "left").exists, "a limited trip shows how much is left")
        snapshot("1-active-trip-with-limit")

        app.buttons["More"].tap()
        app.buttons["Cancel trip"].firstMatch.tap()
        app.sheets.buttons["Cancel trip"].firstMatch.tap()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5))

        app.buttons["openStartTrip"].tap()
        XCTAssertTrue(app.buttons["Lidl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Lidl"].isSelected, "the last store is preselected")
        XCTAssertFalse(app.textFields["storeName"].exists)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Last'")).firstMatch.exists,
                      "the last limit is offered as a chip")
        snapshot("2-start-sheet-returning")
        app.buttons["startTrip"].tap()

        XCTAssertTrue(app.staticTexts["Lidl"].waitForExistence(timeout: 5))
        XCTAssertFalse(text(containing: "left").exists, "a trip without a limit shows no limit bar")
    }

    /// IOS-004/005/008/009/010/011: scan, confirm, over the limit, delete, finish, history,
    /// and the price remembered on the next trip.
    func testScanFinishAndRememberedPrice() throws {
        launch()
        startTrip(newStore: "Lidl", limit: "5")
        app.buttons["scan"].tap()

        // Milk: type the price, two of them.
        scan(milk)
        let price = app.textFields["price"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.typeText("1,99")
        app.steppers["quantity"].buttons.element(boundBy: 1).tap()
        snapshot("3-confirm-sheet")
        app.buttons["addItem"].tap()
        XCTAssertTrue(text(containing: "3,98").waitForExistence(timeout: 5), "HUD total updates after add")

        // Bread pushes the trip over the €5 limit.
        scan(bread)
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.typeText("1,50")
        app.buttons["addItem"].tap()
        XCTAssertTrue(text(containing: "over").waitForExistence(timeout: 5), "over the limit is shown")
        snapshot("4-scanner-over-limit")
        app.buttons["closeScanner"].tap()

        // Open Food Facts (stubbed in UI tests) named the milk after it was added.
        XCTAssertTrue(app.staticTexts["Leite meio gordo"].waitForExistence(timeout: 5), "product name filled in")

        // Cart: delete the bread, back under the limit.
        let breadRow = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", bread)).firstMatch
        XCTAssertTrue(breadRow.waitForExistence(timeout: 5))
        snapshot("5-active-trip-cart")
        breadRow.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(text(containing: "left").waitForExistence(timeout: 5))

        // Finish with a till total.
        app.buttons["finishTrip"].tap()
        XCTAssertTrue(app.navigationBars["Trip finished"].waitForExistence(timeout: 5))
        app.textFields["tillTotal"].tap()
        app.textFields["tillTotal"].typeText("4")
        snapshot("6-summary")
        app.buttons["doneSummary"].tap()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5))

        // History shows the trip and the month total.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["monthTotal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["monthTotal"].label.contains("3,98"))
        snapshot("7-history")

        // Next trip at Lidl: the milk price is remembered, so it is two taps.
        app.tabBars.buttons["Trip"].tap()
        app.buttons["openStartTrip"].tap()
        XCTAssertTrue(app.buttons["Lidl"].waitForExistence(timeout: 5))
        app.buttons["startTrip"].tap()
        app.buttons["scan"].tap()
        scan(milk)
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        XCTAssertEqual(price.value as? String, "1,99", "remembered price is prefilled")
        XCTAssertTrue(text(containing: "Seen here").exists)
        app.buttons["addItem"].tap()
        XCTAssertTrue(text(containing: "1,99").waitForExistence(timeout: 5))
    }

    /// IOS-004: the largest accessibility text size does not clip the total.
    func testLargestTextSizeKeepsTotalReadable() throws {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"])

        startTrip(newStore: "Lidl", limit: "100")
        app.buttons["scan"].tap()
        scan(milk)
        app.textFields["price"].typeText("1234,56")
        app.buttons["addItem"].tap()
        app.buttons["closeScanner"].tap()

        let total = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '234,56' AND NOT (label CONTAINS 'over')")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(total.frame.maxX, app.frame.maxX, "total fits the screen width")
        XCTAssertGreaterThanOrEqual(total.frame.minX, app.frame.minX)
        snapshot("8-accessibility-xxl")
    }

    /// INS-103: with history, the Insights tab shows tiles, bars and lists.
    func testInsightsWithHistory() throws {
        launch(extraArguments: ["-ui-testing-demo-data"])
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["This month"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Average trip"].exists)
        XCTAssertTrue(app.staticTexts["5 of 5"].exists, "all demo trips stayed under their limit")
        snapshot("9-insights-top")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Prices that went up"].waitForExistence(timeout: 5)
                      || app.staticTexts["PRICES THAT WENT UP"].exists)
        snapshot("10-insights-lists")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Your regular basket"].waitForExistence(timeout: 5), "INS-10 shown")
        snapshot("11-insights-your-prices")
    }

    func testInsightsPlaceholderBeforeThreeTrips() throws {
        launch()
        app.tabBars.buttons["Insights"].tap()
        let progress = app.descendants(matching: .any)["insightsProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.value as? String, "0 of 3 trips done")
        snapshot("13-insights-progress")
        app.buttons["insightsStartShopping"].tap()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5), "the empty state leads to the Trip tab")
    }

    /// REL-003: past the free trips, Start shows the paywall; History locks older trips.
    func testPaywallAtStartAndLockedHistory() throws {
        launch(extraArguments: [
            "-ui-testing-demo-data", "-paywall-enabled", "-paywall-free-trips", "0", "-paywall-visible-history", "3",
        ])
        app.buttons["openStartTrip"].tap()
        XCTAssertTrue(app.buttons["unlock"].waitForExistence(timeout: 5), "paywall instead of the start sheet")
        XCTAssertTrue(text(containing: "this month").exists)
        snapshot("12-paywall")
        app.buttons["notNow"].tap()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5), "dismissable at no cost")
        snapshot("12b-empty-trip-last-trip")
        XCTAssertFalse(app.textFields["storeName"].exists)

        app.tabBars.buttons["History"].tap()
        let locked = app.buttons["lockedTrips"]
        XCTAssertTrue(locked.waitForExistence(timeout: 5))
        XCTAssertTrue(locked.label.contains("2 older trips"))
        locked.tap()
        XCTAssertTrue(app.buttons["unlock"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    private func startTrip(newStore: String, limit: String) {
        app.buttons["openStartTrip"].tap()
        let storeName = app.textFields["storeName"]
        XCTAssertTrue(storeName.waitForExistence(timeout: 5), "first use goes straight to a store name")
        storeName.typeText(newStore)
        app.textFields["limit"].tap()
        app.textFields["limit"].typeText(limit)
        app.buttons["startTrip"].tap()
    }

    private func scan(_ code: String) {
        let button = app.buttons["Simulate scan \(code)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// Kept in the result bundle for visual review (`xcresulttool export attachments`).
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
