import XCTest

/// End-to-end trip flows on the simulator. The camera is replaced by `SimulatedScanner`
/// (`-ui-testing` + `UITEST_SCAN_CODES`), everything else is the real app on a throwaway store.
@MainActor
final class TripFlowUITests: XCTestCase {
    private var app = XCUIApplication()
    private let milk = "5601234567892"
    private let bread = "4006381333931"
    private let nutella = "3017620422003"

    override nonisolated func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Each test launches explicitly: XCTest's setUp is nonisolated, and an async `@MainActor`
    /// setUp crashes on some Xcode 26 runtimes (see LuminaVaultClient's ci.yml).
    private func launch(extraArguments: [String] = []) {
        app.launchArguments = ["-ui-testing"] + extraArguments
        app.launchEnvironment["UITEST_SCAN_CODES"] = "\(milk),\(bread),\(nutella)"
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
        XCTAssertFalse(app.staticTexts["tripSaving"].exists, "no other store, so no saving")
        XCTAssertFalse(app.staticTexts["tripMissedSaving"].exists)
        app.buttons["doneSummary"].tap()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5))

        // History shows the trip and the month total.
        openTab("History")
        XCTAssertTrue(app.staticTexts["monthTotal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["monthTotal"].label.contains("3,98"))
        snapshot("7-history")

        // Next trip at Lidl: the milk price is remembered, so the scan alone adds it.
        openTab("Trip")
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
        openTab("Insights")
        XCTAssertTrue(app.staticTexts["This month"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Average trip"].exists)
        XCTAssertTrue(app.staticTexts["5 of 5"].exists, "all demo trips stayed under their limit")
        // SAVE-003: the month's saving under the headline tiles. Demo trips are relative to today,
        // so the amount is checked in unit tests with a fixed date, not here.
        let savings = app.descendants(matching: .any)["savingsTile"]
        XCTAssertTrue(savings.waitForExistence(timeout: 5))
        XCTAssertTrue(savings.label.contains("this month"), "savings tile label: \(savings.label)")
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

        // Scroll until each section shows, not a fixed number of swipes: the savings tile and
        // "Where you'd save most" (SAVE-003) change the screen's height with the date.
        let risers = app.staticTexts["Prices that went up"]
        for _ in 0..<6 where !(risers.exists && risers.isHittable) { app.swipeUp() }
        XCTAssertTrue(risers.waitForExistence(timeout: 5) || app.staticTexts["PRICES THAT WENT UP"].exists)
        snapshot("10-insights-lists")
        let basket = app.staticTexts["Your regular basket"]
        for _ in 0..<6 where !(basket.exists && basket.isHittable) { app.swipeUp() }
        XCTAssertTrue(basket.waitForExistence(timeout: 5), "INS-10 shown")
        snapshot("11-insights-your-prices")
    }

    /// BUD-001: a € budget and a $ budget each show against their own month's spending.
    func testBudgetsInTwoCurrencies() throws {
        launch(extraArguments: ["-ui-testing-demo-data", "-ui-testing-demo-usd-trip"])
        openTab("Insights")

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
        openTab("Plan")
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
        openTab("Plan")
        let total = app.descendants(matching: .any).matching(identifier: "planWeekTotal").firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("Nothing planned"), "an empty week: \(total.label)")
        snapshot("17-plan-empty")

        let started = Date()
        for index in 0..<10 {
            try XCTUnwrap(firstHittable("planAddSlot"), "an empty slot for meal \(index + 1)").tap()
            // Rotate through the four demo meals, each fully, partly or not priced.
            pickMeal(demoMeals[index % demoMeals.count], snapshotName: index == 0 ? "19-plan-picker" : nil)
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

    /// MEAL-003: two planned meals that share bread put one "2 × Pão de forma" line on the list,
    /// what is at home stays off, and scanning the bread ticks the line.
    func testPlannedWeekGoesOnTheListAndAScanTicksIt() throws {
        launch(extraArguments: ["-AppleLocale", "en_PT", "-ui-testing-demo-meals"])
        openTab("Plan")
        for name in ["Pequeno-almoço", "Tosta mista"] {
            try XCTUnwrap(firstHittable("planAddSlot"), "an empty slot for \(name)").tap()
            pickMeal(name)
        }
        app.swipeDown()
        let addToList = app.buttons["planAddToList"]
        XCTAssertTrue(addToList.waitForExistence(timeout: 5))
        addToList.tap()

        let lines = app.buttons.matching(identifier: "planListLine")
        XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(lines.count, 5, "milk, bread, Nutella, cheese, ham")
        let breadLine = lines.matching(NSPredicate(format: "label CONTAINS %@", "2 × Pão de forma")).firstMatch
        XCTAssertTrue(breadLine.exists, "one line for both meals")
        XCTAssertTrue(breadLine.label.contains("Pequeno-almoço") && breadLine.label.contains("Tosta mista"), breadLine.label)
        lines.matching(NSPredicate(format: "label CONTAINS %@", "Queijo")).firstMatch.tap()
        snapshot("20-plan-to-list")
        XCTAssertEqual(app.buttons["planListAdd"].label, "Add 4 items", "the cheese is at home")
        app.buttons["planListAdd"].tap()
        let added = app.staticTexts["planAddedToList"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertTrue(added.label.contains("4 items"), added.label)

        openTab("Trip")
        XCTAssertTrue(app.buttons["Shopping list · 4 to get"].waitForExistence(timeout: 5))
        startTrip(newStore: "Lidl", limit: "60")
        XCTAssertTrue(app.buttons.matching(identifier: "listLine")
            .matching(NSPredicate(format: "label CONTAINS %@", "2 × Pão de forma")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["scan"].tap()
        scan(bread)
        app.textFields["price"].typeText("1,39")
        app.buttons["addItem"].tap()
        app.buttons["closeScanner"].tap()
        XCTAssertTrue(app.staticTexts["Pão de forma"].waitForExistence(timeout: 5))
        let waiting = app.buttons.matching(identifier: "listLine")
        XCTAssertEqual(waiting.count, 3, "the scan ticked the bread")
        XCTAssertFalse(waiting.matching(NSPredicate(format: "label CONTAINS %@", "Pão de forma")).firstMatch.exists)
    }

    /// SAVE-002. A new store against the demo prices: bread €0,99 vs a median of €1,39 and €1,49 (€1,44)
    /// saves €0,45; Nutella €4,39 vs €4,09 and €4,29 (€4,19) costs €0,20 more and was €0,30 cheaper at
    /// Lidl. So the trip saved €0,25 and could have saved €0,30 at Lidl.
    func testListCostStartsTheTripAtTheCheapestStore() throws {
        launch(extraArguments: ["-AppleLocale", "en_PT", "-ui-testing-demo-data", "-ui-testing-demo-list"])
        let list = app.buttons["shoppingList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        list.tap()

        // Worked by hand in `DemoData.seedList`: the sum of each store's remembered prices.
        let lidl = app.descendants(matching: .any)["listCost.Lidl"]
        for _ in 0..<4 where !(lidl.exists && lidl.isHittable) { app.swipeUp() }
        XCTAssertTrue(lidl.waitForExistence(timeout: 5))
        XCTAssertTrue(lidl.label.contains("11,26"), lidl.label)
        let continente = app.descendants(matching: .any)["listCost.Continente"]
        XCTAssertTrue(continente.label.contains("11,76"), continente.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 item has no price yet"))
            .firstMatch.exists, "Queijo is typed")
        snapshot("23-list-cost")

        let start = app.buttons["listStartTrip"]
        XCTAssertTrue(start.label.contains("Lidl"), start.label)
        start.tap()

        // The start sheet opens at Lidl with the estimate, rounded up, as the limit.
        let limit = app.textFields["limit"]
        XCTAssertTrue(limit.waitForExistence(timeout: 5))
        // The field exists while the sheet is still sliding up, before it is filled in.
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "12,00"), object: limit)
        XCTAssertEqual(XCTWaiter.wait(for: [filled], timeout: 5), .completed, "limit: \(limit.value ?? "nil")")
        XCTAssertTrue(app.buttons["Lidl"].isSelected)
        XCTAssertTrue(app.buttons["List €12,00"].exists, "the estimate chip")
        snapshot("24-start-from-list")

        // A store with no estimate clears the estimate's limit and its chip; back at Lidl the chip
        // returns and sets it again.
        app.buttons["New store"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "No limit"), object: limit)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed, "limit: \(limit.value ?? "nil")")
        XCTAssertFalse(app.buttons["List €12,00"].exists)
        // The new store's chain chips include one called Lidl too; tap the store, not the chain.
        app.buttons.matching(NSPredicate(format: "label == 'Lidl' AND NOT (identifier BEGINSWITH 'chain.')"))
            .firstMatch.tap()
        let chip = app.buttons["List €12,00"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        let refilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "12,00"), object: limit)
        XCTAssertEqual(XCTWaiter.wait(for: [refilled], timeout: 5), .completed, "limit: \(limit.value ?? "nil")")
        app.buttons["startTrip"].tap()
        XCTAssertTrue(text(containing: "left").waitForExistence(timeout: 5), "the trip has the limit")

        // MEAL-005: Nutella was on the list, bread was not. Both have a price at Lidl, so each scan
        // adds at once (ADD-001): 4,09 + 1,39 = 5,48 spent against the €11,26 planned there.
        app.buttons["scan"].tap()
        // The cart total, not the banner: the banner hides itself after a moment.
        for code in [nutella, bread] { scan(code) }
        app.buttons["closeScanner"].tap()
        XCTAssertTrue(text(containing: "5,48").waitForExistence(timeout: 10), "both items added")
        app.buttons["finishTrip"].tap()
        XCTAssertTrue(app.navigationBars["Trip finished"].waitForExistence(timeout: 5))

        let planned = app.descendants(matching: .any)["tripPlanned"]
        XCTAssertTrue(planned.waitForExistence(timeout: 5))
        XCTAssertTrue(planned.label.contains("11,26"), planned.label)
        let vsPlan = app.descendants(matching: .any)["tripVsPlan"]
        XCTAssertEqual(vsPlan.label, "You spent €5,78 less than planned")
        let extra = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'offPlan.'"))
        for _ in 0..<4 where !(extra.firstMatch.exists && extra.firstMatch.isHittable) { app.swipeUp() }
        XCTAssertEqual(extra.count, 1, "only the bread was off the plan")
        XCTAssertTrue(extra.firstMatch.label.contains("1,39"), extra.firstMatch.label)
        snapshot("25-summary-plan")
    }

    func testFinishedTripShowsItsSavingAndHistoryToo() throws {
        launch(extraArguments: ["-AppleLocale", "en_PT", "-ui-testing-demo-data"])
        app.buttons["openStartTrip"].tap()
        let newStore = app.buttons["New store"]
        XCTAssertTrue(newStore.waitForExistence(timeout: 5))
        newStore.tap()
        app.buttons["chain.pingo-doce"].tap()
        app.buttons["startTrip"].tap()
        app.buttons["scan"].tap()
        for (code, typed) in [(bread, "0,99"), (nutella, "4,39")] {
            scan(code)
            let price = app.textFields["price"]
            XCTAssertTrue(price.waitForExistence(timeout: 5))
            price.tap()
            price.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + typed)
            app.buttons["addItem"].tap()
            XCTAssertTrue(price.waitForNonExistence(timeout: 5))
        }
        app.buttons["closeScanner"].tap()
        app.buttons["finishTrip"].tap()
        XCTAssertTrue(app.navigationBars["Trip finished"].waitForExistence(timeout: 5))

        let saving = app.staticTexts["tripSaving"]
        XCTAssertTrue(saving.waitForExistence(timeout: 5))
        XCTAssertTrue(saving.label.contains("Saved") && saving.label.contains("0,25"), saving.label)
        let missed = app.staticTexts["tripMissedSaving"]
        XCTAssertTrue(missed.label.contains("0,30") && missed.label.hasSuffix("at Lidl"), missed.label)
        snapshot("21-summary-saving")
        app.buttons["doneSummary"].tap()

        openTab("History")
        let rows = app.staticTexts.matching(identifier: "tripRowSaving")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let labels = rows.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.contains("Saved") && $0.contains("0,25") }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.contains("1,46") && $0.contains("more than elsewhere") }, "\(labels)")
        snapshot("22-history-saving")
    }

    /// `DemoData.seedMeals`, in the picker's order.
    private let demoMeals = ["Arroz de pato", "Iogurte e café", "Pequeno-almoço", "Tosta mista"]

    /// Picks a meal in the open picker. A tap that lands while the sheet is still sliding up is
    /// lost, so it taps again until the picker closes.
    private func pickMeal(_ name: String, snapshotName: String? = nil) {
        let pick = app.buttons.matching(identifier: "mealPick")
            .matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5), "\(name) is in the picker")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: pick)], timeout: 3)
        if let snapshotName { snapshot(snapshotName) }
        for _ in 0..<3 where pick.exists {
            pick.tap()
            _ = pick.waitForNonExistence(timeout: 3)
        }
        XCTAssertFalse(pick.exists, "the picker closes on a pick of \(name)")
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

    /// Taps a tab until it is selected: a tap that lands while the app is still launching is lost.
    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "the \(name) tab")
        for _ in 0..<3 where !tab.isSelected {
            tab.tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: tab)], timeout: 2)
        }
        XCTAssertTrue(tab.isSelected, "the \(name) tab opens")
    }

    private func openStores() {
        openTab("Insights")
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
        openTab("Insights")
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
        // A tap that lands while the app is still settling after launch is lost, so tap again.
        let start = app.buttons["openStartTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        for _ in 0..<3 where !app.buttons["unlock"].exists {
            start.tap()
            _ = app.buttons["unlock"].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(app.buttons["unlock"].exists, "paywall instead of the start sheet")
        XCTAssertTrue(text(containing: "this month").exists)
        snapshot("12-paywall")
        app.buttons["notNow"].tap()
        XCTAssertTrue(app.buttons["openStartTrip"].waitForExistence(timeout: 5), "dismissable at no cost")
        snapshot("12b-empty-trip-last-trip")
        XCTAssertFalse(app.textFields["storeName"].exists)

        openTab("History")
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
