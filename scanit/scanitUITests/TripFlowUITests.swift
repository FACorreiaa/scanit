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
        XCTAssertTrue(app.buttons["shareTrip"].exists, "a finished trip can be shared")
        app.buttons["doneSummary"].tap()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5))

        // History shows the trip and the month total.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["monthTotal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["monthTotal"].label.contains("3,98"))
        snapshot("7-history")

        // Next trip at Lidl: the milk price is remembered, so the scan alone adds it.
        app.tabBars.buttons["Trip"].tap()
        app.buttons["openStartTrip"].tap()
        XCTAssertTrue(app.buttons["Lidl"].waitForExistence(timeout: 5))
        app.buttons["startTrip"].tap()
        app.buttons["scan"].tap()
        scan(milk)
        let addedTitle = app.staticTexts["addedTitle"]
        XCTAssertTrue(addedTitle.waitForExistence(timeout: 5), "a remembered price is added without a tap")
        XCTAssertTrue(addedTitle.label.contains("1,99"))
        XCTAssertTrue(text(containing: "Seen here").exists)
        XCTAssertFalse(price.exists, "no confirm sheet")
        snapshot("added-remembered")

        // Undo takes it back.
        app.buttons["undoAdd"].tap()
        XCTAssertTrue(addedTitle.waitForNonExistence(timeout: 5))
        app.buttons["closeScanner"].tap()
        XCTAssertTrue(app.staticTexts["Cart is empty"].waitForExistence(timeout: 5))
    }

    /// IOS-007: one clear price on the shelf label is added without a tap.
    func testShelfPriceIsReadAndAddedWithoutATap() throws {
        app.launchEnvironment["UITEST_SHELF_TEXT"] = "1,99 €|9,95 €/kg"
        launch()
        startTrip(newStore: "Lidl", limit: "20")
        app.buttons["scan"].tap()
        scan(milk)

        let addedTitle = app.staticTexts["addedTitle"]
        XCTAssertTrue(addedTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(addedTitle.label.contains("1,99"))
        XCTAssertTrue(text(containing: "Read from the shelf label").exists)
        XCTAssertFalse(app.textFields["price"].exists, "no confirm sheet")
        snapshot("added-from-label")

        // A wrong read is fixed from the banner.
        app.buttons["editAdded"].tap()
        let editPrice = app.textFields["editPrice"]
        XCTAssertTrue(editPrice.waitForExistence(timeout: 5))
        XCTAssertEqual(editPrice.value as? String, "1,99")
        XCTAssertFalse(addedTitle.exists, "the banner makes way for the edit sheet")
    }

    /// IOS-007: a label with two item prices is not guessed; the sheet offers both.
    func testAmbiguousLabelStillAsks() throws {
        app.launchEnvironment["UITEST_SHELF_TEXT"] = "1,99 €|1,49 €"
        launch()
        startTrip(newStore: "Lidl", limit: "20")
        app.buttons["scan"].tap()
        scan(milk)

        XCTAssertTrue(app.buttons["labelChip"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["addedTitle"].exists)
        snapshot("price-read-sheet")
    }

    func testTypingStaysAvailableWhenNoPriceIsRead() throws {
        app.launchEnvironment["UITEST_SHELF_TEXT"] = "Leite meio gordo"
        launch()
        startTrip(newStore: "Lidl", limit: "20")
        app.buttons["scan"].tap()
        scan(milk)

        XCTAssertTrue(app.staticTexts["Couldn't read a price"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["readPrice"].exists, "reading can be tried again")

        app.buttons["typePrice"].tap()
        XCTAssertTrue(app.textFields["price"].waitForExistence(timeout: 5))
    }

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

        // ADD-003: a monthly budget shows this month's spending against it.
        let budget = app.buttons["monthlyBudget"]
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        budget.tap()
        let amount = app.textFields["budgetAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("5000")
        app.buttons["saveBudget"].tap()
        XCTAssertTrue(text(containing: "of ").waitForExistence(timeout: 5) || budget.label.contains("of "),
                      "the budget row shows spent of budget")
        snapshot("9b-insights-budget")
        // ADD-006: trips can be exported from About.
        app.buttons["insightsAbout"].tap()
        XCTAssertTrue(app.buttons["exportTrips"].waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Prices that went up"].waitForExistence(timeout: 5)
                      || app.staticTexts["PRICES THAT WENT UP"].exists)
        snapshot("10-insights-lists")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Your regular basket"].waitForExistence(timeout: 5), "INS-10 shown")
        snapshot("11-insights-your-prices")
    }

    /// BUD-001: a € budget and a $ budget each show against their own month's spending.
    func testBudgetsInTwoCurrencies() throws {
        launch(extraArguments: ["-ui-testing-demo-data", "-ui-testing-demo-usd-trip"])
        app.tabBars.buttons["Insights"].tap()

        let euro = app.buttons["monthlyBudget"]
        XCTAssertTrue(euro.waitForExistence(timeout: 5))
        let dollar = app.buttons["monthlyBudget.USD"]
        XCTAssertTrue(dollar.waitForExistence(timeout: 5), "a row for the currency of the dollar trip")
        XCTAssertTrue(dollar.label.contains("USD"), "with two currencies each row names its own")

        for (row, amount) in [(euro, "500"), (dollar, "100")] {
            row.tap()
            let field = app.textFields["budgetAmount"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            // The sheet focuses the field while it is still presenting, and on the simulator the
            // keyboard sometimes never comes up, so keys typed then are lost. Tap the field first,
            // and only tap Save once the amount is really in it and Save is enabled.
            field.tap()
            field.typeText(amount)
            let save = app.buttons["saveBudget"]
            let ready = [
                expectation(for: NSPredicate(format: "value == %@", amount), evaluatedWith: field),
                expectation(for: NSPredicate(format: "isEnabled == true AND isHittable == true"), evaluatedWith: save),
            ]
            wait(for: ready, timeout: 5)
            save.tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the sheet closes after saving \(amount)")
        }

        XCTAssertTrue(euro.label.contains("€") && euro.label.contains("of"), "euro row: \(euro.label)")
        XCTAssertTrue(dollar.label.contains("$") && dollar.label.contains("of"), "dollar row: \(dollar.label)")
        XCTAssertFalse(dollar.label.contains("€"), "the dollar row never shows euros: \(dollar.label)")
        snapshot("9c-insights-budgets-two-currencies")
    }

    /// CMP-001: a new Portuguese store takes its chain, and its name, in one tap.
    func testNewStoreTakesAChainInOneTap() throws {
        launch(extraArguments: ["-AppleLocale", "en_PT"])
        app.buttons["openStartTrip"].tap()
        let chip = app.buttons["chain.pingo-doce"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "Portugal's chains are offered for a new store")
        snapshot("12-start-trip-chains")
        chip.tap()
        XCTAssertEqual(app.textFields["storeName"].value as? String, "Pingo Doce", "the chip names the store")
        app.buttons["startTrip"].tap()
        XCTAssertTrue(app.staticTexts["Pingo Doce"].waitForExistence(timeout: 5))

        openStores()
        let picker = app.buttons["storeChain.Pingo Doce"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertFalse(describe(picker).contains("None"), "the store kept its chain: \(describe(picker))")
    }

    /// CMP-001: a store made before chains existed gets one from About → Stores.
    func testOlderStoreGetsAChainInStores() throws {
        launch(extraArguments: ["-AppleLocale", "en_PT", "-ui-testing-demo-data"])
        openStores()
        let picker = app.buttons["storeChain.Continente"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(describe(picker).contains("None"), "demo stores have no chain yet: \(describe(picker))")
        let suggestion = app.buttons["suggestChain.Continente"]
        XCTAssertTrue(suggestion.exists, "the name looks like a chain, so it is offered")
        snapshot("13-stores-suggestion")
        suggestion.tap()
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 5))
        XCTAssertFalse(describe(picker).contains("None"), "Continente is set: \(describe(picker))")
    }

    /// MEAL-001: a meal made from past purchases shows what it costs, in the editor and the list.
    func testMealFromPastPurchasesShowsItsCost() throws {
        launch(extraArguments: ["-AppleLocale", "en_PT", "-ui-testing-demo-data"])
        app.tabBars.buttons["Plan"].tap()
        let meals = app.buttons["planMeals"]
        XCTAssertTrue(meals.waitForExistence(timeout: 5))
        meals.tap()
        let newMeal = app.buttons["newMeal"]
        XCTAssertTrue(newMeal.waitForExistence(timeout: 5))
        snapshot("14-meals-empty")
        newMeal.tap()

        let name = app.textFields["mealName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Breakfast")
        XCTAssertTrue(app.staticTexts["mealCostNone"].exists || app.otherElements["mealCostNone"].exists
                      || text(containing: "No prices yet").exists, "nothing priced before any ingredient")

        for typed in ["nutel", "leite"] {
            let field = app.textFields["ingredientNew"]
            field.tap()
            field.typeText(typed)
            let suggestion = app.buttons["ingredientSuggestion"].firstMatch
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "\(typed) was bought before")
            suggestion.tap()
        }
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "ingredientRow").count, 2)
        // Submitting the empty field closes the keyboard, so the cost is in view again.
        app.textFields["ingredientNew"].typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(text(containing: "at Lidl").waitForExistence(timeout: 5), "each ingredient says where it was cheapest")
        XCTAssertTrue(text(containing: "A serving").exists)
        snapshot("15-meal-editor-cost")

        app.navigationBars.buttons.firstMatch.tap()
        let row = app.descendants(matching: .any).matching(identifier: "mealRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Breakfast") && row.label.contains("a serving"), "list row: \(row.label)")
        snapshot("16-meals-list")
    }

    /// MEAL-002: a week of 10 meals is planned in under two minutes, costs what its meals cost,
    /// and copies into the next week in one tap. (Surviving a relaunch: `MealPlanTests`, since UI
    /// tests run on a throwaway store.)
    func testWeekPlanWithTenMealsInUnderTwoMinutes() throws {
        launch(extraArguments: ["-AppleLocale", "en_PT", "-ui-testing-demo-data", "-ui-testing-demo-meals"])
        app.tabBars.buttons["Plan"].tap()
        let total = app.descendants(matching: .any).matching(identifier: "planWeekTotal").firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("Nothing planned"), "an empty week: \(total.label)")
        snapshot("17-plan-empty")

        let started = Date()
        for index in 0..<10 {
            let add = try XCTUnwrap(firstHittable("planAddSlot"), "an empty slot for meal \(index + 1)")
            add.tap()
            let picks = app.buttons.matching(identifier: "mealPick")
            XCTAssertTrue(picks.firstMatch.waitForExistence(timeout: 5))
            if index == 0 { snapshot("19-plan-picker") }
            // Rotate through the four demo meals, each fully, partly or not priced.
            picks.element(boundBy: index % picks.count).tap()
            XCTAssertTrue(picks.firstMatch.waitForNonExistence(timeout: 5), "the picker closes on a pick")
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 120, "10 meals took \(Int(elapsed)) s")

        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("At least") && total.label.contains("10 meals"),
                      "unpriced ingredients make the week a floor: \(total.label)")
        snapshot("18-plan-week")

        app.buttons["planNextWeek"].tap()
        let copy = app.buttons["planCopyLastWeek"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.label.contains("10"), copy.label)
        copy.tap()
        XCTAssertTrue(total.label.contains("10 meals"), "next week copied: \(total.label)")
        XCTAssertFalse(copy.exists, "nothing left to copy")
    }

    /// The first element with `identifier` that can take a tap, scrolling down to find one.
    private func firstHittable(_ identifier: String, swipes: Int = 6) -> XCUIElement? {
        for _ in 0...swipes {
            let candidates = app.buttons.matching(identifier: identifier).allElementsBoundByIndex
            if let hit = candidates.first(where: { $0.isHittable }) { return hit }
            app.swipeUp()
        }
        return nil
    }

    private func openStores() {
        app.tabBars.buttons["Insights"].tap()
        app.buttons["insightsAbout"].tap()
        let stores = app.buttons["aboutStores"]
        XCTAssertTrue(stores.waitForExistence(timeout: 5))
        stores.tap()
    }

    private func describe(_ element: XCUIElement) -> String {
        "\(element.label) \(element.value as? String ?? "")"
    }

    /// ADD-004: "Start shopping" from a shortcut opens the start sheet, or the scanner mid-trip.
    func testStartShoppingShortcut() throws {
        launch(extraArguments: ["-ui-testing-start-shopping"])
        XCTAssertTrue(app.textFields["storeName"].waitForExistence(timeout: 5), "no trip: the start sheet opens")

        app.terminate()
        launch(extraArguments: ["-ui-testing-start-shopping", "-ui-testing-demo-data", "-ui-testing-demo-trip"])
        XCTAssertTrue(app.buttons["closeScanner"].waitForExistence(timeout: 5), "trip in progress: the scanner opens")
    }

    /// ADD-005: a list line is ticked when its product is scanned, and leaves "Still to get".
    func testShoppingListIsTickedByScanning() throws {
        launch()
        XCTAssertTrue(app.buttons["shoppingList"].waitForExistence(timeout: 5))
        app.buttons["shoppingList"].tap()
        let field = app.textFields["listNewItem"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("leite\n")
        field.typeText("ovos\n")
        snapshot("list-sheet")
        app.buttons["listDone"].tap()
        XCTAssertTrue(app.buttons["Shopping list · 2 to get"].waitForExistence(timeout: 5))

        startTrip(newStore: "Lidl", limit: "20")
        XCTAssertTrue(app.staticTexts["Still to get"].waitForExistence(timeout: 5)
                      || app.staticTexts["STILL TO GET"].exists)
        app.buttons["scan"].tap()
        scan(milk)
        app.textFields["price"].typeText("1,99")
        app.buttons["addItem"].tap()
        app.buttons["closeScanner"].tap()

        // The stubbed Open Food Facts names the milk "Leite meio gordo", which answers "leite".
        XCTAssertTrue(app.staticTexts["Leite meio gordo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "listLine").count == 1, "only ovos is left to get")
        snapshot("list-still-to-get")
    }

    /// LIVE-001: with a trip in progress, the total is in the Dynamic Island and on the Lock Screen.
    func testLiveActivityShowsTheTotal() throws {
        launch(extraArguments: ["-ui-testing-live-activity"])
        startTrip(newStore: "Lidl", limit: "20")
        // Starting the activity can hold the start sheet a moment longer, and a scanner opened
        // while that sheet is still closing does not open at all.
        XCTAssertTrue(app.staticTexts["Lidl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["storeName"].waitForNonExistence(timeout: 5))
        app.buttons["scan"].tap()
        scan(milk)
        app.textFields["price"].typeText("1,99")
        app.buttons["addItem"].tap()
        app.buttons["closeScanner"].tap()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let total = springboard.staticTexts.containing(NSPredicate(format: "label CONTAINS '1,99'")).firstMatch
        let shown = total.waitForExistence(timeout: 10)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "live-activity-island"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(shown, "the Dynamic Island shows the trip total")

        // Finishing the trip takes it down.
        // A tap can land while the app is still zooming back from the Home Screen and be lost.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let done = app.buttons["doneSummary"]
        for _ in 0..<3 where !done.exists {
            app.buttons["finishTrip"].tap()
            _ = done.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(done.exists, "Finish opens the summary")
        done.tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(total.waitForNonExistence(timeout: 10), "the activity ends with the trip")
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
