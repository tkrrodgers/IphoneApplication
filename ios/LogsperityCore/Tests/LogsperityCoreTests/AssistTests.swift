import Testing
@testable import LogsperityCore

// Pilot feedback, Nov 2026: list changes, PARC order, hints, filling in from a known source, recurring charges.

@Suite struct PilotFeedbackListTests {
    @Test func pillarsAreInPARCOrder() {
        #expect(Pillar.allCases.map(\.name) == ["Prospecting", "Advertising", "Relationships", "Clients"])
    }

    @Test func networkingIsOneName() {
        #expect(Taxonomy.categoryByID["cat.networking"]?.name == "Networking")
        #expect(Taxonomy.activityByID["act.networking.prospecting"]?.name == "Networking")
        #expect(Taxonomy.activityByID["act.networking.relationships"]?.pillar == .relationships)
        #expect(!Taxonomy.activities.contains { $0.name.hasPrefix("Networking-") })
        #expect(!Taxonomy.mileageReasons.contains { $0.hasPrefix("Networking-") })
    }

    @Test func socialMediaReplacesFacebookAndTwitter() {
        let names = Set(Taxonomy.activities.map(\.name))
        #expect(!names.contains("Facebook Marketing") && !names.contains("Twitter Marketing") && !names.contains("Lead Generation"))
        for n in ["Social Media Content Creation", "Social Media Interaction", "Livestreaming"] { #expect(names.contains(n)) }
        #expect(Taxonomy.activityByID["act.lead_generation"]?.name == "Lead Generation")  // old entries still resolve
    }

    @Test func planOfActionList() {
        for p in ["Text", "Video Message", "Social Media Message"] { #expect(Taxonomy.planOfAction.contains(p)) }
        #expect(!Taxonomy.planOfAction.contains { $0.contains("Campaign") })
    }

    @Test func savedLogsMoveToRenamedItems() {
        var b = LogBook()
        var p = ProspectRecord(date: Day(2026, 3, 1))
        p.attribution = Attribution(pillar: .prospecting, categoryID: "cat.network_open_group", activityID: "act.networking_open_group")
        b.prospects = [p]
        var a = ActivityRecord(date: Day(2026, 3, 2))
        a.attribution = Attribution(pillar: .clients, activityID: "act.facebook_marketing")
        b.activities = [a]
        var t = TripRecord(date: Day(2026, 3, 3))
        t.reason = "Networking-Closed Group"
        b.trips = [t]
        let m = b.migratingTaxonomy()
        #expect(m.prospects[0].attribution.categoryID == "cat.networking")
        #expect(m.prospects[0].attribution.activityID == "act.networking.prospecting")
        #expect(m.activities[0].attribution.activityID == "act.social_media_interaction.clients")
        #expect(m.trips[0].reason == "Networking")
    }

    @Test func quarterHours() {
        #expect(Format.quarterHours(1.25) == "1.25 h")
        #expect(Format.quarterHours(0.75) == "0.75 h")
        #expect(Format.quarterHours(1.5) == "1.5 h")
        #expect(Format.quarterHours(2) == "2 h")
        #expect(Format.quarterHours(374.25) == "374.25 h")
    }

    @Test func strengthColors() {  // red, orange, yellow, blue, black
        #expect(Strength.allCases.map(\.colorHex) == ["#D32F2F", "#EF7D1A", "#E2B714", "#2F6DB5", "#1C1C1E"])
    }

    @Test func vendorWordsCapitalized() {
        #expect(LogRules.capitalizedWords("cedar grill") == "Cedar Grill")
        #expect(LogRules.capitalizedWords("mcDonald's drive thru") == "McDonald's Drive Thru")
    }
}

@Suite struct HintTests {
    @Test func aPartialProspectWaitsInTheReviewQueue() {
        var p = ProspectRecord(date: Day(2026, 11, 2))
        p.firstNames = "Ana"
        p.notes = "Referred by the Beckers"
        LogRules.markHint(&p)
        #expect(!p.reviewed)
        #expect(p.notes == "Referred by the Beckers HERB: still need the last name, the pillar, the category, the source and the activity.")
        var b = LogBook()
        b.prospects = [p]
        let item = Coach(b, now: Day(2026, 11, 2)).reviewItems().first
        #expect(item?.title == "Hint: Ana")
        #expect(item?.question == "Finish Ana — add the last name, the pillar, the category, the source and the activity?")
    }

    @Test func finishingAHintClearsIt() {
        var p = ProspectRecord(date: Day(2026, 11, 2))
        p.notes = "Call back HERB: still need the last name."
        p.reviewed = false
        p.firstNames = "Ana"; p.lastName = "Ruiz"
        p.attribution = Attribution(pillar: .clients, categoryID: "cat.past_client", activityID: "act.past_client_interaction", sourceID: "s1")
        LogRules.markHint(&p)
        #expect(p.reviewed)
        #expect(p.notes == "Call back")
    }

    @Test func expenseAndTripHints() {
        var e = ExpenseRecord(date: Day(2026, 11, 2))
        e.vendor = "Cedar Grill"
        LogRules.markHint(&e)
        #expect(LogRules.missing(e) == ["the amount", "the category"])
        var t = TripRecord(date: Day(2026, 11, 2))
        t.destination = "Title company"
        t.gpsMiles = 14
        LogRules.markHint(&t)
        var b = LogBook()
        b.expenses = [e]
        b.trips = [t]
        let qs = Coach(b, now: Day(2026, 11, 2)).reviewItems().map(\.question)
        #expect(qs.contains("Finish this trip — add the reason?"))
        #expect(qs.contains("Finish this expense — add the amount and the category?"))
    }
}

@Suite struct AssistTests {
    @Test func knownSourceFillsInPillarCategoryAndActivity() {
        let dana = SAMPLE.sources.first { $0.name == "Dana Ruiz" }!
        let a = SAMPLE.usualAttribution(forSource: dana.id)
        #expect(a?.pillar == .relationships)
        #expect(a?.categoryID == "cat.realtor")
        #expect(a?.activityID == "act.relationship_building_professional")
        #expect(a?.subPillar == .professional)
    }

    @Test func recurringChargesAskEachMonth() {
        var b = LogBook()
        var adobe = ExpenseRecord(date: Day(2026, 10, 3))
        adobe.vendor = "Adobe"; adobe.amount = 54.99; adobe.categoryID = "exp.technology.software"; adobe.recurring = true
        var gym = adobe
        gym.id = "g"; gym.vendor = "CRM"; gym.amount = 59
        var paidAlready = gym.renewed(on: Day(2026, 11, 1))
        paidAlready.recurring = true
        var oneOff = adobe
        oneOff.id = "o"; oneOff.vendor = "Printer"; oneOff.recurring = nil
        b.expenses = [adobe, gym, paidAlready, oneOff]
        let due = b.recurringDue(now: Day(2026, 11, 2))
        #expect(due.map(\.vendor) == ["Adobe"])  // CRM is already logged for November
        let nov = due[0].renewed(on: Day(2026, 11, 2))
        #expect(nov.id != adobe.id && nov.amount == 54.99 && nov.recurring == true && nov.date == Day(2026, 11, 2))
    }
}
