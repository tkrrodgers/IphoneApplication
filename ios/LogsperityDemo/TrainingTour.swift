import AVFoundation
import XCTest

/// A narrated training tour of Logsperity for filming. It starts from a fresh install, walks every tab and HERB's
/// main conversations, and speaks a narration between steps. HERB answers in its own voice (HERB speaks replies).
/// Not part of the shipped app. Run it with demo/run-demo.sh; the narration also prints to the log as subtitles.
@MainActor
final class TrainingTour: XCTestCase {
    private let app = XCUIApplication()
    private let narrator = Narrator()

    override func setUp() {
        continueAfterFailure = true
        executionTimeAllowance = 60 * 60
    }

    /// demo/run-demo.sh --voice-check: one line from the narrator, to set the volume before filming.
    func testVoiceCheck() {
        say("This is the narrator for the Logsperity training. If you can hear me clearly, you're ready to film.")
    }

    /// Rehearses just Reports and Coach on the sample year (not used for filming).
    func testReportsAndCoach() {
        app.launch()
        if app.buttons["Explore with a sample year first"].waitForExistence(timeout: 3) { tap(app.buttons["Explore with a sample year first"]) }
        reports()
        coach()
        XCTAssertTrue(app.navigationBars["Coach"].exists || app.staticTexts["Coach"].exists, "Coach tab didn't open")
    }

    func testTrainingTour() {
        app.launch()
        pause(4)  // time to start the camera

        welcome()
        setUp_account()
        today()
        herb()
        logTab()
        reports()
        coach()
        more()

        tab("Today")
        say("That's the tour. Log in about a minute a day, talk to HERB when your hands are busy, and check Coach once a week. Thanks for piloting Logsperity.")
        pause(3)
    }

    // MARK: Chapters

    private func welcome() {
        say("Welcome to Logsperity training. Logsperity helps sales professionals know their numbers, maximize their time, and multiply their prosperity.")
        say("This is the welcome screen you see the first time you open the app. It covers the four big ideas.")
        say("Six simple logs: prospects, closings, income, expenses, mileage, and activity. Logging takes about a minute a day.")
        say("Logsperity turns those logs into your numbers: conversion rates, hourly rates, return on investment by pillar, and the Logsperity Index.")
        say("HERB is your built in coach. Talk or type, and HERB fills in the entry, asks for anything missing, and saves only when you say yes.")
        say("And it's private. Everything stays on your iPhone.")
    }

    private func setUp_account() {
        say("Tap Get started to set up your account.")
        tap(app.buttons["Get started"])
        say("First, tell Logsperity about you. Your name, company and profession are the only things it needs.")
        type("Tom Rodgers", into: app.textFields["Name"])
        type("Prosperity Simplified", into: app.textFields["Company"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Profession'")).firstMatch)
        tap(app.buttons["Lender"])
        say("Your contact details are optional. Tap Next.")
        tap(app.buttons["Next"])

        say("Next is your business plan. Enter your annual gross income goal, your net profit goal, your average commission, your average transaction size, the hours you work each week, and your weeks of vacation.")
        scroll(2)
        say("As you type, Logsperity shows you what that plan really means: monthly income, the transactions you need each month, the volume you need, and your hourly rate. This is your business.")
        tap(app.buttons["Next"])

        say("Last, you can turn on a daily reminder to log, and choose how many questions HERB asks. Quick asks only what's required, Balanced is the default, and Thorough asks for everything.")
        pause(1)
        say("You'd tap Start using Logsperity here. For this training we'll go back and load a sample year instead, so every screen has real looking numbers.")
        for _ in 0..<3 { tap(app.navigationBars.buttons["Back"]) }
        say("The sample year belongs to Marcus Reed, a fictional mortgage lender. Tap Explore with a sample year first.")
        tap(app.buttons["Explore with a sample year first"])
        pause(1)
    }

    private func today() {
        say("This is the Today tab, your home screen. It greets you, and the Ask HERB button is always at the top.")
        say("Below it are your key numbers at a glance.")
        scroll(1)
        say("When HERB logs something on its own, like a trip, it waits here for you to review. Then come this week's focus, the three things that will move your business most.")
        scroll(1)
        say("Follow-ups shows who to call today. Late ones are marked in red, new ones in orange.")
        scroll(2)
        say("At the bottom, Quick add opens any of the six logs with one tap. Let's open a prospect.")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Prospect'")).firstMatch)
        say("Every log has a simple form. Name and phone, where the lead came from, how strong it is, and when to follow up.")
        scroll(2)
        say("Save closes the form. Save and Next keeps it open for the next entry. We'll cancel this one.")
        tap(app.buttons["Cancel"])
        scrollToTop()
    }

    private func herb() {
        say("Now let's meet HERB. Tap Ask HERB.")
        tap(app.buttons["Ask HERB"])
        say("On your iPhone, tap the microphone and just talk. HERB also understands typing. These examples show what you can say. Tap one to try it.")

        say("First, a new prospect. HERB pulls out the name, the phone number and the follow-up date, then asks about anything missing, one question at a time.")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '“New prospect Tom Rodgers'")).firstMatch)
        waitForHerb("Got it, Tom Rodgers, mobile 847 477 0619, follow-up tomorrow. Do you want to add an address?")
        say("You can answer by voice, by typing, or with a quick reply button. We'll tap No.")
        tap(app.buttons["No"])
        waitForHerb("Okay. Who referred Tom, or where did the lead come from?")
        say("HERB always asks where a lead came from, because that's how Logsperity knows which sources pay off.")
        herb("Ruth Alvarez sent him", reply: "Tom Rodgers, mobile 847 477 0619, from Ruth Alvarez, follow-up tomorrow. Save it?")
        say("HERB recognized Ruth as a realtor. The card shows exactly what will be saved. Nothing is saved until you say yes.")
        herb("yes", reply: "Saved Tom Rodgers. I'll remind you to follow up tomorrow.")

        say("Next, an expense. Just say what you spent.")
        herb("I spent 45 dollars on lunch with Dana Ruiz", reply: "Got it, 45 dollars, meal, with Dana Ruiz. Which restaurant?")
        herb("Cedar Grill", reply: "45 dollars at Cedar Grill with Dana Ruiz, as Meal. Save it?")
        say("HERB picked the expense category and the IRS category for you. Tap Save.")
        tap(app.buttons["Save"].firstMatch)
        waitForHerb("Expense saved.")

        say("Time spent building your business counts too.")
        herb("Two hours of door knocking, got two leads", reply: "2 hours of Door Knocking. You mentioned 2 leads. I'll help you add them after this. Save it?")
        herb("yes", reply: "Activity saved. You mentioned 2 leads from Door Knocking. Want to add them now?")
        tap(app.buttons["Later"])
        waitForHerb("Okay. You can add them from the Log tab any time.")

        say("Income works the same way.")
        herb("Got a 2,000 referral fee from Lakeside Realty", reply: "2,000 dollars referral fees from Lakeside Realty. Save it?")
        herb("yes", reply: "Income saved.")

        say("If you're driving and can't finish, just say so. HERB saves what it has to the Review queue and asks the rest later.")
        herb("New prospect Priya Patel, follow up tomorrow", reply: "Got it, Priya Patel, follow-up tomorrow. Do you want to add an address and phone number?")
        herb("I'm driving", reply: "Saved to your Review queue. I'll ask about the address, the phone number and the source later. Drive safe.")

        say("HERB is also your coach. Ask it about your business.")
        herb("What should I focus on this week?", reply: "Three things this week: 1. Call your 8 hot prospects, Priya Shah, Tom and Ana Becker, Raj Nguyen, about 18 thousand of likely income. 2. Ask Dana Torres for a review. Your closing follow-up is due. Past clients are your best source. 3. Coffee with Jared Cole. 4 closings in the last year, but 59 days since you talked. One to drop: Door Knocking. 10 hours this year, 0 closings, 0 dollars an hour.")
        herb("Who should I follow up with today?", reply: "7 today. 3 are urgent: Lena Ortiz, met at Saturday's open house, not called yet, and Priya Shah, pre-approval expires Nov 4. Last contact Oct 21. Also Tom and Ana Becker: rate-lock decision call at 2 PM. Want me to draft texts to Lena and Priya?")
        herb("Am I on track for my plan?", reply: "Income is 119 percent of pace: 178 thousand against 150 thousand projected by today. Profit is at 121 percent of pace. I forecast about 226 thousand for the year against your 180 thousand goal.")
        herb("Which sources never close?", reply: "These sources send prospects that never close: LeadBoost, 12 prospects; Savannah neighborhood, 5 prospects; Grace Community Church, 3 prospects. You've spent 950 dollars on LeadBoost this year.")
        say("That's the kind of insight that saves real money. Marcus has spent 950 dollars on a lead service that has never produced a closing.")
        herb("What's my Logsperity Index?", reply: "Your Logsperity Index is 90, below the healthy baseline. 100 is a healthy business. The biggest lever is conversion: 19 percent against a benchmark of 30 percent.")

        say("HERB can open any report for you, too.")
        herb("Email me the March report", reply: "Here's your March report. Tap Email it and I'll open Mail with the report. You press send.")
        tap(app.buttons["Open report"])
        pause(2)
        scroll(1)
        say("Every report can be shared or printed as a PDF.")
        swipeDownSheet()
        say("Tap Done to close HERB.")
        tap(app.buttons["Done"])
    }

    private func logTab() {
        tab("Log")
        say("The Log tab holds all six logs, with this year's totals beside each one.")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prospects'")).firstMatch)
        say("Here's every prospect, newest first. Tom Rodgers, who we just added with HERB, is at the top. Swipe left on any row to delete it.")
        say("Tap a row to see or change it.")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Tom Rodgers'")).firstMatch)
        pause(1.5)
        scroll(1)
        tap(app.buttons["Cancel"])
        scroll(1)
        back()

        say("At the bottom of the Log tab is the Review queue. These are items HERB captured for you, like Priya Patel from a moment ago and trips it noticed.")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Review queue'")).firstMatch)
        say("For each one, tap Yes to confirm it, Edit to change it, or Dismiss to throw it away.")
        tap(app.buttons["Yes"].firstMatch)
        pause(1)
        back()
    }

    private func reports() {
        tab("Reports")
        say("The Reports tab has four groups. Logs print your raw entries. Quick Stats give you the headlines. Detailed Reports dig into each part of your business. And there's a report for every month and the year to date.")
        tap(app.buttons["Profit"])
        say("This is the Profit quick stat: income, expenses, and what you kept.")
        scroll(2)
        back()
        reveal(app.buttons["Source Conversion Report"])
        tap(app.buttons["Source Conversion Report"])
        say("Detailed reports have a period picker. You can look at this month, last month, this quarter, the year to date, the last 30 days, or last year.")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Period'")).firstMatch)
        tap(app.buttons["This quarter"])
        pause(1)
        scroll(2)
        say("Tap the share button to send or print the report as a PDF.")
        tap(app.buttons["Share or print as PDF"])
        pause(3)
        closeShareSheet()
        back()
    }

    private func coach() {
        tab("Coach")
        say("The Coach tab is where you step back once a week. At the top is the Logsperity Index. 100 means a healthy business. It combines your conversion, your return on what you spend, and your profit margin.")
        scroll(1)
        say("The chart shows your index month by month. Below that, the business plan tracker compares what you've actually done with where your plan says you should be today, and forecasts your year.")
        scroll(1)
        say("Then this week's focus, and HERB's coaching insights. Each insight explains a pattern HERB found in your numbers. You can dismiss any you've already handled.")
        scroll(2)
        pause(1)
        scrollToTop()
    }

    private func more() {
        tab("More")
        say("Finally, the More tab.")
        open("Account", "Account holds your details.")
        open("Business Plan Set Up", "Business Plan Set Up lets you change your goals for this year, or plan ahead for next year.", scrolls: 1)
        open("Input Cheat Sheet", "The Input Cheat Sheet explains pillars, categories, sources and activities, and the rules HERB follows for you.", scrolls: 2)
        open("HERB", "In HERB settings, choose how many questions HERB asks, whether HERB speaks its replies, and your daily reminder.")
        open("About this pilot", "About this pilot explains what's in this version and what's coming next. Above it is a link to email customer service.")
        say("Under Data and privacy you can export your data, load the sample year, or erase everything. Remember, your logs live only on your iPhone.")
        pause(1)
    }

    // MARK: Helpers

    private func say(_ text: String) {
        print("🎙 \(text)")
        narrator.speak(text)
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 6) else {
            print("⚠️ Not found: \(element)")
            return
        }
        element.tap()
        pause(1)
    }

    /// Scrolls until an off-screen row is on screen.
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { scroll(1) }
    }

    private func type(_ text: String, into field: XCUIElement) {
        tap(field)
        for word in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            field.typeText((word.offset == 0 ? "" : " ") + word.element)
            pause(0.15)
        }
        pause(0.5)
    }

    /// Types a line to HERB, sends it, and waits while HERB speaks its reply.
    private func herb(_ text: String, reply: String) {
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        type(text, into: field)
        tap(app.buttons["Send"])
        hideKeyboard()
        waitForHerb(reply)
    }

    /// A small scroll on the chat hides the keyboard so the draft card stays in view.
    private func hideKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        pause(0.5)
    }

    /// HERB speaks at about 2.8 words a second; `reply` is what it will say, used only for timing.
    private func waitForHerb(_ reply: String) {
        let words = reply.split(separator: " ").count
        pause(Double(words) / 2.6 + 1)
    }

    /// Switches tabs, tapping again if a closing sheet swallowed the first tap.
    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : app.buttons[name]
        for _ in 0..<3 where !button.isSelected {
            tap(button)
            pause(0.5)
        }
    }

    /// Opens a row, explains it while it's on screen, and goes back.
    private func open(_ row: String, _ narration: String, scrolls: Int = 0) {
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch)
        say(narration)
        scroll(scrolls)
        back()
    }

    private func back() {
        let bar = app.navigationBars.firstMatch
        let back = bar.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        pause(1)
    }

    /// Slow scrolls a camera can follow.
    private func scroll(_ times: Int) {
        let window = app.windows.firstMatch
        for _ in 0..<times {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 350, thenHoldForDuration: 0.2)
            pause(1.2)
        }
    }

    private func scrollToTop() {
        app.statusBars.firstMatch.exists ? app.statusBars.firstMatch.tap() : app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        pause(1)
    }

    private func swipeDownSheet() {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        pause(1.5)
    }

    private func closeShareSheet() {
        if let label = ["Close", "Cancel"].first(where: { app.buttons[$0].exists }) {
            app.buttons[label].tap()
        } else {
            swipeDownSheet()
        }
        pause(2)
    }
}

/// The narrator's voice, different from HERB's so viewers can tell them apart. When demo/run-demo.sh is running, the
/// Mac speaks the narration with its best installed voice (the simulator only has basic voices): each line is
/// dropped into a shared folder and the script answers when it has finished speaking. Otherwise the simulator speaks.
@MainActor
final class Narrator {
    private let folder = URL(fileURLWithPath: "/tmp/logsperity-narration")
    private var useMac: Bool
    private var count = 0
    private let synth = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice? = {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        for name in ["Aaron", "Daniel", "Arthur", "Fred"] {
            if let v = all.filter({ $0.name.hasPrefix(name) }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) { return v }
        }
        return AVSpeechSynthesisVoice(language: "en-GB")
    }()

    init() {
        useMac = FileManager.default.fileExists(atPath: folder.appendingPathComponent("listening").path)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        print("Narrator voice: \(useMac ? "Mac voice" : voice?.name ?? "default")")
    }

    func speak(_ text: String) {
        if useMac {
            count += 1
            let name = String(format: "%04d", count)
            let tmp = folder.appendingPathComponent("\(name).tmp")
            let done = folder.appendingPathComponent("\(name).done")
            if (try? text.write(to: tmp, atomically: true, encoding: .utf8)) != nil,
               (try? FileManager.default.moveItem(at: tmp, to: folder.appendingPathComponent("\(name).txt"))) != nil {
                let start = Date()
                while !FileManager.default.fileExists(atPath: done.path) && Date().timeIntervalSince(start) < 60 {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
                if FileManager.default.fileExists(atPath: done.path) {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                    return
                }
            }
            useMac = false  // the Mac stopped answering: speak in the simulator from here on
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.postUtteranceDelay = 0.4
        synth.speak(u)
        let start = Date()
        while !synth.isSpeaking && Date().timeIntervalSince(start) < 2 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        while synth.isSpeaking { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
}
