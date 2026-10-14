import XCTest

/// Raw App Store screenshots (6.9", 1320×2868 on iPhone 17 Pro Max). Opt-in, never part of a normal
/// run: `TEST_RUNNER_SCANIT_SCREENSHOTS=1`. Framed with captions afterwards by brand/tools/store-frames.html.
@MainActor
final class AppStoreScreenshots: XCTestCase {
    private let app = XCUIApplication()

    override nonisolated func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SCANIT_SCREENSHOTS"] == "1", "screenshots are opt-in")
    }

    func testCaptureStoreScreens() throws {
        // 1. A trip in progress, close to the limit.
        app.launchArguments = ["-ui-testing", "-ui-testing-demo-data", "-ui-testing-demo-trip"]
        app.launch()
        XCTAssertTrue(app.buttons["scan"].waitForExistence(timeout: 10))
        sleep(1)
        shot("store-1-trip")

        // 2. Insights.
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["This month"].waitForExistence(timeout: 5))
        sleep(1)
        shot("store-2-insights")

        // 2b. Insights lists: prices that went up, cheapest store for regulars.
        // Scroll until the "Prices that went up" header sits just under the navigation bar.
        let header = app.staticTexts["Prices that went up"]
        for _ in 0..<6 where !(header.exists && header.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        sleep(1)
        shot("store-5-prices")

        // 3. History.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["monthTotal"].waitForExistence(timeout: 5))
        sleep(1)
        shot("store-3-history")

        // 6. A remembered price: scan milk at Lidl, where the demo history saw it before.
        app.terminate()
        app.launchArguments = ["-ui-testing", "-ui-testing-demo-data", "-ui-testing-demo-trip"]
        app.launchEnvironment["UITEST_AUTOSCAN"] = "5601234567892"
        app.launch()
        XCTAssertTrue(app.buttons["scan"].waitForExistence(timeout: 10))
        app.buttons["scan"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Seen here'")).firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        shot("store-6-remembered")
        app.launchEnvironment["UITEST_AUTOSCAN"] = nil

        // 4. Ready to shop: the mascot, no trip in progress.
        app.terminate()
        app.launchArguments = ["-ui-testing", "-ui-testing-demo-data"]
        app.launch()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 10))
        sleep(1)
        shot("store-4-ready")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
