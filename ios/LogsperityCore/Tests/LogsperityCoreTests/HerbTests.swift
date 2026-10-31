import Foundation
import Testing
@testable import LogsperityCore

// Ports of herb-sim/tests/test_herb.py (ParserTests, IntentTests) and test_dialog.py (follow-up questions,
// design §17.2), run on the sample year. NOW is a Friday; "next week" is Monday Nov 2.

extension HerbSettings {
    /// The sample account: Marcus Reed in Denton, TX, Balanced questions.
    static let sample = HerbSettings(questionStyle: .balanced, ownerFirstName: "Marcus", homeState: "TX")
}

/// Drives one conversation the way the app does: the state from each reply goes back with the next, and the
/// changes and learned settings are applied before the next turn.
struct Convo {
    var book: LogBook
    var settings: HerbSettings
    var state: HerbDialogState?
    var activeTrip: HerbActiveTrip?
    var last: HerbReply?

    init(book: LogBook = SAMPLE, settings: HerbSettings = .sample) {
        self.book = book
        self.settings = settings
    }

    /// A new conversation on the same book and settings (the simulator's shared database).
    init(after c: Convo) { self.init(book: c.book, settings: c.settings) }

    @discardableResult
    mutating func say(_ text: String) -> HerbReply {
        let r = Herb(book: book, now: SAMPLE_NOW, settings: settings, activeTrip: activeTrip).respond(to: text, state: state)
        state = r.state
        book = book.applying(r.changes)
        if let s = r.settings { settings = s }
        switch r.trip {
        case .start(let dest): activeTrip = HerbActiveTrip(destination: dest, minutes: 20)
        case .end: activeTrip = nil
        case nil: break
        }
        last = r
        return r
    }

    var pending: HerbPending? { last?.pending }
    var data: HerbFields { last?.draft?.data ?? [:] }
    var say: String { last?.say ?? "" }
    func prospect(_ lastName: String = "Rodgers") -> ProspectRecord? { book.prospects.last { $0.lastName == lastName } }
}

func ask(_ text: String) -> HerbReply {
    Herb(book: SAMPLE, now: SAMPLE_NOW, settings: .sample).respond(to: text, state: nil)
}

// MARK: test_herb.py

@Suite struct HerbParserTests {
    @Test func amounts() {
        #expect(HerbParse.amounts("about 520 thousand")[0].value == 520_000)
        #expect(HerbParse.amounts("$86.40 at Cedar Grill")[0].value == 86.4)
        #expect(HerbParse.amounts("a 2k bonus")[0].value == 2000)
        #expect(HerbParse.amounts("I made 6,500")[0].value == 6500)
        #expect(HerbParse.amounts("talk Thursday after 5").isEmpty)
        #expect(HerbParse.amounts("drove 14 miles").isEmpty)
    }

    @Test func durations() {
        #expect(HerbParse.durationMinutes("two hours of door knocking") == 120)
        #expect(HerbParse.durationMinutes("forty five minutes") == 45)
        #expect(HerbParse.durationMinutes("an hour and a half") == 90)
        #expect(HerbParse.durationMinutes("90 minutes") == 90)
        #expect(HerbParse.durationMinutes("lunch with Dana") == nil)
    }

    @Test func phoneAndWake() {
        #expect(HerbParse.phone("call 940-555-0137 today")?.0 == "(940) 555-0137")
        #expect(HerbParse.stripWake("Hi Herb, what's up") == "what's up")
        #expect(HerbParse.stripWake("Hey Siri, ask Herb who I need to call") == "who I need to call")
    }

    @Test func when() {
        #expect(HerbParse.parseWhen("Thursday after five", now: SAMPLE_NOW) == Day(2026, 11, 5))
        #expect(HerbParse.parseWhen("tomorrow", now: SAMPLE_NOW) == Day(2026, 10, 31))
        #expect(HerbParse.parseWhen("in 3 days", now: SAMPLE_NOW) == Day(2026, 11, 2))
        #expect(HerbParse.parseTime("Thursday after 5") == "5:00 PM")
    }

    @Test func similarityMatchesDifflib() {
        #expect(similarity("abcd", "bcde") == 0.75)
        #expect(similarity("alvarez", "alvares") > 0.85)
        #expect(similarity("leads", "leadboost") < 0.88)
    }
}

@Suite struct HerbIntentTests {
    @Test func recordLeadDesignExample() {
        let r = ask("Kevin Morales, 940-555-0137, Ruth Alvarez at Cedar and Main sent him, move-up buyer about 520, Thursday after five")
        #expect(r.intent == .logProspect)
        let d = r.draft!.data
        #expect(d["firstNames"] == "Kevin" && d["lastName"] == "Morales")
        #expect(d["phone1"] == "(940) 555-0137")
        #expect(d["source"] == "Ruth Alvarez")
        #expect(d["categoryId"] == "cat.realtor")
        #expect(d.str("notes")?.contains("520,000") == true, "\(d)")
        #expect(d["followUp"] == "2026-11-05")
    }

    @Test func newLeadOpenHouse() {
        let d = ask("New lead from Saturday's open house, Nora Diaz, she's just looking").draft!.data
        #expect(d["categoryId"] == "cat.open_house")
        #expect(d.str("source")?.hasPrefix("Open house") == true, "\(d)")
        #expect(d["strength"] == "cold")
    }

    @Test func pastClientReferralGoesToClients() {  // rule R2
        let d = ask("New prospect Owen Park, Greg Wallace referred him").draft!.data
        #expect(d["pillar"] == "clients")
        #expect(d["categoryId"] == "cat.past_client")
    }

    @Test func leadsToRecordPrompts() {
        let r = ask("Hi Herb, I have some leads to record.")
        #expect(r.intent == .logProspect)
        #expect(r.draft == nil)
        #expect(r.followUp)
    }

    @Test func closing() {
        let r = ask("The Morales loan closed, 520 thousand, I made 6,500")
        #expect(r.intent == .logClosing)
        let d = r.draft!.data
        #expect(d["transactionSize"] == 520_000)
        #expect(d["income"] == 6500)
        #expect(d["prospectId"] != nil)
    }

    @Test func expenseMealWithPartner() {
        let r = ask("Log a $42 lunch with Jared")
        let d = r.draft!.data
        #expect(r.intent == .logExpense)
        #expect(d["amount"] == 42)
        #expect(d["categoryId"] == "exp.relationships.meal")
        #expect(d["withWhom"] == "Jared Cole")
    }

    @Test func expenseVendor() {
        var d = ask("Lunch with Dana, 86 dollars at Cedar Grill").draft!.data
        #expect(d["vendor"] == "Cedar Grill" && d["amount"] == 86)
        d = ask("Bought printer paper at Office Depot for $43.17").draft!.data
        #expect(d["categoryId"] == "exp.general.office_supplies")
        #expect(d["amount"] == 43.17)
    }

    @Test func scanReceipt() {
        #expect(ask("Scan a receipt").actions[0].kind == .open(.receiptScanner))
        #expect(HerbTarget.receiptScanner.key == "expense:scan")
    }

    @Test func activity() {
        let r = ask("I spent two hours door knocking and got three leads")
        let d = r.draft!.data
        #expect(r.intent == .logActivity && d["activityId"] == "act.door_knocking" && d["minutes"] == 120)
        #expect(ask("an hour and a half at the open house").draft!.data["minutes"] == 90)
    }

    @Test func income() {
        let d = ask("Got a 2,000 referral fee from Lakeside Realty").draft!.data
        #expect(d["amount"] == 2000 && d["type"] == "referral_fees" && d["payer"] == "Lakeside Realty")
    }

    @Test func trip() {
        #expect(ask("I drove to the title company, 14 miles").draft!.data["gpsMiles"] == 14)
        var c = Convo()
        let r = c.say("Start a business trip to Lakeside Realty")
        #expect(r.intent == .logTrip)
        #expect(r.trip == .start(destination: "Lakeside Realty"))
        let end = c.say("End trip")
        #expect(end.draft?.log == .trips)
        #expect((end.draft?.data.num("gpsMiles") ?? 0) > 0)
        #expect(end.draft?.data["destination"] == "Lakeside Realty")
        #expect(ask("End trip").say.hasPrefix("There's no trip running"))
    }

    @Test func focus() {
        let r = ask("What should I focus on this week to make more money?")
        #expect(r.intent == .focus)
        #expect(r.cards.filter { $0.chip == "focus" }.count == 3)
        #expect(r.say.contains("Three things this week"))
    }

    @Test func followUpsViaSiri() {
        let r = ask("Hey Siri, ask Herb who I need to follow up with")
        #expect(r.intent == .followUps)
        #expect((r.say + " " + r.cards.map(\.title).joined(separator: " ")).contains("Priya Shah"))
    }

    @Test(arguments: [
        ("Am I on track?", HerbIntent.pace), ("Which sources never close?", .sourcesNoClose),
        ("What's my Logsperity Index?", .index), ("Where am I wasting time?", .efficiency),
        ("Which pillar has the best return?", .roi), ("Which pillar converts best?", .conversion),
        ("Which agencies generated the most income for me this year, not just leads?", .topSources),
        ("What does Herb need from me?", .review), ("How many miles have I driven?", .mileageSummary),
        ("What can you do?", .help), ("What's my business plan?", .plan),
    ])
    func queries(_ text: String, _ intent: HerbIntent) {
        let r = ask(text)
        #expect(r.intent == intent)
        #expect(!r.say.isEmpty)
        #expect(!r.say.hasPrefix("Sorry, I hit a snag"), "\(r.say)")
    }

    @Test func sourcesNeverCloseNamesLeadBoost() {
        #expect(ask("Which sources never close?").say.contains("LeadBoost"))
    }

    @Test func report() {
        let r = ask("Email me the March report")
        #expect(r.actions.map(\.kind) == [.open(.report("month_03")), .open(.emailReport("month_03"))])
        #expect(r.actions.compactMap { if case .open(let t) = $0.kind { t.key } else { nil } } == ["report:month_03", "email:month_03"])
        #expect(r.say.hasPrefix("Here's your March report."))
    }

    @Test func confirmSaves() throws {
        let r = ask("New lead, Hannah Brooks, 940-555-0199, Dana Ruiz sent her")
        #expect(r.changes.isEmpty)  // nothing saved without yes
        let out = try Herb(book: SAMPLE, now: SAMPLE_NOW, settings: .sample).confirm(r.draft!)
        let after = SAMPLE.applying(out.changes)
        #expect(after.prospects.count == SAMPLE.prospects.count + 1)
        let p = try #require(after.prospects.last)
        #expect(after.sourceName(p.attribution.sourceID) == "Dana Ruiz")
        #expect(after.sources.count == SAMPLE.sources.count)  // the existing source is reused
        #expect(p.followUp != nil && p.capture == .voice)
        #expect(out.say == "Saved. I'll remind you to follow up.")
    }

    @Test func greetings() {
        #expect(ask("").say == "Hi Marcus. What can I do for you?")
        #expect(ask("thanks").say == "Anytime.")
        let r = Herb(book: SAMPLE, now: SAMPLE_NOW, settings: .sample, hour: 15).respond(to: "Hi Herb, hello", state: nil)
        #expect(r.say.hasPrefix("Good afternoon, Marcus."))
    }
}

// MARK: test_dialog.py — prospects

@Suite struct HerbProspectFollowUps {
    @Test func completeEntryOnlyAsksForTheSource() throws {
        var c = Convo()
        var r = c.say("Hi Herb, new prospect Tom Rodgers, 216 Shadow Creek Lane, Hickory Creek Texas, 847-477-0619, Follow up next week")
        let d = c.data
        #expect(d["firstNames"] == "Tom" && d["lastName"] == "Rodgers" && d["phone1"] == "(847) 477-0619")
        #expect(d["address"] == "216 Shadow Creek Lane" && d["city"] == "Hickory Creek" && d["state"] == "TX")
        #expect(d["followUp"] == "2026-11-02")
        #expect(c.pending == HerbPending("value", slot: "source"))
        #expect(r.say.contains("Who referred Tom"))
        r = c.say("Ruth Alvarez sent him")
        #expect(c.pending?.type == "confirm")
        #expect(r.say.hasSuffix("Save it?"))
        #expect(r.changes.isEmpty)
        c.say("yes")
        let p = try #require(c.prospect())
        #expect(p.address == "216 Shadow Creek Lane" && p.city == "Hickory Creek" && p.state == "TX" && p.phone1 == "(847) 477-0619")
        #expect(p.attribution.categoryID == "cat.realtor")
        #expect(c.state == nil)
        #expect(c.say == "Saved Tom Rodgers. I'll remind you to follow up Monday, Nov 2.")
    }

    @Test func missingAddressIsOffered() {
        var c = Convo()
        let r = c.say("Hi Herb, New Prospect, Tom Rodgers, 847-477-0619, Follow up next week")
        #expect(r.say == "Got it — Tom Rodgers, mobile (847) 477-0619, follow-up Monday, Nov 2. Do you want to add an address?")
        #expect(c.pending?.slots == ["address"])
    }

    @Test func missingAddressAndPhoneOfferedTogether() {
        var c = Convo()
        let r = c.say("Hi Herb, new prospect Tom Rodgers, follow up next week")
        #expect(r.say.contains("Do you want to add an address and phone number?"))
        #expect(c.pending?.slots == ["address", "phone"])
        #expect(r.actions.map(\.label).prefix(4) == ["Yes", "No", "Address only", "Phone only"])
    }

    @Test func phoneNumberOnly() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, follow up next week")
        #expect(c.say("phone number only").say == "What's the phone number?")
        let r = c.say("847 477 0619")
        #expect(r.say.contains("(847) 477-0619"))
        #expect(c.pending?.slot == "source")  // address was declined: not offered again
    }

    @Test func yesAsksEachValueInTurn() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, follow up next week")
        #expect(c.say("yes").say == "What's the address?")
        let r = c.say("216 Shadow Creek Lane in Hickory Creek")
        #expect(r.say.contains("And the phone number?"))
        c.say("847-477-0619")
        #expect(c.data["city"] == "Hickory Creek")
        #expect(c.data["phone1"] == "(847) 477-0619")
    }

    @Test func givingThePhoneReoffersTheAddress() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, follow up next week")
        #expect(c.say("847-477-0619").say.contains("Do you want to add the address?"))
        c.say("No")
        #expect(c.pending?.slot == "source")
        c.say("216 Shadow Creek Lane")  // changing one's mind later still works
        #expect(c.data["address"] == "216 Shadow Creek Lane")
    }

    @Test func addressGivenDirectlyReoffersPhone() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, follow up next week")
        #expect(c.say("216 Shadow Creek Lane, Hickory Creek, Texas").say.contains("Do you want to add the phone number?"))
    }

    @Test func noAddressJustThePhone() {
        var c = Convo()
        c.say("new prospect Tom Rodgers")
        #expect(c.say("no address, just the phone").say == "What's the phone number?")
    }

    @Test func noDeclinesBoth() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, follow up next week")
        c.say("no")
        #expect(c.pending?.slot == "source")
    }

    @Test func spokenEmailInThoroughMode() {
        var c = Convo(settings: HerbSettings(questionStyle: .thorough, ownerFirstName: "Marcus", homeState: "TX"))
        let r = c.say("new prospect Tom Rodgers, 847-477-0619, 216 Shadow Creek Lane")
        #expect(r.say.replacingOccurrences(of: "an email", with: "the email").contains("Do you want to add the email address?"))
        c.say("yes")
        c.say("tom dot rodgers at gmail dot com")
        #expect(c.data["email1"] == "tom.rodgers@gmail.com")
    }

    @Test func newSourceAsksWhoItIs() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, 847-477-0619, follow up next week")
        c.say("no")
        #expect(c.say("Sam Lee").say.contains("Sam Lee is new to me"))
        c.say("he's a realtor")
        #expect(c.data["source"] == "Sam Lee" && c.data["categoryId"] == "cat.realtor")
        c.say("yes")
        let p = c.prospect()!
        #expect(c.book.sourceName(p.attribution.sourceID) == "Sam Lee")  // Sam is set up for next time
        #expect(c.book.sources.count == SAMPLE.sources.count + 1)
    }

    @Test func followUpDefaultAndChoice() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, 847-477-0619")
        c.say("no")
        c.say("Zillow")
        #expect(c.pending?.type == "default")
        #expect(c.say.contains("Monday"))
        c.say("in two weeks")
        #expect(c.data["followUp"] == "2026-11-13")
    }

    @Test func correctionAtConfirm() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, 847-477-0619, 216 Shadow Creek Lane, from Zillow, follow up Monday")
        #expect(c.pending?.type == "confirm")
        c.say("actually make it Tuesday")
        #expect(c.data["followUp"] == "2026-11-03")
        c.say("the phone is 940-555-0111")
        #expect(c.data["phone1"] == "(940) 555-0111")
        #expect(c.pending?.type == "confirm")
    }

    @Test func cancelSavesNothing() {
        var c = Convo()
        c.say("new prospect Tom Rodgers")
        let r = c.say("cancel")
        #expect(r.state == nil)
        #expect(r.changes.isEmpty)
        #expect(c.book.prospects.count == SAMPLE.prospects.count)
    }

    @Test func finishLaterParksItInReview() throws {
        var c = Convo()
        c.say("new prospect Tom Rodgers, follow up next week")
        let r = c.say("I'm driving")
        #expect(r.say.contains("Review queue"))
        #expect(r.say.contains("the address"))
        #expect(r.say.hasSuffix("Drive safe."))
        let p = try #require(c.prospect())
        #expect(!p.reviewed)
        #expect(p.notes?.contains("HERB: still need") == true)
        let item = try #require(Coach(c.book, now: SAMPLE_NOW).reviewItems().first { $0.recordID == p.id })
        #expect(item.question.hasPrefix("Finish Tom Rodgers"))
    }

    @Test func quickModeStillAsksTheSource() {  // D3: source is required in every mode
        var c = Convo(settings: HerbSettings(questionStyle: .quick, ownerFirstName: "Marcus", homeState: "TX"))
        c.say("new prospect Tom Rodgers")
        #expect(c.pending?.slot == "source")
        let r = c.say("from Zillow")
        #expect(c.pending?.type == "confirm", "\(r.say)")
    }

    @Test func unknownSourceGoesToReview() throws {
        var c = Convo()
        for answer in ["I don't know", "skip", "no", "Don't know", "nobody, he just called me"] {
            var n = Convo(after: c)
            n.say("new prospect Tom Rodgers, 847-477-0619")
            if n.pending?.type == "offer" { n.say("no") }  // after three "no"s HERB stops offering the address
            #expect(n.pending?.slot == "source", "\(answer)")
            let r = n.say(answer)
            #expect(r.say.contains("mark the source unknown"), "\(answer): \(r.say)")
            #expect(n.data["source"] == "Unknown")
            #expect(n.data["reviewed"] == false)
            c = n
        }
        c.say("yes")
        c.say("yes")
        let p = try #require(c.book.prospects.last)
        #expect(c.book.sourceName(p.attribution.sourceID) == "Unknown" && !p.reviewed)
        let item = try #require(Coach(c.book, now: SAMPLE_NOW).reviewItems().first { $0.recordID == p.id })
        #expect(item.question.hasPrefix("Where did Tom"), "\(item.question)")
        let keys = Coach(c.book, now: SAMPLE_NOW).insights().map(\.key)
        #expect(keys.contains("source.unknown"))
        #expect(!keys.contains("source.\(p.attribution.sourceID!)"))
        let say = Herb(book: c.book, now: SAMPLE_NOW, settings: c.settings).respond(to: "Which sources never close?", state: nil).say
        #expect(!say.contains("Unknown"))
    }

    @Test func knownSourceCanReplaceUnknown() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, 847-477-0619")
        c.say("no")
        c.say("I don't know")
        c.say("actually Ruth Alvarez sent him")
        #expect(c.data["source"] == "Ruth Alvarez")
        #expect(c.data["reviewed"] != false)
    }

    @Test func skippingThreeTimesStopsTheOffer() {
        var c = Convo()
        var last = ""
        for _ in 0..<3 {
            c = Convo(after: c)
            c.say("new prospect Tom Rodgers, 847-477-0619")
            #expect(c.pending?.slots == ["address"])
            last = c.say("no").say
        }
        #expect(last.contains("stop asking"))
        #expect(c.last?.settings?.neverAsk.contains("address") == true)
        c = Convo(after: c)
        c.say("new prospect Ann Lee, 847-477-0620")
        #expect(c.pending?.type != "offer")
        #expect(c.settings.neverAsk.contains("address"))
    }

    @Test func duplicateBecomesAnUpdate() {
        var c = Convo()
        #expect(c.say("new prospect Kevin Morales").say.contains("Is this the same person?"))
        c.say("same person")
        c.say("940-555-0199")
        c.say("yes")
        #expect(c.prospect("Morales")?.phone1 == "(940) 555-0199")
        #expect(c.book.prospects.filter { $0.lastName == "Morales" }.count == 1)
    }

    @Test func sideQuestionKeepsTheDraft() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, 847-477-0619")
        let r = c.say("which sources never close?")
        #expect(r.say.contains("LeadBoost"))
        #expect(r.say.contains("Back to Tom Rodgers"))
        #expect(c.pending?.slots == ["address"])
        #expect(r.state != nil && r.draft != nil)
    }

    @Test func newEntryWhileOneWaits() {
        var c = Convo()
        c.say("new prospect Tom Rodgers, 847-477-0619")
        #expect(c.say("new prospect Mary Jones").say.contains("save Tom Rodgers"))
        let r = c.say("yes")
        #expect(c.prospect() != nil)
        #expect(r.say.contains("Mary Jones"))
        #expect(c.state?.data["lastName"] == "Jones")
    }
}

// MARK: test_dialog.py — other logs

@Suite struct HerbOtherLogs {
    @Test func expenseMissingCategoryAndPeople() {
        var c = Convo()
        c.say("I spent 45 dollars")
        #expect(c.pending?.slot == "category")
        c.say("lunch")
        #expect(c.say.contains("Who was the lunch with?"))
        c.say("Dana Ruiz")
        #expect(c.say.contains("Which restaurant?"))
        let r = c.say("Cedar Grill")
        #expect(c.pending?.type == "confirm", "\(r.say)")
        #expect(c.data["vendor"] == "Cedar Grill" && c.data["categoryId"] == "exp.relationships.meal")
    }

    @Test func soloMealWarns() {
        var c = Convo()
        c.say("lunch, 18 dollars at Chipotle")
        #expect(c.say("just me").say.contains("aren't deductible"))
        #expect(c.data["categoryId"] == "exp.travel.meal")
    }

    @Test func activityLeadsChainIntoProspects() throws {
        var c = Convo()
        c.say("I spent two hours door knocking and got two leads")
        #expect(c.say("yes").say.contains("want to add them now"))
        #expect(c.book.activities.count == SAMPLE.activities.count + 1)
        #expect(c.say("yes").say == "Lead 1 of 2 — what's the name?")
        c.say("Maria Lopez 940-555-0101")
        #expect(c.data["categoryId"] == "cat.door_knocking")
        c.say("no")
        c.say("yes")
        #expect(c.say("yes").say.contains("Lead 2 of 2"))
        let r = c.say("that's all")
        #expect(r.state == nil)
        let p = try #require(c.prospect("Lopez"))
        #expect(c.book.sourceName(p.attribution.sourceID) == "Savannah neighborhood")
    }

    @Test func updateExistingContact() throws {
        var c = Convo()
        let r = c.say("I called Priya Shah, she's not ready yet, follow up in two weeks")
        #expect(r.intent == .updateProspect)
        c.say("yes")
        let p = try #require(c.prospect("Shah"))
        #expect(p.followUp == Day(2026, 11, 13))
        #expect(p.notes?.contains("Called — she's not ready yet") == true, "\(p.notes ?? "")")
        #expect(c.book.prospects.count == SAMPLE.prospects.count)
    }

    @Test(arguments: ["Kevin Morales's email is kevin@example.com", "Kevin Morales email is kevin@example.com",
                      "new phone for Kevin Morales 940-555-0123"])
    func updateContactDetails(_ text: String) {
        let r = ask(text)
        #expect(r.intent == .updateProspect)
        #expect(r.pending?.type == "confirm")
    }

    @Test func updateAsksForNextFollowUp() {
        #expect(ask("I called Priya Shah, left a voicemail").say.contains("When should you follow up with Priya next"))
    }

    @Test func incomeAsksTypeAndPayer() {
        var c = Convo()
        c.say("got paid 3,000")
        #expect(c.pending?.slot == "type")
        c.say("referral fee")
        #expect(c.pending?.slot == "payer")
        c.say("Lakeside Realty")
        #expect(c.data["type"] == "referral_fees" && c.data["payer"] == "Lakeside Realty")
    }

    @Test func tripAsksDestination() {
        var c = Convo()
        c.say("drove 12 miles")
        let r = c.say("to the title company")
        #expect(c.data["reason"] == "Title Company")
        #expect(r.say.contains("worth $9.12"))
    }

    @Test func closingEstimatesIncome() throws {
        var c = Convo()
        c.say("the Morales loan closed")
        #expect(c.pending?.slot == "size")
        let r = c.say("520 thousand")
        #expect(c.pending?.type == "default")
        #expect(r.say.contains("about $"))
        c.say("yes")
        #expect((c.data.num("income") ?? 0) > 5000)
        c.say("yes")  // save: the closing, its income row, and Kevin stays one prospect (R5)
        let cl = try #require(c.book.closings.last)
        #expect(cl.prospectID == c.prospect("Morales")?.id && cl.transactionSize == 520_000)
        #expect(c.book.income.contains { $0.closingID == cl.id && $0.amount == cl.income })
    }

    @Test func requiredFieldsCannotBeSkipped() {
        var c = Convo()
        c.say("I spent 45 dollars")
        let r = c.say("skip")
        #expect(c.pending?.slot == "category")
        #expect(r.say.contains("I need that one"))
    }
}

// MARK: Swift-specific: the state travels with each turn

@Suite struct HerbStateTests {
    @Test func stateSurvivesJSON() throws {
        var a = Convo(), b = Convo()
        a.say("new prospect Tom Rodgers, follow up next week")
        let json = try JSONEncoder().encode(a.state)
        b.state = try JSONDecoder().decode(HerbDialogState.self, from: json)
        #expect(a.say("yes").say == b.say("yes").say)
        #expect(a.state == b.state)
    }

    @Test func repeatClientClosingBecomesIncome() throws {
        var book = SAMPLE
        let closed = try #require(book.prospects.first { p in book.closings.contains { $0.prospectID == p.id } && p.lastName != "" })
        book.prospects = book.prospects.filter { $0.lastName != closed.lastName || $0.id == closed.id }
        var c = Convo(book: book)
        c.say("\(closed.fullName) closed again, 400 thousand, I made 5,000")
        #expect(c.last?.draft?.log == .income, "\(c.say)")
        #expect(c.say.contains("already has a closing"))
        c.say("yes")
        #expect(c.book.closings.count == book.closings.count)  // R5: still one closing
        #expect(c.book.income.last?.notes == "Repeat transaction (rule R4)")
    }
}
