import Testing
@testable import LogsperityCore

// Ports of herb-sim's CoachingTests and the "every report builds" API test, run on the sample year.

let SAMPLE_NOW = Day(2026, 10, 30)
let SAMPLE = SampleYear.build(now: SAMPLE_NOW)

@Suite struct SampleYearTests {
    @Test func isDeterministic() {
        let again = SampleYear.build(now: SAMPLE_NOW)
        #expect(again.prospects.count == SAMPLE.prospects.count)
        #expect(again.closings.map(\.income) == SAMPLE.closings.map(\.income))
    }

    @Test func shapeOfTheYear() throws {
        let led = try Ledger(SAMPLE, periodKey: "ytd", now: SAMPLE_NOW)
        #expect((150...200).contains(led.prospectCount))
        #expect((25...40).contains(led.closingCount))
        #expect(led.incomeTotal > 100_000)
        #expect(led.index != nil)
        // R5 holds in generated data too
        let ids = SAMPLE.closings.compactMap(\.prospectID)
        #expect(Set(ids).count == ids.count)
        // nothing is dated today or later except auto-captured items under review
        #expect(SAMPLE.closings.allSatisfy { $0.date < SAMPLE_NOW })
    }
}

@Suite struct CoachingTests {
    let coach = Coach(SAMPLE, now: SAMPLE_NOW)

    @Test func storyRulesFire() {
        let keys = coach.insights().map(\.key)
        #expect(keys.contains("zombie.LeadBoost"))
        #expect(keys.contains("conv.activity.act.door_knocking"))
        #expect(keys.contains("timesink.act.open_houses"))
        #expect(keys.contains { $0.hasPrefix("drift.") }, "\(keys)")
    }

    @Test func insightsAreRankedConcernFirst() {
        let levels = coach.insights().map(\.level)
        #expect(levels == levels.sorted())
    }

    @Test func dismissedInsightsAreHidden() {
        let c = Coach(SAMPLE, now: SAMPLE_NOW, dismissed: ["zombie.LeadBoost"])
        #expect(!c.insights().map(\.key).contains("zombie.LeadBoost"))
    }

    @Test func reviewQueueHasAutoItems() {
        let items = coach.reviewItems()
        #expect(items.count >= 8)
        #expect(Set(items.map(\.log)).isSuperset(of: [.trips, .expenses, .activities, .prospects]))
    }

    @Test func focusHasThreeItems() {
        let f = coach.focus()
        #expect(f.items.count == 3)
        #expect(f.say.hasPrefix("Three things this week"))
        #expect(f.drop != nil)
    }

    @Test func followUpsIncludeStoryProspects() {
        let names = coach.followUps().map(\.name)
        #expect(names.contains("Priya Shah"))
        #expect(names.contains("Kevin Morales"))
        #expect(coach.followUps().contains { $0.kind == .partner && $0.name == "Jared Cole" })
    }

    @Test func kpis() {
        #expect(coach.kpis().map(\.key) == ["income", "closings", "prospects", "index"])
    }

    @Test func parkedProspectQuestion() {
        #expect(Coach.parkedMissing("HERB: still need the source.") == "the source")
        #expect(Coach.parkedMissing("no marker") == nil)
    }
}

@Suite struct ReportTests {
    let reports = Reports(SAMPLE, now: SAMPLE_NOW)

    @Test func everyReportBuilds() throws {
        for group in Reports.menu {
            for item in group.items {
                let r = try reports.build(item.key)
                #expect(!r.widgets.isEmpty, "\(item.key)")
                #expect(r.title == item.title || group.id == "monthly", "\(item.key)")
            }
        }
    }

    @Test func everyReportBuildsOnAnEmptyBook() throws {
        let empty = Reports(LogBook(), now: SAMPLE_NOW)
        for group in Reports.menu { for item in group.items { _ = try empty.build(item.key) } }
    }

    @Test func monthlyReportUsesThatMonth() throws {
        let r = try reports.build("month_03")
        #expect(r.period.from == Day(2026, 3, 1) && r.period.to == Day(2026, 3, 31))
        let future = try reports.build("month_12")
        if case .text(let p, _) = future.widgets[0].content { #expect(p == ["This month hasn't started yet."]) }
        else { Issue.record("expected a text widget") }
    }

    @Test func unknownReport() {
        #expect(throws: ReportError.unknownReport("nope")) { try reports.build("nope") }
    }

    @Test func annualStreamlinedHasSixPages() {
        #expect(reports.annualPages(year: 2026, version: "streamlined").pages.count == 6)
        #expect(reports.annualPages(year: 2026).pages.count == 15)
    }

    @Test func pnlLinesAddUpToTotalExpenses() throws {
        let led = try Ledger(SAMPLE, periodKey: "ytd", now: SAMPLE_NOW)
        let irs = Reports.irsTotals(led)
        #expect(abs(irs.values.reduce(0, +) - led.expensesTotal) < 0.01)  // issue I2: nothing left out
    }
}
