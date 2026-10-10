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

        // 3. History.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["monthTotal"].waitForExistence(timeout: 5))
        sleep(1)
        shot("store-3-history")

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
