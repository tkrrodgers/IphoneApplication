import Testing
@testable import LogsperityCore

// Swift port of herb-sim/tests/test_calc.py: same fixture, same expected numbers.

let NOW = Day(2026, 4, 15)

func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tol
}

/// Tiny hand-checkable ledger for March 2026.
func fixture() -> LogBook {
    var b = LogBook()
    b.plans[2026] = PlanInputs(grossIncomeGoal: 150_000, netProfitGoal: 125_000, avgCommission: 6_500,
                               avgTransactionSize: 335_000, hoursPerWeek: 40, vacationWeeks: 0)
    let greg = SourceRecord(name: "Greg Wallace")
    b.sources = [greg]
    let pastClient = Attribution(pillar: .clients, subPillar: .clients, categoryID: "cat.past_client",
                                 activityID: "act.past_client_interaction", sourceID: greg.id)
    var p1 = ProspectRecord(date: Day(2026, 3, 2))
    p1.firstNames = "A"; p1.lastName = "One"; p1.attribution = pastClient; p1.strength = .hot
    var p2 = ProspectRecord(date: Day(2026, 3, 5))
    p2.firstNames = "B"; p2.lastName = "Two"; p2.attribution = pastClient; p2.strength = .medium
    b.prospects = [p1, p2]
    for i in 0..<2 {
        var p = ProspectRecord(date: Day(2026, 3, 10))
        p.firstNames = "C"; p.lastName = "Door\(i)"; p.strength = .cold
        p.attribution = Attribution(pillar: .prospecting, subPillar: .prospecting, categoryID: "cat.door_knocking",
                                    activityID: "act.door_knocking")
        b.prospects.append(p)
    }
    let c = LogRules.closing(from: p1, date: Day(2026, 3, 20), transactionSize: 400_000, income: 5_000)
    b.closings = [c]
    var inc = LogRules.incomeRows(for: c, lastName: "One", addToIncome: true)[0]
    inc.attribution.activityID = nil
    inc.attribution.sourceID = nil
    b.income = [inc]
    var consulting = IncomeRecord(date: Day(2026, 3, 25))
    consulting.mode = .type; consulting.type = .consultingFees; consulting.amount = 1_000
    b.income.append(consulting)
    var gift = ExpenseRecord(date: Day(2026, 3, 3))
    gift.vendor = "Gift"; gift.amount = 100; gift.group = .clients; gift.categoryID = "exp.clients.thank_you_gifts"
    var phone = ExpenseRecord(date: Day(2026, 3, 4))
    phone.vendor = "Phone"; phone.amount = 50; phone.group = .general; phone.categoryID = "exp.general.phone"
    b.expenses = [gift, phone]
    var t1 = TripRecord(date: Day(2026, 3, 6))
    t1.reason = "x"; t1.destination = "y"; t1.odometerStart = 1000; t1.odometerEnd = 1010
    var t2 = TripRecord(date: Day(2026, 3, 7))
    t2.reason = "x"; t2.destination = "y"; t2.gpsMiles = 99; t2.isBusiness = false
    b.trips = [t1, t2]
    var a1 = ActivityRecord(date: Day(2026, 3, 2))
    a1.attribution = Attribution(pillar: .clients, subPillar: .clients, activityID: "act.past_client_interaction")
    a1.minutes = 120
    var a2 = ActivityRecord(date: Day(2026, 3, 10))
    a2.attribution = Attribution(pillar: .prospecting, subPillar: .prospecting, activityID: "act.door_knocking")
    a2.minutes = 60
    b.activities = [a1, a2]
    return b
}

@Suite struct PlanTests {
    @Test func example2018BusinessPlan() {
        let o = PlanInputs.default.outputs
        #expect(approx(o.annualTransactions, 23.08, 0.005))
        #expect(approx(o.monthlyTransactions, 1.92, 0.005))
        #expect(approx(o.hourlyGross, 72.12, 0.005))
        #expect(approx(o.hourlyNet, 60.10, 0.005))
        #expect(approx(o.annualVolume, 7_730_769.23, 0.05))
        #expect(approx(o.yieldPct, 0.0194, 0.00005))
        #expect(o.annualWorkHours == 2080)
        #expect(o.annualExpenses == 25_000)
    }

    @Test func vacationReducesWorkHours() {
        let o = PlanInputs(grossIncomeGoal: 180_000, netProfitGoal: 150_000, avgCommission: 5_500,
                           avgTransactionSize: 380_000, hoursPerWeek: 45, vacationWeeks: 3).outputs
        #expect(o.annualWorkHours == 49 * 45)
    }

    @Test func netCannotExceedGross() {
        var p = PlanInputs.default
        p.grossIncomeGoal = 100
        p.netProfitGoal = 200
        #expect(throws: PlanError.netExceedsGross) { try p.validate() }
    }
}

@Suite struct IndexTests {
    @Test func sample2018() { #expect(approx(logsperityIndex(netROI: 2.386, margin: 0.8193, conversion: 0.40), 120.5, 0.05)) }
    @Test func healthyIs100() { #expect(approx(logsperityIndex(netROI: 2.0, margin: 0.75, conversion: 0.30), 100)) }
    @Test func missingInput() { #expect(logsperityIndex(netROI: nil, margin: 0.5, conversion: 0.3) == nil) }
}

@Suite struct PeriodTests {
    @Test func quarter() throws {
        let p = try Period.parse("q:2026-3", now: NOW)
        #expect(p.from == Day(2026, 7, 1) && p.to == Day(2026, 9, 30))
    }

    @Test func ytdAndMonth() throws {
        #expect(try Period.parse("ytd", now: NOW).from == Day(2026, 1, 1))
        #expect(try Period.parse("month:2026-02", now: NOW).to == Day(2026, 2, 28))
    }

    @Test func badPeriod() {
        #expect(throws: PeriodError.self) { try Period.parse("fortnight", now: NOW) }
    }

    @Test func previousAndLastYear() throws {
        let m = try Period.parse("month:2026-03", now: NOW)
        #expect(m.previous.from == Day(2026, 2, 1) && m.previous.to == Day(2026, 2, 28))
        let leap = try Period.parse("custom:2024-02-29:2024-03-10", now: NOW).sameLastYear
        #expect(leap.from == Day(2023, 2, 28))
    }
}

@Suite struct DayTests {
    @Test func ordinalRoundTrip() {
        for d in [Day(1970, 1, 1), Day(2000, 2, 29), Day(2026, 12, 31), Day(1969, 12, 31)] {
            #expect(Day(ordinal: d.ordinal) == d)
        }
        #expect(Day(1970, 1, 1).ordinal == 0)
        #expect(Day(2026, 3, 1).days(to: Day(2026, 4, 1)) == 31)
    }

    @Test func weekday() {
        #expect(Day(2026, 11, 2).weekday == 0)  // Monday
        #expect(Day(2026, 10, 31).weekday == 5)  // Saturday
        #expect(LogRules.nextBusinessDay(after: Day(2026, 10, 30)) == Day(2026, 11, 2))
    }

    @Test func parsing() {
        #expect(Day(iso: "2026-02-29") == nil)
        #expect(Day(iso: "2024-02-29") == Day(2024, 2, 29))
        #expect(Day(iso: "nope") == nil)
    }
}

@Suite struct LedgerTests {
    let led = Ledger(fixture(), period: try! Period.parse("month:2026-03", now: NOW), now: NOW)

    @Test func countsAndConversion() {
        #expect(led.prospectCount == 4)
        #expect(led.closingCount == 1)
        #expect(approx(led.conversion, 0.25))
        #expect(led.volume == 400_000)
    }

    @Test func incomeAndExpenses() {
        #expect(led.incomeTotal == 6_000)
        #expect(led.nonTransactionIncome == 1_000)
        #expect(approx(led.mileageDeduction, 10 * 0.725))  // personal trip excluded
        #expect(approx(led.expensesTotal, 150 + 7.25))
        #expect(approx(led.profit, 6_000 - 157.25))
    }

    @Test func efficiency() {
        #expect(approx(led.bbHours, 3))
        #expect(approx(led.hoursPerProspect, 0.75))
        #expect(approx(led.hoursPerClosing, 3))
        #expect(approx(led.workHours, 2080 * 31 / 365))
        #expect(approx(led.hourlyGross, 6_000 / (2080 * 31 / 365)))
    }

    @Test func pillarBreakdownAndROI() {
        let pil = Dictionary(uniqueKeysWithValues: led.breakdown(.pillar).map { ($0.key!, $0) })
        #expect(pil.count == 4)
        #expect(approx(pil["clients"]!.conversion, 0.5))
        #expect(pil["prospecting"]!.closings == 0)
        #expect(pil["clients"]!.expenses == 100)
        let roi = Dictionary(uniqueKeysWithValues: led.pillarROI().map { ($0.key, $0) })
        #expect(approx(roi["clients"]!.roi, (5_000 - 100) / 100))
        let wages = 2 * led.hourlyGross!
        #expect(approx(roi["clients"]!.roiWithTime, (5_000 - 100 - wages) / (100 + wages)))
        // overhead holds the phone bill, mileage and unattributed consulting income
        #expect(approx(roi["overhead"]!.expenses, 50 + 7.25))
        #expect(approx(roi["overhead"]!.income, 1_000))
        #expect(approx(roi["total"]!.roiWithTime, led.netROI!))
        #expect(roi["clients"]!.label == "Best" && roi["prospecting"]!.label == "Worst")
    }

    @Test func netROIAndIndex() {
        let capital = led.expensesTotal + led.bbHours * led.hourlyGross!
        #expect(approx(led.netROI, (6_000 - capital) / capital))
        #expect(approx(led.index, logsperityIndex(netROI: led.netROI, margin: led.margin, conversion: 0.25)!))
    }

    @Test func splitMileageRate() {
        #expect(Taxonomy.mileageRate(on: Day(2026, 6, 30)) == 0.725)
        #expect(Taxonomy.mileageRate(on: Day(2026, 7, 1)) == 0.76)
    }

    @Test func scorecard() throws {
        let sc = try Scorecard(fixture(), log: .prospects, measure: .quantity, dimension: .category,
                               periodKey: "month:2026-03", now: NOW)
        let totals = Dictionary(uniqueKeysWithValues: sc.rows.map { ($0.key, $0.total) })
        #expect(totals["cat.door_knocking"] == 2)
        #expect(sc.subPillarTotals[.clients] == 2)
    }

    @Test func monthsInUse() throws {
        let ytd = try Ledger(fixture(), periodKey: "ytd", now: NOW)
        #expect(ytd.monthsInUse == 2)  // March and April (data starts in March)
    }

    @Test func breakdownSortsByProspects() {
        // both have 2 prospects; the one with a closing ranks first
        let cats = led.breakdown(.category)
        #expect(cats.map(\.key) == ["cat.past_client", "cat.door_knocking"])
        let sources = led.breakdown(.source)
        #expect(sources.last!.key == nil && sources.last!.name == "Unknown")
    }
}

@Suite struct RuleTests {
    @Test func r5OneClosingPerProspect() throws {
        let b = fixture()
        let two = b.prospects.first { $0.lastName == "Two" }!
        try LogRules.checkOneClosing(prospect: two, closings: b.closings)
        let one = b.prospects.first { $0.lastName == "One" }!
        #expect(throws: LogRuleError.self) { try LogRules.checkOneClosing(prospect: one, closings: b.closings) }
        // editing the existing closing is allowed
        try LogRules.checkOneClosing(prospect: one, closings: b.closings, editing: b.closings[0].id)
    }

    @Test func r3AdditionalTransactionsAreIncome() {
        let b = fixture()
        let door = b.prospects.first { $0.lastName == "Door0" }!
        let c = LogRules.closing(from: door, date: Day(2026, 3, 28), transactionSize: 300_000, income: 4_000)
        let rows = LogRules.incomeRows(for: c, lastName: "Door0", addToIncome: true,
                                       additional: [(transactionSize: 200_000, income: 2_500)])
        #expect(rows.count == 2)
        #expect(rows[0].closingID == c.id && rows[1].closingID == nil)
        #expect(rows.allSatisfy { $0.mode == .transaction && $0.attribution.pillar == .prospecting })
    }

    @Test func r6OdometerDefaultsToPreviousEnd() {
        #expect(LogRules.defaultOdometerStart(for: Day(2026, 3, 8), trips: fixture().trips) == 1010)
    }

    @Test func activityRoundsTo15Minutes() {
        #expect(LogRules.roundMinutes(50) == 45)
        #expect(LogRules.roundMinutes(53) == 60)
        #expect(LogRules.roundMinutes(5) == 15)
    }

    @Test func r2PastClientReferral() {
        var p = ProspectRecord(date: NOW)
        p.attribution = Attribution(pillar: .relationships, subPillar: .professional, categoryID: "cat.realtor",
                                    sourceID: "ruth")
        LogRules.applyPastClientReferral(&p, referrerIsPastClient: true)
        #expect(p.attribution.pillar == .clients && p.attribution.categoryID == "cat.past_client")
        #expect(p.originallyFromSourceID == "ruth")
    }

    @Test func defaultFollowUps() {
        let fri = Day(2026, 10, 30)
        #expect(LogRules.defaultFollowUp(strength: .hot, from: fri) == Day(2026, 11, 2))
        #expect(LogRules.defaultFollowUp(strength: .medium, from: fri) == Day(2026, 11, 2))
        #expect(LogRules.defaultFollowUp(strength: .cold, from: fri) == Day(2026, 11, 13))
        #expect(LogRules.defaultFollowUp(strength: .medium, from: Day(2026, 10, 29)) == Day(2026, 11, 2))  // Sun → Mon
        #expect(LogRules.defaultFollowUp(strength: .noGo, from: fri) == nil)
    }
}

@Suite struct TaxonomyTests {
    @Test func countsMatchDesign() {
        #expect(Taxonomy.categories.count == 63)
        #expect(Taxonomy.activities.count == 53)
    }

    @Test func idsMatchSimulator() {
        #expect(Taxonomy.categoryByID["cat.mailer_farming"]?.name == "Mailer/Farming")
        #expect(Taxonomy.activityByID["act.mail_campaigning.clients"] != nil)
        #expect(Taxonomy.activityByID["act.mail_campaigning.advertising"] != nil)
        #expect(Taxonomy.activityByID["act.committee_involvement.prospecting"] != nil)
        #expect(Taxonomy.expenseCategoryByID["exp.travel.meal"]?.irs == "Travel")
        #expect(Set(Taxonomy.categories.map(\.id)).count == 63)
    }

    @Test func sourceNormalization() {
        #expect(SourceRecord.normalize("Zillow") == SourceRecord.normalize("zillow.com"))
        #expect(SourceRecord.normalize("Ruth  Alvarez") == SourceRecord.normalize("ruth alvarez"))
    }

    @Test func formats() {
        #expect(Format.money(1234567) == "$1,234,567")
        #expect(Format.money(-50.5, cents: true) == "-$50.50")
        #expect(Format.moneyK(644_231) == "$644.2k")
        #expect(Format.pct(0.25) == "25%")
        #expect(Format.hours(1234.5) == "1,234.5 h")
    }
}
