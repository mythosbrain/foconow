import XCTest

final class HabitCounterUITests: XCTestCase {
    func testAppearancePersistsAndFollowsSystem() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Today is yours."].waitForExistence(timeout: 25))
        web.buttons["Settings and backup"].tap()
        let light = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Light appearance")).firstMatch
        XCTAssertTrue(light.waitForExistence(timeout: 5))
        light.tap()
        XCTAssertTrue(web.staticTexts["Light mode is on."].waitForExistence(timeout: 5))
        capture("Light settings", app)
        web.buttons["Close dialog"].tap()
        capture("Light home", app)
        web.buttons["Settings and backup"].tap()
        web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Dark appearance")).firstMatch.tap()
        XCTAssertTrue(web.staticTexts["Dark mode is on."].waitForExistence(timeout: 5))
        capture("Dark settings", app)
        web.buttons["Close dialog"].tap()
        capture("Dark home", app)
        app.terminate()
        app.launch()
        XCTAssertTrue(web.staticTexts["Today is yours."].waitForExistence(timeout: 25))
        web.buttons["Settings and backup"].tap()
        XCTAssertTrue(web.staticTexts["Dark mode is on."].waitForExistence(timeout: 5))
        web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "System appearance")).firstMatch.tap()
        XCTAssertTrue(web.staticTexts["Matches your device’s appearance."].waitForExistence(timeout: 5))
        web.buttons["Close dialog"].tap()
        capture("System home", app)
    }

    func testDailyFlowAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Today is yours."].waitForExistence(timeout: 25))
        capture("Today", app)
        web.buttons["Edit habit and start date"].tap()
        let name = web.textFields["Habit name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
        capture("Habit editor", app)
        web.buttons["Save changes"].tap()
        web.buttons["Open today’s check-in"].tap()
        let mood = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Good mood")).firstMatch
        XCTAssertTrue(mood.waitForExistence(timeout: 5))
        mood.tap()
        capture("Check-in", app)
        web.buttons["Save check-in"].tap()
        XCTAssertTrue(web.staticTexts["Feeling good · see you tomorrow."].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(web.staticTexts["Today is yours."].waitForExistence(timeout: 20))
        for _ in 0..<5 {
            if web.staticTexts["Feeling good · see you tomorrow."].isHittable { break }
            web.swipeUp()
        }
        XCTAssertTrue(web.buttons["Edit today’s check-in"].exists)
        XCTAssertTrue(web.buttons["Edit today’s check-in"].isEnabled)
        web.links["My journal"].tap()
        XCTAssertTrue(web.staticTexts["Put it into words."].waitForExistence(timeout: 5))
        capture("Journal", app)
        web.buttons["Write an entry"].tap()
        let thoughts = web.textViews["Your thoughts"]
        XCTAssertTrue(thoughts.waitForExistence(timeout: 5))
        thoughts.tap()
        thoughts.typeText("A little more space for what matters.")
        web.buttons["Save to my journal"].tap()
        XCTAssertTrue(web.staticTexts["A little more space for what matters."].waitForExistence(timeout: 5))
        web.links["Insights"].tap()
        XCTAssertTrue(web.staticTexts["See your progress."].waitForExistence(timeout: 5))
        capture("Insights", app)
        web.links["Today"].tap()
        web.buttons["Breathe"].tap()
        web.buttons["Start 60-second breathing"].tap()
        XCTAssertTrue(web.staticTexts["Breathe in…"].waitForExistence(timeout: 3))
        capture("Breathe", app)
    }
    func testPremiumToolsAndReminder() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Today is yours."].waitForExistence(timeout: 25))
        capture("Premium home", app)
        web.buttons["Log an urge"].tap()
        XCTAssertTrue(web.staticTexts["Notice the moment"].waitForExistence(timeout: 5))
        let note = web.textViews.matching(NSPredicate(format: "label BEGINSWITH %@", "A note to yourself")).firstMatch
        note.tap(); note.typeText("Paused before opening my phone.")
        capture("Urge log", app)
        web.buttons["Save this moment"].tap()
        web.links["My journal"].tap()
        XCTAssertTrue(web.staticTexts["Put it into words."].waitForExistence(timeout: 5))
        let search = web.searchFields["Search journal"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Paused before opening")
        XCTAssertTrue(web.staticTexts["Paused before opening my phone."].waitForExistence(timeout: 5))
        capture("Searchable journal", app)
        web.links["Today"].tap()
        let customize = web.buttons["Customize daily intentions"]
        for _ in 0..<7 { if customize.isHittable { break }; web.swipeUp() }
        customize.tap()
        XCTAssertTrue(web.staticTexts["Small wins, your way"].waitForExistence(timeout: 5))
        capture("Custom intentions", app)
        web.buttons["Save my intentions"].tap()
        web.links["Insights"].tap()
        XCTAssertTrue(web.staticTexts["More than a streak."].waitForExistence(timeout: 5))
        capture("Weekly review", app)
        web.buttons["Settings and backup"].tap()
        let reminder = web.buttons["Daily reminder"]
        for _ in 0..<5 { if reminder.isHittable { break }; web.swipeUp() }
        reminder.tap()
        XCTAssertTrue(web.staticTexts["A gentle daily reminder"].waitForExistence(timeout: 5))
        capture("Reminder settings", app)
        web.buttons["Cancel"].tap()
    }

    func testReminderCanBeScheduledAndTurnedOff() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Today is yours."].waitForExistence(timeout: 25))
        web.buttons["Settings and backup"].tap()
        let button = web.buttons["Daily reminder"]
        for _ in 0..<5 { if button.isHittable { break }; web.swipeUp() }
        button.tap()
        let toggle = web.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" { toggle.tap() }
        web.buttons["Save reminder"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        XCTAssertTrue(web.staticTexts["Your daily reminder is set."].waitForExistence(timeout: 5))
        web.buttons["Settings and backup"].tap()
        let reopen = web.buttons["Daily reminder"]
        for _ in 0..<5 { if reopen.isHittable { break }; web.swipeUp() }
        reopen.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        capture("Enabled reminder", app)
        toggle.tap()
        web.buttons["Save reminder"].tap()
        XCTAssertTrue(web.staticTexts["Daily reminder turned off."].waitForExistence(timeout: 5))
    }

    func testAppLimitsScreenShowsHonestSimulatorState() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Today is yours."].waitForExistence(timeout: 25))
        let focus = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Protect your focus")).firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        focus.tap()
        XCTAssertTrue(app.navigationBars["App limits"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Make room for what matters."].exists)
        let authorize = app.buttons["focus-authorize"]
        XCTAssertTrue(authorize.exists)
        XCTAssertFalse(authorize.isEnabled)
        capture("App limits setup", app)
        app.buttons["focus-done"].tap()
        XCTAssertTrue(web.staticTexts["Today is yours."].waitForExistence(timeout: 10))
        XCTAssertTrue(web.buttons["Open today’s check-in"].isEnabled)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
