import XCTest

/// Walks the screens changed for the November 2026 pilot feedback and saves a screenshot of each to
/// /tmp/logsperity-shots for review. Not part of the shipped app.
@MainActor
final class FeedbackCheck: XCTestCase {
    private let app = XCUIApplication()
    private let folder = URL(fileURLWithPath: "/tmp/logsperity-shots")

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func testFeedbackScreens() {
        app.launch()
        tap(app.buttons["Explore with a sample year first"])
        scrollTo(app.staticTexts["Monthly charges"])
        shot("01-today-monthly-charges")

        // A prospect saved with only a first name becomes a hint.
        quickAdd("Prospect")
        shot("02-prospect-form-required-red")
        type("Ana", into: app.textFields["First name"])
        shot("03-prospect-save-as-hint")
        tap(app.buttons["Save as hint"])

        // A known source fills in pillar, category and activity.
        quickAdd("Prospect")
        type("Becker", into: app.textFields["Last name"])
        type("Tom", into: app.textFields["First name"])
        type("Ana", into: app.textFields["Second first name (couples)"])
        type("Dana Ruiz", into: app.textFields["Who or what sent it"])
        app.navigationBars.firstMatch.tap()  // dismiss the keyboard
        shot("04-prospect-filled-from-source")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pillar'")).firstMatch)
        shot("05-pillar-order-parc")
        tap(app.buttons["Relationships"])
        swipeUp(2)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan of action'")).firstMatch)
        shot("06-plan-of-action")
        tap(app.buttons["Text"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Strength'")).firstMatch)
        shot("07-strength-colors")
        tap(app.buttons["Hot"])
        tap(app.buttons["Save"])

        tab("Log")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prospects'")).firstMatch)
        shot("08-prospects-strength-colors")
        back()
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Review queue'")).firstMatch)
        shot("09-review-queue-hint")
        back()
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Activity'")).firstMatch)
        shot("10-activity-quarter-hours")
        back()

        tab("Today")
        quickAdd("Expense")
        shot("11-expense-blank-group-recurring")
        type("cedar grill", into: app.textFields["Vendor"])
        shot("12-expense-vendor-capitalized")
        tap(app.buttons["Cancel"])

        quickAdd("Trip")
        tap(app.textFields["Reason"])
        shot("13-trip-reason-suggestions")
        tap(app.buttons["Cancel"])

        quickAdd("Activity")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pillar'")).firstMatch)
        tap(app.buttons["Clients"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Activity'")).firstMatch)
        shot("14-client-activities-social-media")
        app.navigationBars.firstMatch.tap()
        tap(app.buttons["Cancel"])

        quickAdd("Closing")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Choose from Prospects'")).firstMatch)
        shot("15-closing-prospects-alphabetical")
    }

    // MARK: Helpers

    private func shot(_ name: String) {
        pause(1.2)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    private func pause(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func tap(_ e: XCUIElement) {
        guard e.waitForExistence(timeout: 5) else { print("⚠️ Not found: \(e)"); return }
        e.tap()
        pause(0.8)
    }

    private func type(_ text: String, into field: XCUIElement) {
        tap(field)
        field.typeText(text)
        pause(0.5)
    }

    private func quickAdd(_ kind: String) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", kind)).firstMatch
        scrollTo(button)
        tap(button)
    }

    private func scrollTo(_ e: XCUIElement) {
        for _ in 0..<8 where !(e.exists && e.isHittable) { swipeUp(1) }
    }

    private func swipeUp(_ n: Int) {
        let w = app.windows.firstMatch
        for _ in 0..<n {
            w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            pause(0.6)
        }
    }

    private func tab(_ name: String) {
        tap(app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : app.buttons[name])
    }

    private func back() {
        let b = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
        pause(0.8)
    }
}
