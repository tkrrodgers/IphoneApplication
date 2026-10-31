import Foundation

// Report builders (design §14, §15). Each report is a list of widgets. Swift port of herb-sim/reports.py.

public struct Report: Sendable {
    public let key: String
    public let title: String
    public let period: Period
    public let widgets: [ReportWidget]
}

public struct ReportMenuGroup: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let items: [(key: String, title: String)]
}

public enum ReportError: Error, Equatable {
    case unknownReport(String)
}

public struct Reports: Sendable {
    public let book: LogBook
    public let now: Day
    public let dismissed: Set<String>

    public init(_ book: LogBook, now: Day, dismissed: Set<String> = []) {
        self.book = book
        self.now = now
        self.dismissed = dismissed
    }

    var coach: Coach { Coach(book, now: now, dismissed: dismissed) }
    func ledger(_ key: String) -> Ledger { try! Ledger(book, periodKey: key, now: now) }

    // MARK: Helpers

    static func top(_ rows: [BreakdownRow], _ value: (BreakdownRow) -> Double, n: Int = 5) -> [BreakdownRow] {
        Array(rows.filter { $0.key != nil && value($0) > 0 }.sorted { value($0) > value($1) }.prefix(n))
    }

    static func pillarPie(_ led: Ledger, _ title: String, _ value: (BreakdownRow) -> Double,
                          _ fmt: (Double) -> String = { String(Int($0)) }) -> ReportWidget {
        let rows = led.breakdown(.pillar)
        let total = rows.reduce(0) { $0 + value($1) }
        return ReportWidget(title, .pie(rows.map { r in
            ChartItem(r.name, value(r), "\(fmt(value(r))) (\(Format.pct(total > 0 ? value(r) / total : 0)))")
        }, center: nil, caption: nil))
    }

    static func monthColumns(_ title: String, _ series: String, _ led: Ledger, _ value: (MonthRow) -> Double,
                             _ fmt: (Double) -> String) -> ReportWidget {
        ReportWidget(title, span: 3, .columns(series: [series], items: led.byMonth().map {
            ColumnSeriesItem(label: $0.label, values: [value($0)], displays: [fmt(value($0))])
        }))
    }

    // MARK: Shared blocks

    /// Page 1 of the annual report; also the monthly and YTD summaries.
    func summaryWidgets(_ s: Ledger) -> [ReportWidget] {
        let notYet = max(0, s.prospectCount - s.closingCount)
        return [
            ReportWidget("Profit and Loss", .stack([
                ChartItem("Profit", max(0, s.profit), "\(Format.money(s.profit)) (\(Format.pct(ratio(s.profit, s.incomeTotal))))", role: .profit),
                ChartItem("Expenses", s.expensesTotal, "\(Format.money(s.expensesTotal)) (\(Format.pct(ratio(s.expensesTotal, s.incomeTotal))))", role: .expense),
            ])),
            ReportWidget("Conversion Rate", .pie([
                ChartItem("Closings", Double(s.closingCount), "\(s.closingCount) closings"),
                ChartItem("Not yet converted", Double(notYet), "\(notYet) of \(s.prospectCount) prospects"),
            ], center: Format.pct(s.conversion), caption: "\(Format.pct(s.conversion)) = \(s.closingCount) ÷ \(s.prospectCount)")),
            ReportWidget("Transaction Summary", .stats([
                StatItem("Average closing volume", Format.money(s.avgVolume), formula: "\(Format.money(s.volume)) ÷ \(s.closingCount)"),
                StatItem("Average closing income", Format.money(s.avgClosingIncome), formula: "\(Format.money(s.closingIncome)) ÷ \(s.closingCount)"),
            ])),
            ReportWidget("Efficiency Analysis", .stats([
                StatItem("Business-building hours per prospect", Format.num(s.hoursPerProspect, decimals: 2),
                         formula: "\(Format.num(s.hoursPerProspect, decimals: 2)) = \(Format.num(s.bbHours, decimals: 2)) ÷ \(s.prospectCount)"),
                StatItem("Business-building hours per closing", Format.num(s.hoursPerClosing, decimals: 2),
                         formula: "\(Format.num(s.hoursPerClosing, decimals: 2)) = \(Format.num(s.bbHours, decimals: 2)) ÷ \(s.closingCount)"),
            ])),
            ReportWidget("Hourly Rate Analysis", .stats([
                StatItem("Based on gross income", Format.money(s.hourlyGross), formula: "\(Format.money(s.incomeTotal)) ÷ \(Format.num(s.workHours)) hours"),
                StatItem("Based on net income", Format.money(s.hourlyNet), formula: "\(Format.money(s.profit)) ÷ \(Format.num(s.workHours)) hours"),
            ])),
            ReportWidget("Volume Closed", .stat(value: s.volume, display: Format.money(s.volume), caption: "\(s.closingCount) closings",
                                          formula: "Σ transaction size, \(s.period.label)")),
            ReportWidget("Logsperity Index", .index(Coach.indexSummary(s))),
        ]
    }

    func topPerformers(_ led: Ledger, minProspects: Int = 3) -> ReportWidget {
        let dims: [(Dimension, String)] = [(.pillar, "Pillar"), (.category, "Category"), (.source, "Source"), (.activity, "Activity")]
        let rows: [ReportRow] = dims.map { dim, label in
            let b = led.breakdown(dim).filter { $0.key != nil && !(dim == .source && $0.name == "Unknown") }
            let bestConv = b.filter { $0.prospects >= minProspects }.max { ($0.conversion ?? 0) < ($1.conversion ?? 0) }
            let bestVol = b.max { $0.volume < $1.volume }
            let bestInc = b.max { $0.closingIncome < $1.closingIncome }
            return ["dimension": .text(label),
                    "conversion": .text(bestConv.map { "\($0.name) (\(Format.pct($0.conversion)))" } ?? Format.dash),
                    "volume": .text(bestVol.flatMap { $0.volume > 0 ? "\($0.name) (\(Format.moneyK($0.volume)))" : nil } ?? Format.dash),
                    "income": .text(bestInc.flatMap { $0.closingIncome > 0 ? "\($0.name) (\(Format.money($0.closingIncome)))" : nil } ?? Format.dash)]
        }
        return ReportWidget("Top Performers", span: 3, .table(columns: [
            Column("dimension", ""), Column("conversion", "Best conversion"), Column("volume", "Most volume closed"),
            Column("income", "Most income earned"),
        ], rows: rows, total: nil, note: "Conversion leaders need at least \(minProspects) prospects."))
    }

    func monthlyAverages(_ led: Ledger) -> ReportWidget {
        let m = Double(led.monthsInUse)
        let one: (Double) -> String = { Format.num($0, decimals: 1) }
        let money: (Double) -> String = { Format.money($0) }
        let metrics: [(String, Double, (Double) -> String)] = [
            ("Prospects", Double(led.prospectCount), one), ("Closings", Double(led.closingCount), one),
            ("Volume", led.volume, money), ("Income", led.incomeTotal, money), ("Expenses", led.expensesTotal, money),
            ("Profit", led.profit, money), ("Business-building hours", led.bbHours, one),
        ]
        return ReportWidget("Monthly Averages", .table(columns: [
            Column("metric", "Metric"), Column("total", "Total", right: true),
            Column("avg", "Per month (\(Int(m)) months in use)", right: true),
        ], rows: metrics.map { ["metric": .text($0.0), "total": .text($0.2($0.1)), "avg": .text($0.2($0.1 / m))] },
           total: nil, note: nil))
    }

    func inputOutput(_ led: Ledger) -> ReportWidget {
        ReportWidget("Input to Output", span: 3, .columns(
            series: ["Business-building hours", "Prospects", "Closings", "Income ($k)"],
            items: led.byMonth().map { r in
                ColumnSeriesItem(label: r.label, values: [r.bbHours, Double(r.prospects), Double(r.closings), r.income / 1000],
                                 displays: [Format.num(r.bbHours, decimals: 1), String(r.prospects), String(r.closings), Format.moneyK(r.income)])
            }))
    }

    // MARK: Log reports

    public static let logTitles: [(key: String, title: String)] = [
        ("prospects", "Prospects Log"), ("closings", "Closings Log"), ("income", "Income Log"),
        ("expenses", "Expense Log"), ("trips", "Mileage Log"), ("activities", "Activity Log"),
    ]

    func logWidget(_ led: Ledger, _ log: String) -> ReportWidget {
        let title = Self.logTitles.first { $0.key == log }!.title
        func pillarName(_ a: Attribution) -> Cell { .text(a.pillar?.name ?? "") }
        func cat(_ a: Attribution) -> Cell { .text(a.categoryID.flatMap { Taxonomy.categoryByID[$0]?.name } ?? "") }
        func act(_ a: Attribution) -> Cell { .text(a.activityID.flatMap { Taxonomy.activityByID[$0]?.name } ?? "") }
        func src(_ id: RecordID?) -> Cell { .text(book.sourceName(id) ?? "") }
        let date: (Day) -> Cell = { .text($0.iso) }
        var cols: [Column]
        var rows: [ReportRow]
        var total: ReportRow
        switch log {
        case "prospects":
            cols = [Column("date", "Date"), Column("name", "Name"), Column("phone", "Phone"), Column("pillar", "Pillar"),
                    Column("category", "Category"), Column("source", "Source"), Column("activity", "Activity"),
                    Column("strength", "Strength"), Column("plan", "Plan of action"), Column("followUp", "Follow-up")]
            rows = led.prospects.reversed().map { p in
                ["date": date(p.date), "name": .text(p.fullName), "phone": .text(p.phone1 ?? ""), "pillar": pillarName(p.attribution),
                 "category": cat(p.attribution), "source": src(p.attribution.sourceID), "activity": act(p.attribution),
                 "strength": .text(p.strength?.name ?? ""), "plan": .text(p.planOfAction ?? ""), "followUp": .text(p.followUp?.iso ?? "")]
            }
            total = ["date": .text("\(rows.count) entries")]
        case "closings":
            cols = [Column("date", "Date"), Column("name", "Name"), Column("pillar", "Pillar"), Column("category", "Category"),
                    Column("source", "Source"), Column("activity", "Activity"),
                    Column("size", "Transaction size", right: true, .money), Column("income", "Income", right: true, .money)]
            rows = led.closings.reversed().map { c in
                let name = book.prospects.first { $0.id == c.prospectID }?.fullName ?? ""
                return ["date": date(c.date), "name": .text(name), "pillar": pillarName(c.attribution), "category": cat(c.attribution),
                        "source": src(c.attribution.sourceID), "activity": act(c.attribution),
                        "size": .number(c.transactionSize), "income": .number(c.income)]
            }
            total = ["date": .text("\(rows.count) entries"), "size": .number(led.volume), "income": .number(led.closingIncome)]
        case "income":
            cols = [Column("date", "Date"), Column("kind", "Kind"), Column("name", "Name / type"), Column("payer", "Payer"),
                    Column("count", "# trans.", right: true, .num), Column("size", "Transaction size", right: true, .money),
                    Column("amount", "Income", right: true, .money)]
            rows = led.income.reversed().map { i in
                let kind = ["transaction": "Transaction", "batch": "Batch", "type": "By type"][i.mode.rawValue]!
                let name = i.mode == .transaction ? (i.lastName ?? "") : (i.type?.name ?? "")
                return ["date": date(i.date), "kind": .text(kind), "name": .text(name), "payer": .text(i.payer ?? ""),
                        "count": i.transactionCount.map { .number(Double($0)) } ?? .text(""),
                        "size": i.transactionSize.map { .number($0) } ?? .text(""), "amount": .number(i.amount)]
            }
            total = ["date": .text("\(rows.count) entries"), "amount": .number(led.incomeTotal)]
        case "expenses":
            cols = [Column("date", "Date"), Column("vendor", "Vendor"), Column("group", "Group"), Column("category", "Category"),
                    Column("irs", "IRS category"), Column("receipt", "Receipt"), Column("amount", "Amount", right: true, .money)]
            rows = led.expenses.reversed().map { e in
                ["date": date(e.date), "vendor": .text(e.vendor), "group": .text(e.group.name), "category": .text(e.category?.name ?? ""),
                 "irs": .text(e.irs), "receipt": .text(e.hasReceipt ? "✓" : e.amount >= 75 ? "Missing" : Format.dash),
                 "amount": .number(e.amount)]
            }
            total = ["date": .text("\(rows.count) entries"), "amount": .number(led.cashExpenses)]
        case "trips":
            cols = [Column("date", "Date"), Column("reason", "Reason"), Column("destination", "Destination"),
                    Column("begin", "Begin", right: true, .num1), Column("end", "End", right: true, .num1),
                    Column("miles", "Miles", right: true, .num1), Column("use", "Use"), Column("deduction", "Deduction", right: true, .money)]
            rows = led.trips.reversed().map { t in
                ["date": date(t.date), "reason": .text(t.reason), "destination": .text(t.destination),
                 "begin": t.odometerStart.map { .number($0) } ?? .text(""), "end": t.odometerEnd.map { .number($0) } ?? .text(""),
                 "miles": .number(t.miles), "use": .text(t.isBusiness ? "Business" : "Personal"),
                 "deduction": .number(t.isBusiness ? t.miles * Taxonomy.mileageRate(on: t.date) : 0)]
            }
            total = ["date": .text("\(rows.count) entries"), "miles": .number(led.businessMiles), "deduction": .number(led.mileageDeduction)]
        default:
            cols = [Column("date", "Date"), Column("pillar", "Pillar"), Column("activity", "Activity"), Column("with", "With"),
                    Column("minutes", "Minutes", right: true, .num), Column("hours", "Hours", right: true, .num1)]
            rows = led.activities.reversed().map { a in
                ["date": date(a.date), "pillar": pillarName(a.attribution), "activity": act(a.attribution),
                 "with": src(a.attribution.sourceID), "minutes": .number(Double(a.minutes)), "hours": .number(Double(a.minutes) / 60)]
            }
            total = ["date": .text("\(rows.count) entries"), "minutes": .number(led.bbHours * 60), "hours": .number(led.bbHours)]
        }
        return ReportWidget(title, span: 3, .table(columns: cols, rows: rows, total: total, note: nil))
    }

    // MARK: Detailed reports

    static func breakdownTable(_ rows: [BreakdownRow], _ fields: [(String, String, ValueFormat, (BreakdownRow) -> Double?)],
                               nameLabel: String) -> ([Column], [ReportRow]) {
        let cols = [Column("name", nameLabel)] + fields.map { Column($0.0, $0.1, right: true, $0.2) }
        let out: [ReportRow] = rows.map { r in
            var row: ReportRow = ["name": .text(r.name)]
            for f in fields { row[f.0] = .number(f.3(r)) }
            return row
        }
        return (cols, out)
    }

    func prospectsReport(_ led: Ledger) -> [ReportWidget] {
        let pil = led.breakdown(.pillar), cats = led.breakdown(.category), acts = led.breakdown(.activity)
        let srcs = led.breakdown(.source)
        let tp = pil.max { $0.prospects < $1.prospects }
        let strength = Dictionary(grouping: led.prospects.compactMap(\.strength), by: { $0 }).mapValues(\.count)
        return [
            ReportWidget("Prospects", .stats([
                StatItem("Prospects", String(led.prospectCount), caption: led.period.label),
                StatItem("Conversion", Format.pct(led.conversion), formula: "\(led.closingCount) ÷ \(led.prospectCount)"),
                StatItem("Hours per prospect", Format.num(led.hoursPerProspect, decimals: 2),
                         formula: "\(Format.num(led.bbHours, decimals: 1)) ÷ \(led.prospectCount)"),
                StatItem("Top pillar", tp.map(\.name) ?? Format.dash, caption: tp.map { "\($0.prospects) prospects" }),
            ])),
            Self.pillarPie(led, "Prospects by Pillar", { Double($0.prospects) }),
            ReportWidget("Strength of Contact", .pie(Strength.allCases.map {
                ChartItem($0.name, Double(strength[$0] ?? 0), String(strength[$0] ?? 0))
            }, center: nil, caption: nil)),
            ReportWidget("Top 5 Categories", .bar(Self.top(cats, { Double($0.prospects) }).map { ChartItem($0.name, Double($0.prospects), String($0.prospects)) }, horizontal: true)),
            ReportWidget("Top 5 Activities", .bar(Self.top(acts, { Double($0.prospects) }).map { ChartItem($0.name, Double($0.prospects), String($0.prospects)) }, horizontal: true)),
            ReportWidget("Top Sources", .table(columns: [Column("name", "Source"), Column("prospects", "Prospects", right: true, .num),
                                                   Column("share", "Share", right: true, .pct)],
                                         rows: Array(srcs.filter { $0.prospects > 0 }.prefix(8)).map {
                                             ["name": .text($0.name), "prospects": .number(Double($0.prospects)),
                                              "share": .number(ratio(Double($0.prospects), Double(led.prospectCount)))]
                                         }, total: nil, note: nil)),
            ReportWidget("Prospects by Category", span: 2, .table(columns: [
                Column("name", "Category"), Column("pillar", "Pillar"), Column("prospects", "Prospects", right: true, .num),
                Column("share", "% of total", right: true, .pct),
            ], rows: cats.filter { $0.prospects > 0 }.map {
                ["name": .text($0.name), "pillar": .text($0.pillar?.name ?? ""), "prospects": .number(Double($0.prospects)),
                 "share": .number(ratio(Double($0.prospects), Double(led.prospectCount)))]
            }, total: nil, note: nil)),
            Self.monthColumns("Prospects by Month", "Prospects", led, { Double($0.prospects) }, { String(Int($0)) }),
        ]
    }

    func closingsReport(_ led: Ledger) -> [ReportWidget] {
        let pil = led.breakdown(.pillar)
        let cats = led.breakdown(.category).filter { $0.closings > 0 }.sorted { $0.closingIncome > $1.closingIncome }
        let acts = led.breakdown(.activity).filter { $0.closings > 0 }
        let (catCols, catRows) = Self.breakdownTable(cats, [
            ("closings", "Closings", .num, { Double($0.closings) }), ("volume", "Volume", .money, { $0.volume }),
            ("income", "Income", .money, { $0.closingIncome }), ("avgVolume", "Avg volume", .money, { $0.avgVolume }),
            ("avgIncome", "Avg income", .money, { $0.avgIncome }),
        ], nameLabel: "Category")
        let (actCols, actRows) = Self.breakdownTable(Self.top(acts, { Double($0.closings) }), [
            ("closings", "Closings", .num, { Double($0.closings) }), ("volume", "Volume", .money, { $0.volume }),
            ("income", "Income", .money, { $0.closingIncome }),
        ], nameLabel: "Activity")
        return [
            ReportWidget("Closings", .stats([
                StatItem("Closings", String(led.closingCount), caption: led.period.label),
                StatItem("Volume", Format.money(led.volume)),
                StatItem("Closing income", Format.money(led.closingIncome)),
                StatItem("Average closing volume", Format.money(led.avgVolume), formula: "\(Format.money(led.volume)) ÷ \(led.closingCount)"),
                StatItem("Average closing income", Format.money(led.avgClosingIncome), formula: "\(Format.money(led.closingIncome)) ÷ \(led.closingCount)"),
            ])),
            Self.pillarPie(led, "Share by Quantity", { Double($0.closings) }),
            Self.pillarPie(led, "Share by Volume", { $0.volume }, { Format.moneyK($0) }),
            Self.pillarPie(led, "Share by Income", { $0.closingIncome }, { Format.money($0) }),
            ReportWidget("Average Volume per Closing by Pillar", .bar(pil.map { ChartItem($0.name, $0.avgVolume ?? 0, Format.moneyK($0.avgVolume)) }, horizontal: false)),
            ReportWidget("Closings by Category", span: 2, .table(columns: catCols, rows: catRows, total: nil, note: nil)),
            ReportWidget("Top 5 Activities by Closings", span: 3, .table(columns: actCols, rows: actRows, total: nil, note: nil)),
        ]
    }

    static func convRows(_ rows: [BreakdownRow]) -> [BreakdownRow] {
        rows.filter { $0.prospects > 0 }.sorted { (($0.conversion ?? 0), $0.closings) > (($1.conversion ?? 0), $1.closings) }
    }

    static var convFields: [(String, String, ValueFormat, (BreakdownRow) -> Double?)] { [
        ("prospects", "Prospects", .num, { Double($0.prospects) }), ("closings", "Closings", .num, { Double($0.closings) }),
        ("conversion", "Conversion", .pct, { $0.conversion }),
    ] }

    func conversionReport(_ led: Ledger) -> [ReportWidget] {
        let pil = led.breakdown(.pillar)
        let cats = Self.convRows(led.breakdown(.category).filter { $0.key != nil })
        let acts = Self.convRows(led.breakdown(.activity).filter { $0.key != nil })
        let none = (cats + acts).filter { $0.closings == 0 }.sorted { $0.prospects > $1.prospects }
        let (cc, cr) = Self.breakdownTable(cats.filter { $0.closings > 0 }, Self.convFields, nameLabel: "Category")
        let (ac, ar) = Self.breakdownTable(acts.filter { $0.closings > 0 }, Self.convFields, nameLabel: "Activity")
        return [
            ReportWidget("Overall Conversion", .stat(value: led.conversion, display: Format.pct(led.conversion),
                                               caption: "\(led.closingCount) closings from \(led.prospectCount) prospects",
                                               formula: "\(Format.pct(led.conversion)) = \(led.closingCount) ÷ \(led.prospectCount)")),
            ReportWidget("Conversion by Pillar", .bar(pil.map { ChartItem($0.name, $0.conversion ?? 0, Format.pct($0.conversion)) }, horizontal: false)),
            ReportWidget("Top 5 Categories by Conversion", .bar(cats.filter { $0.prospects >= 3 }.prefix(5).map {
                ChartItem($0.name, $0.conversion ?? 0, Format.pct($0.conversion))
            }, horizontal: true)),
            ReportWidget("Categories, best to worst", span: 2, .table(columns: cc, rows: cr, total: nil, note: nil)),
            ReportWidget("Activities, best to worst", span: 2, .table(columns: ac, rows: ar, total: nil, note: nil)),
            ReportWidget("No conversion yet", .list(none.map {
                ListItem(title: $0.name, text: "\($0.prospects) prospects, 0 closings", level: $0.prospects >= 4 ? .concern : .watch)
            })),
        ]
    }

    func sourceConversionReport(_ led: Ledger) -> [ReportWidget] {
        let srcs = led.breakdown(.source)
        let fields = Self.convFields + [("income", "Income", .money, { $0.closingIncome }), ("spent", "Spent", .money, { $0.expenses })]
        let (cols, conv) = Self.breakdownTable(Self.convRows(srcs.filter { $0.closings > 0 }), fields, nameLabel: "Source")
        let (_, none) = Self.breakdownTable(srcs.filter { $0.prospects > 0 && $0.closings == 0 }.sorted { $0.prospects > $1.prospects },
                                            fields, nameLabel: "Source")
        return [
            ReportWidget("Top Sources by Income", .bar(Self.top(srcs, { $0.closingIncome }, n: 6).map {
                ChartItem($0.name, $0.closingIncome, Format.money($0.closingIncome))
            }, horizontal: true)),
            ReportWidget("Sources with Conversion", span: 2, .table(columns: cols, rows: conv, total: nil, note: nil)),
            ReportWidget("Sources with No Conversion", span: 3, .table(columns: cols, rows: none, total: nil,
                                                                 note: "A source sending 4–5 prospects that never convert: time to move on, or coach the source.")),
        ]
    }

    func incomeReport(_ led: Ledger) -> [ReportWidget] {
        let cats = led.breakdown(.category), acts = led.breakdown(.activity), pil = led.breakdown(.pillar)
        let tr = PlanTracking(book, year: led.period.to.year, now: now)
        var byType: [String: Double] = [:]
        for i in led.income where i.mode != .transaction {
            byType[(i.type?.name ?? "Other") + (i.mode == .batch ? " (batch)" : ""), default: 0] += i.amount
        }
        let (pc, pr) = Self.breakdownTable(pil, [
            ("closings", "Closings", .num, { Double($0.closings) }), ("income", "Income", .money, { $0.income }),
            ("avgIncome", "Per closing", .money, { $0.avgIncome }),
        ], nameLabel: "Pillar")
        return [
            ReportWidget("Income", .stats([
                StatItem("Total income", Format.money(led.incomeTotal), caption: led.period.label),
                StatItem("From closings", Format.money(led.closingIncome), caption: "\(led.closingCount) closings"),
                StatItem("Non-transaction income", Format.money(led.nonTransactionIncome)),
                StatItem("Projected annual income", Format.money(tr.forecast.value), formula: "YTD + open pipeline + recent run rate"),
            ])),
            ReportWidget("Top 5 Categories by Income", .bar(Self.top(cats, { $0.income }).map { ChartItem($0.name, $0.income, Format.money($0.income)) }, horizontal: true)),
            ReportWidget("Top 5 Activities by Income", .bar(Self.top(acts, { $0.income }).map { ChartItem($0.name, $0.income, Format.money($0.income)) }, horizontal: true)),
            ReportWidget("Income per Closing by Pillar", .table(columns: pc, rows: pr, total: nil, note: nil)),
            ReportWidget("Non-transaction Income", .table(columns: [Column("type", "Type"), Column("amount", "Amount", right: true, .money)],
                                                    rows: byType.sorted { $0.value > $1.value }.map { ["type": .text($0.key), "amount": .number($0.value)] },
                                                    total: nil, note: nil)),
            Self.monthColumns("Income by Month", "Income", led, { $0.income }, { Format.moneyK($0) }),
        ]
    }

    static func irsTotals(_ led: Ledger) -> [String: Double] {
        var out = Dictionary(uniqueKeysWithValues: Taxonomy.irsCategories.map { ($0, 0.0) })
        for e in led.expenses { out[e.irs, default: 0] += e.amount }
        out["Car & Truck", default: 0] += led.mileageDeduction
        return out
    }

    func expenseReport(_ led: Ledger) -> [ReportWidget] {
        let groups = Dictionary(grouping: led.expenses, by: \.group).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let totalCash = led.cashExpenses > 0 ? led.cashExpenses : 1
        let irs = Self.irsTotals(led)
        let cats = Dictionary(grouping: led.expenses, by: \.categoryID).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let missing = led.expenses.filter { $0.amount >= 75 && !$0.hasReceipt }
        return [
            ReportWidget("Expenses", .stats([
                StatItem("Total expenses", Format.money(led.expensesTotal), caption: led.period.label),
                StatItem("Cash expenses", Format.money(led.cashExpenses)),
                StatItem("Mileage deduction", Format.money(led.mileageDeduction)),
                StatItem("Share of income", Format.pct(ratio(led.expensesTotal, led.incomeTotal)),
                         formula: "\(Format.money(led.expensesTotal)) ÷ \(Format.money(led.incomeTotal))"),
            ])),
            ReportWidget("Expenses by Group", .pie(groups.sorted { $0.value > $1.value }.map {
                ChartItem($0.key.name, $0.value, "\(Format.money($0.value)) (\(Format.pct($0.value / totalCash)))")
            }, center: nil, caption: nil)),
            ReportWidget("By IRS Category", .table(columns: [Column("irs", "IRS category"), Column("amount", "Amount", right: true, .money)],
                                             rows: Taxonomy.irsCategories.filter { irs[$0]! != 0 }.map { ["irs": .text($0), "amount": .number(irs[$0])] },
                                             total: nil, note: "IRS mapping from the 2018 model — review it with your CPA.")),
            ReportWidget("Top Specific Categories", .table(columns: [
                Column("group", "Group"), Column("name", "Category"), Column("irs", "IRS"), Column("amount", "Amount", right: true, .money),
            ], rows: cats.sorted { $0.value > $1.value }.prefix(12).compactMap { k, v in
                Taxonomy.expenseCategoryByID[k].map { ["group": .text($0.group.name), "name": .text($0.name), "irs": .text($0.irs), "amount": .number(v)] }
            }, total: nil, note: nil)),
            ReportWidget("Receipts Missing ($75 or more)", .table(columns: [
                Column("date", "Date"), Column("vendor", "Vendor"), Column("category", "Category"), Column("amount", "Amount", right: true, .money),
            ], rows: missing.map { ["date": .text($0.date.iso), "vendor": .text($0.vendor), "category": .text($0.category?.name ?? ""), "amount": .number($0.amount)] },
               total: nil, note: "IRS documentary-evidence threshold. Snap these so they hold up in an audit.")),
            Self.monthColumns("Expenses by Month", "Expenses", led, { $0.expenses }, { Format.moneyK($0) }),
        ]
    }

    func mileageReport(_ led: Ledger) -> [ReportWidget] {
        var rateRows: [ReportRow] = []
        for r in Taxonomy.mileageRates {
            let miles = led.businessTrips.filter { r.from <= $0.date && $0.date <= r.to }.reduce(0) { $0 + $1.miles }
            if miles > 0 {
                rateRows.append(["period": .text("\(Format.shortDate(r.from)) – \(Format.shortDate(r.to, withYear: true))"),
                                 "miles": .number(miles), "rate": .text(String(format: "$%.3f", r.rate)),
                                 "deduction": .number(miles * r.rate),
                                 "formula": .text("\(Format.num(miles, decimals: 1)) mi × \(String(format: "$%.3f", r.rate))")])
            }
        }
        let dests = Dictionary(grouping: led.businessTrips, by: \.destination).mapValues { $0.reduce(0) { $0 + $1.miles } }
        let m = Double(led.monthsInUse)
        return [
            ReportWidget("Mileage", .stats([
                StatItem("Business miles", Format.num(led.businessMiles), caption: led.period.label),
                StatItem("Deduction", Format.money(led.mileageDeduction), formula: "miles × IRS rate by trip date"),
                StatItem("Average miles per month", Format.num(led.businessMiles / m), formula: "÷ \(Int(m)) months in use"),
                StatItem("Estimated hours in the car", Format.num(led.businessMiles / 60, decimals: 1), formula: "miles ÷ 60"),
            ])),
            ReportWidget("Deduction by Rate Period", .table(columns: [
                Column("period", "Period"), Column("miles", "Miles", right: true, .num1), Column("rate", "Rate", right: true),
                Column("deduction", "Deduction", right: true, .money), Column("formula", "Math"),
            ], rows: rateRows, total: nil, note: "Each trip uses the IRS rate in effect on its date.")),
            ReportWidget("Top Destinations (miles)", .bar(dests.sorted { $0.value > $1.value }.prefix(8).map {
                ChartItem($0.key, $0.value, Format.num($0.value))
            }, horizontal: true)),
            Self.monthColumns("Miles by Month", "Business miles", led, { $0.miles }, { Format.num($0) }),
        ]
    }

    func activityReport(_ led: Ledger) -> [ReportWidget] {
        let acts = led.breakdown(.activity).filter { $0.hours > 0 }.sorted { $0.hours > $1.hours }
        let total = led.bbHours > 0 ? led.bbHours : 1
        var (cols, rows) = Self.breakdownTable(acts, [
            ("hours", "Hours", .num1, { $0.hours }), ("share", "% of time", .pct, { $0.hours / total }),
            ("prospects", "Prospects", .num, { Double($0.prospects) }), ("closings", "Closings", .num, { Double($0.closings) }),
            ("income", "Income", .money, { $0.income }), ("perHour", "$ / hour", .money, { $0.incomePerHour }),
        ], nameLabel: "Activity")
        cols[0] = Column("name", "Activity")
        rows = rows.map { $0 }
        return [
            ReportWidget("Business-building Time", .stats([
                StatItem("Hours", Format.num(led.bbHours, decimals: 1), caption: led.period.label),
                StatItem("Hours per week", Format.num(led.bbHoursPerWeek, decimals: 1)),
                StatItem("Income per hour", Format.money(led.incomePerBBHour), formula: "\(Format.money(led.incomeTotal)) ÷ \(Format.num(led.bbHours, decimals: 1)) h"),
            ])),
            Self.pillarPie(led, "Hours by Pillar", { $0.hours }, { Format.hours($0) }),
            ReportWidget("Hours by Activity", .bar(acts.prefix(10).map { ChartItem($0.name, $0.hours, Format.hours($0.hours)) }, horizontal: true)),
            ReportWidget("Income per Hour by Activity (top 5)", .bar(Self.top(acts, { $0.incomePerHour ?? 0 }).map {
                ChartItem($0.name, $0.incomePerHour ?? 0, Format.money($0.incomePerHour))
            }, horizontal: true)),
            ReportWidget("Activity Detail", span: 3, .table(columns: cols, rows: rows, total: nil, note: nil)),
        ]
    }

    func efficiencyReport(_ led: Ledger) -> [ReportWidget] {
        let pil = led.breakdown(.pillar)
        var (cols, rows) = Self.breakdownTable(pil, [
            ("hours", "Hours", .num1, { $0.hours }), ("hpp", "Hours / prospect", .num1, { $0.hoursPerProspect }),
            ("hpc", "Hours / closing", .num1, { $0.hoursPerClosing }), ("gross", "Gross $ / hour", .money, { $0.incomePerHour }),
            ("profit", "Profit $ / hour", .money, { ratio($0.income - $0.expenses, $0.hours) }),
        ], nameLabel: "Pillar")
        rows.append(["name": .text("Overall"), "hours": .number(led.bbHours), "hpp": .number(led.hoursPerProspect),
                     "hpc": .number(led.hoursPerClosing), "gross": .number(led.incomePerBBHour), "profit": .number(led.profitPerBBHour)])
        cols[0] = Column("name", "Pillar")
        let best = pil.filter { $0.hoursPerClosing != nil }.min { $0.hoursPerClosing! < $1.hoursPerClosing! }
        return [
            ReportWidget("Efficiency by Pillar", span: 3, .table(columns: cols, rows: rows, total: nil,
                                                           note: "Lower hours per prospect and per closing is better." + (best.map { " Most efficient: \($0.name)." } ?? ""))),
            ReportWidget("Hours per Prospect", .bar(pil.map { ChartItem($0.name, $0.hoursPerProspect ?? 0, Format.num($0.hoursPerProspect, decimals: 1)) }, horizontal: false)),
            ReportWidget("Hours per Closing", .bar(pil.map { ChartItem($0.name, $0.hoursPerClosing ?? 0, Format.num($0.hoursPerClosing, decimals: 1)) }, horizontal: false)),
            ReportWidget("Standard Hourly Rates", .stats([
                StatItem("Gross", Format.money(led.hourlyGross), formula: "\(Format.money(led.incomeTotal)) ÷ \(Format.num(led.workHours)) work hours"),
                StatItem("Net", Format.money(led.hourlyNet), formula: "\(Format.money(led.profit)) ÷ \(Format.num(led.workHours)) work hours"),
                StatItem("Business-building hours per week", Format.num(led.bbHoursPerWeek, decimals: 1)),
            ])),
        ]
    }

    static let irsLines: [(String, String)] = [
        ("Advertising", "8"), ("Car & Truck", "9"), ("Commissions/Fees", "10"), ("Insurance", "15"), ("Interest-Other", "16b"),
        ("Legal/Professional", "17"), ("Office", "18"), ("Rent", "20b"), ("Repairs", "21"), ("Supplies", "22"), ("Taxes", "23"),
        ("Travel", "24a"), ("Meals/Entertainment", "24b"), ("Utilities", "25"), ("Wages", "26"), ("Other", "27a"),
    ]

    func pnlReport(_ led: Ledger) -> [ReportWidget] {
        let irs = Self.irsTotals(led)
        var other: [String: Double] = [:]
        for e in led.expenses where e.irs == "Other" { other[e.category?.name ?? "Other", default: 0] += e.amount }
        return [
            ReportWidget("Profit & Loss (Schedule C format)", .stats([
                StatItem("Gross receipts", Format.money(led.incomeTotal)),
                StatItem("Total expenses", Format.money(led.expensesTotal)),
                StatItem("Net profit", Format.money(led.profit), formula: "\(Format.money(led.incomeTotal)) − \(Format.money(led.expensesTotal))"),
            ])),
            ReportWidget("Expenses by Line", span: 2, .table(columns: [
                Column("line", "Line"), Column("name", "Expense"), Column("amount", "Amount", right: true, .money),
            ], rows: Self.irsLines.map { ["line": .text($0.1), "name": .text($0.0), "amount": .number(irs[$0.0] ?? 0)] },
               total: ["name": .text("Total expenses"), "amount": .number(led.expensesTotal)],
               note: "Car & Truck uses the standard mileage deduction. Meals are shown in full; generally 50% is deductible — confirm treatment with your CPA.")),
            ReportWidget("Statement 1 — Other Expenses", .table(columns: [Column("name", "Item"), Column("amount", "Amount", right: true, .money)],
                                                          rows: other.sorted { $0.value > $1.value }.map { ["name": .text($0.key), "amount": .number($0.value)] },
                                                          total: ["name": .text("Total other"), "amount": .number(other.values.reduce(0, +))], note: nil)),
        ]
    }

    func profitROIReport(_ led: Ledger) -> [ReportWidget] {
        let rows = led.pillarROI()
        let pil = rows.filter { !["overhead", "total"].contains($0.key) }
        func table(_ fields: [(String, String, ValueFormat, (ROIRow) -> Double?)], label: Bool = false) -> ([Column], [ReportRow]) {
            var cols = [Column("name", "Pillar")] + fields.map { Column($0.0, $0.1, right: true, $0.2) }
            if label { cols.append(Column("label", "")) }
            return (cols, rows.map { r in
                var row: ReportRow = ["name": .text(r.name), "label": .text(r.label)]
                for f in fields { row[f.0] = .number(f.3(r)) }
                return row
            })
        }
        let (mc, mr) = table([("income", "Income", .money, { $0.income }), ("expenses", "Expenses", .money, { $0.expenses }),
                              ("profit", "Profit", .money, { $0.profit }), ("margin", "Margin", .pct, { $0.margin }),
                              ("roi", "ROI", .num1, { $0.roi })])
        let (tc, trows) = table([("hours", "Hours", .num1, { $0.hours }), ("wages", "Wages invested", .money, { $0.wages }),
                                 ("capital", "Capital", .money, { $0.capital }), ("profit", "Profit", .money, { $0.profitWithTime }),
                                 ("roi", "ROI", .num1, { $0.roiWithTime })], label: true)
        return [
            ReportWidget("Profit and Loss", .stack([
                ChartItem("Profit", max(0, led.profit), "\(Format.money(led.profit)) (\(Format.pct(led.margin)))", role: .profit),
                ChartItem("Expenses", led.expensesTotal, "\(Format.money(led.expensesTotal)) (\(Format.pct(ratio(led.expensesTotal, led.incomeTotal))))", role: .expense),
            ])),
            ReportWidget("Profit", .stats([
                StatItem("Net profit", Format.money(led.profit), formula: "\(Format.money(led.incomeTotal)) − \(Format.money(led.expensesTotal))"),
                StatItem("Profit margin", Format.pct(led.margin, decimals: 1)),
                StatItem("Net ROI (with time)", Format.pct(led.netROI), formula: "(income − capital) ÷ capital"),
            ])),
            ReportWidget("Profit by Pillar", .pie(pil.map { ChartItem($0.name, max(0, $0.profit), Format.money($0.profit)) }, center: nil, caption: nil)),
            ReportWidget("ROI by Pillar — money only", span: 3, .table(columns: mc, rows: mr, total: nil, note: nil)),
            ReportWidget("ROI by Pillar — time and money", span: 3, .table(columns: tc, rows: trows, total: nil,
                                                                     note: "Wages invested = business-building hours × your gross hourly rate (\(Format.money(led.hourlyGross))). Overhead (General, Self-Improvement, Technology, Travel and mileage) is included in the total.")),
            ReportWidget("Income, Expenses and Profit by Pillar", span: 3, .columns(series: ["Income", "Expenses", "Profit"], items: pil.map {
                ColumnSeriesItem(label: $0.name, values: [$0.income, $0.expenses, $0.profit],
                                 displays: [Format.moneyK($0.income), Format.moneyK($0.expenses), Format.moneyK($0.profit)])
            })),
        ]
    }

    func relationshipsAdsReport(_ led: Ledger) -> [ReportWidget] {
        let sp = Dictionary(uniqueKeysWithValues: led.breakdown(.subPillar).map { ($0.key!, $0) })
        let hg = led.hourlyGross ?? 0
        let keys = ["personal", "professional", "internet", "traditional"]
        func wages(_ k: String) -> Double { (sp[k]?.hours ?? 0) * hg }
        func profit(_ k: String) -> Double { (sp[k]?.income ?? 0) - wages(k) - (sp[k]?.expenses ?? 0) }
        let metrics: [(String, (String) -> String)] = [
            ("Prospects", { Format.num(Double(sp[$0]?.prospects ?? 0)) }), ("Closings", { Format.num(Double(sp[$0]?.closings ?? 0)) }),
            ("Conversion", { Format.pct(sp[$0]?.conversion) }), ("Volume", { Format.moneyK(sp[$0]?.volume ?? 0) }),
            ("Income", { Format.money(sp[$0]?.income ?? 0) }), ("Hours", { Format.num(sp[$0]?.hours ?? 0, decimals: 1) }),
            ("Estimated wages", { Format.money(wages($0)) }), ("Expenses", { Format.money(sp[$0]?.expenses ?? 0) }),
            ("Profit", { Format.money(profit($0)) }),
        ]
        return [
            ReportWidget("Relationships & Advertising", span: 3, .table(columns: [
                Column("metric", ""), Column("personal", "Personal", right: true), Column("professional", "Professional", right: true),
                Column("internet", "Internet", right: true), Column("traditional", "Traditional", right: true),
            ], rows: metrics.map { m in
                var row: ReportRow = ["metric": .text(m.0)]
                for k in keys { row[k] = .text(m.1(k)) }
                return row
            }, total: nil, note: "Profit = income − estimated wages (hours × gross hourly rate) − expenses.")),
            ReportWidget("Income vs Cost", span: 3, .columns(series: ["Income", "Wages + expenses"], items: keys.map { k in
                let inc = sp[k]?.income ?? 0, cost = wages(k) + (sp[k]?.expenses ?? 0)
                return ColumnSeriesItem(label: SubPillar(rawValue: k)!.name.components(separatedBy: "– ").last!,
                                        values: [inc, cost], displays: [Format.moneyK(inc), Format.moneyK(cost)])
            })),
        ]
    }

    func overallReport(_ led: Ledger) -> [ReportWidget] {
        [monthlyAverages(led), ReportWidget("Totals", .stats([
            StatItem("Prospects", String(led.prospectCount)), StatItem("Closings", String(led.closingCount)),
            StatItem("Volume", Format.money(led.volume)), StatItem("Income", Format.money(led.incomeTotal)),
            StatItem("Expenses", Format.money(led.expensesTotal)), StatItem("Profit", Format.money(led.profit)),
        ]))]
    }

    func coachingReport(_ led: Ledger) -> [ReportWidget] {
        let guidance = [
            "Overall numbers: income, expenses, profit, conversion and hours per prospect and per closing are the foundation of next year's plan.",
            "Conversion: watch any category or activity with 2–3 prospects and no closings; 4 or more with none is a concern. Notice sources that send prospects who never convert.",
            "Closings and income: keep working where you close, and look at the pillars with the biggest average deal and the most income per closing.",
            "Activities: lower hours per prospect and per closing is better — move hours from inefficient pillars to the ones that close with less time.",
            "Profit and ROI: look for the pillars with the highest return on the time and money you invest.",
        ]
        return [ReportWidget("HERB's coaching for you", span: 2, .list(coach.insights().prefix(10).map {
            ListItem(title: $0.title, text: $0.text, level: $0.level)
        })), ReportWidget("How to read your numbers", .text(guidance, pageBreak: false))]
    }

    func businessPlanReport(_ led: Ledger) -> [ReportWidget] {
        let year = led.period.to.year
        let tr = PlanTracking(book, year: year, now: now)
        let inputs = book.plan(for: year), o = inputs.outputs
        let months = Ledger(book, period: Period(key: "year", label: String(year), from: Day(year, 1, 1), to: Day(year, 12, 31)), now: now).byMonth()
        let ytd = year == now.year ? ledger("ytd") : led
        return [
            ReportWidget("Business Plan Progress", span: 3, .progress(tr.items.map {
                ProgressItem(label: $0.label, actual: $0.actual, projected: $0.projected, goal: $0.goal, displayActual: $0.displayActual,
                             displayProjected: $0.displayProjected, displayGoal: $0.displayGoal, pacePct: $0.pacePct)
            })),
            ReportWidget("Month by Month", span: 3, .table(columns: [
                Column("month", "Month"), Column("income", "Income", right: true, .money), Column("planIncome", "Plan", right: true, .money),
                Column("profit", "Profit", right: true, .money), Column("planProfit", "Plan", right: true, .money),
                Column("closings", "Closings", right: true, .num), Column("planClosings", "Plan", right: true, .num1),
                Column("volume", "Volume", right: true, .money), Column("planVolume", "Plan", right: true, .money),
            ], rows: months.map { m in
                ["month": .text(m.label), "income": .number(m.income), "planIncome": .number(o.monthlyGross), "profit": .number(m.profit),
                 "planProfit": .number(o.monthlyNet), "closings": .number(Double(m.closings)), "planClosings": .number(o.monthlyTransactions),
                 "volume": .number(m.volume), "planVolume": .number(o.monthlyVolume)]
            }, total: nil, note: nil)),
            ReportWidget("Hourly Rates", .stats([
                StatItem("Projected gross", Format.money(o.hourlyGross), formula: "\(Format.money(inputs.grossIncomeGoal)) ÷ \(Format.num(o.annualWorkHours)) h"),
                StatItem("Actual gross", Format.money(ytd.hourlyGross), caption: "\(Format.pct(ytd.hourlyGross.flatMap { ratio($0, o.hourlyGross) })) of plan"),
                StatItem("Projected net", Format.money(o.hourlyNet)),
                StatItem("Actual net", Format.money(ytd.hourlyNet), caption: "\(Format.pct(ytd.hourlyNet.flatMap { ratio($0, o.hourlyNet) })) of plan"),
            ])),
            ReportWidget("Year-end Forecast", .stat(value: tr.forecast.value, display: Format.money(tr.forecast.value),
                                              caption: "Goal \(Format.money(inputs.grossIncomeGoal))",
                                              formula: "\(Format.money(tr.forecast.ytd)) YTD + \(Format.money(tr.forecast.pipeline)) pipeline + \(Format.money(tr.forecast.runRate)) run rate")),
        ]
    }

    func indexReport(_ led: Ledger) -> [ReportWidget] {
        [ReportWidget("Logsperity Index", .index(Coach.indexSummary(led))),
         ReportWidget("Index by Month (year to date through each month)", .bar(indexTrend(book, year: led.period.to.year, now: now).map {
             ChartItem($0.label, $0.value ?? 0, Format.num($0.value))
         }, horizontal: false)),
         ReportWidget("How the index works", .text([
             "Logsperity Index = 100 × [(0.5 × Net ROI + profit margin) ÷ 2.5 + conversion rate].",
             "100 is a healthy business: 30% conversion, 200% net ROI and 75% of gross income kept. Below 100 is weaker; above 100 is stronger.",
             "Yours: 100 × [(0.5 × \(Format.num(led.netROI, decimals: 2)) + \(Format.num(led.margin, decimals: 2))) ÷ 2.5 + \(Format.num(led.conversion, decimals: 2))] = \(Format.num(led.index, decimals: 1)).",
         ], pageBreak: false))]
    }

    func monthReport(_ led: Ledger) -> [ReportWidget] {
        if led.period.from > now {
            return [ReportWidget(led.period.label, .text(["This month hasn't started yet."], pageBreak: false))]
        }
        let prev = Ledger(book, period: led.period.previous, now: now)
        let one: (Double) -> String = { Format.num($0, decimals: 1) }
        let n: (Double) -> String = { Format.num($0) }
        let m: (Double) -> String = { Format.money($0) }
        let lines: [(String, Double, Double, (Double) -> String)] = [
            ("Prospects", Double(led.prospectCount), Double(prev.prospectCount), n),
            ("Closings", Double(led.closingCount), Double(prev.closingCount), n),
            ("Income", led.incomeTotal, prev.incomeTotal, m), ("Expenses", led.expensesTotal, prev.expensesTotal, m),
            ("Business-building hours", led.bbHours, prev.bbHours, one), ("Business miles", led.businessMiles, prev.businessMiles, n),
        ]
        return summaryWidgets(led) + [ReportWidget("Compared with \(prev.period.label)", span: 3, .table(columns: [
            Column("metric", "Metric"), Column("this", led.period.label, right: true), Column("prev", prev.period.label, right: true),
            Column("change", "Change", right: true),
        ], rows: lines.map { l in
            ["metric": .text(l.0), "this": .text(l.3(l.1)), "prev": .text(l.3(l.2)),
             "change": .text("\(l.1 - l.2 >= 0 ? "+" : "−")\(l.3(abs(l.1 - l.2)))")]
        }, total: nil, note: nil))]
    }

    // MARK: Annual report (§15.2)

    public func annualPages(year: Int, version: String = "complete") -> (title: String, pages: [(title: String, widgets: [ReportWidget])]) {
        let period = version == "ytd" || year == now.year
            ? Period(key: "ytd", label: "\(year) year to date", from: Day(year, 1, 1), to: min(Day(year, 12, 31), now))
            : try! Period.parse("year:\(year)", now: now)
        let led = Ledger(book, period: period, now: now)
        let plan = businessPlanReport(led)
        var pages: [(String, [ReportWidget])] = [
            ("\(year) Complete Report — Summary", summaryWidgets(led)),
            ("Business Plan Progress Tracker", [plan[0]] + plan.dropFirst(2)),
            ("Monthly Averages and Top Performers", [monthlyAverages(led), topPerformers(led)]),
            ("Input to Output", [inputOutput(led)]),
            ("\(year) Prospects Report", prospectsReport(led)),
            ("\(year) Closings Report", closingsReport(led)),
            ("\(year) Income Report", incomeReport(led)),
            ("\(year) Conversion Rate Report", conversionReport(led)),
            ("Source Conversion", sourceConversionReport(led)),
            ("\(year) Mileage Report", mileageReport(led)),
            ("\(year) Profit & Loss", pnlReport(led)),
            ("ROI by Pillar", profitROIReport(led)),
            ("Logsperity Index", indexReport(led)),
            ("Coaching Advice", coachingReport(led)),
            ("HERB's Year in Review", [yearInReview(led)]),
        ]
        if version == "streamlined" {
            pages = [0, 1, 2, 12, 13, 14].map { pages[$0] }
            pages[0].0 = "\(year) Streamlined Report — Summary"
        }
        let title = ["complete": "\(year) Complete Annual Report", "streamlined": "\(year) Streamlined Annual Report",
                     "ytd": "\(year) Annual Report — Year to Date"][version] ?? "\(year) Annual Report"
        return (title, pages)
    }

    func yearInReview(_ led: Ledger) -> ReportWidget {
        let ins = coach.insights()
        let wins = ins.filter { $0.level == .win }.prefix(2)
        let concerns = ins.filter { $0.level == .concern || $0.level == .watch }.prefix(3)
        let best = led.breakdown(.pillar).filter { $0.prospects > 0 }.max { ($0.conversion ?? 0) < ($1.conversion ?? 0) }
        var paras = ["You logged \(led.prospectCount) prospects and \(led.closingCount) closings for \(Format.money(led.incomeTotal)) of income and \(Format.money(led.profit)) of profit (\(Format.pct(led.margin)) margin). Your Logsperity Index is \(Format.num(led.index))."]
        if let best {
            paras.append("What worked: \(best.name) converted best at \(Format.pct(best.conversion)). " + wins.map(\.text).joined(separator: " "))
        }
        if !concerns.isEmpty { paras.append("What didn't: " + concerns.map(\.text).joined(separator: " ")) }
        let f = coach.focus()
        if !f.items.isEmpty {
            paras.append("For next year's plan: " + f.items.map(\.title).joined(separator: "; ") + (f.drop.map { "; and drop \($0.title)." } ?? "."))
        }
        return ReportWidget("HERB's Year in Review", span: 3, .text(paras, pageBreak: false))
    }

    func annualWidgets(_ version: String, year: Int) -> [ReportWidget] {
        annualPages(year: year, version: version).pages.flatMap { [ReportWidget($0.title, span: 3, .text([], pageBreak: true))] + $0.widgets }
    }

    // MARK: Registry and menu (§14.1)

    public static let titles: [String: String] = {
        var t: [String: String] = [
            "log_prospects": "Prospects Log", "log_closings": "Closings Log", "log_income": "Income Log",
            "log_expenses": "Expense Log", "log_trips": "Mileage Log", "log_activities": "Activity Log", "log_all": "All Logs",
            "quick_prospects": "Prospects", "quick_closings": "Closings", "quick_profit": "Profit",
            "quick_current_month": "Current Month", "quick_annual_ytd": "Annual Report YTD",
            "quick_annual_streamlined": "Annual Report Streamlined",
            "prospects": "Prospects Report", "conversion": "Conversion Rate Report", "source_conversion": "Source Conversion Report",
            "closings": "Closings Report", "income": "Income Report", "expenses": "Expense Report", "mileage": "Mileage Report",
            "activity": "Activity Report", "efficiency": "Efficiency Analysis", "input_output": "Input-to-Output Report",
            "pnl": "Profit & Loss (traditional)", "profit_roi": "Profit & ROI Report", "relationships_ads": "Relationships & Ads Report",
            "overall_stats": "Basic Overall Stats", "coaching_advice": "Coaching Advice", "business_plan": "Business Plan Report",
            "index": "Logsperity Index", "annual_ytd": "Annual Report YTD", "annual_streamlined": "Annual Report Streamlined",
            "annual_complete": "Annual Report Complete", "ytd": "Year to Date Report",
        ]
        for m in 1...12 { t[String(format: "month_%02d", m)] = "\(monthNames[m - 1]) Report" }
        return t
    }()

    public static let menu: [ReportMenuGroup] = {
        func items(_ keys: [String]) -> [(key: String, title: String)] { keys.map { ($0, titles[$0]!) } }
        return [
            ReportMenuGroup(id: "logs", title: "Logs", items: items(["log_prospects", "log_closings", "log_income", "log_expenses",
                                                                     "log_trips", "log_activities", "log_all"])),
            ReportMenuGroup(id: "quick", title: "Quick Stats", items: items(["quick_prospects", "quick_closings", "quick_profit",
                                                                             "quick_current_month", "quick_annual_ytd", "quick_annual_streamlined"])),
            ReportMenuGroup(id: "detailed", title: "Detailed Reports", items: items([
                "prospects", "conversion", "source_conversion", "closings", "income", "expenses", "mileage", "activity", "efficiency",
                "input_output", "pnl", "profit_roi", "relationships_ads", "overall_stats", "coaching_advice", "business_plan", "index",
                "annual_ytd", "annual_streamlined", "annual_complete"])),
            ReportMenuGroup(id: "monthly", title: "Monthly & YTD",
                            items: (1...12).map { (String(format: "month_%02d", $0), monthNames[$0 - 1]) } + [("ytd", "Year to Date")]),
        ]
    }()

    /// Builds one report. Monthly reports use the current year (or `year:YYYY` from the period key).
    public func build(_ key: String, periodKey: String? = nil) throws -> Report {
        guard let title = Self.titles[key] else { throw ReportError.unknownReport(key) }
        var pk = periodKey ?? "ytd"
        if key.hasPrefix("month_") {
            let y = periodKey.flatMap { $0.hasPrefix("year:") ? Int($0.dropFirst(5)) : nil } ?? now.year
            pk = "month:\(y)-\(key.dropFirst(6))"
        } else if ["ytd", "quick_annual_ytd", "quick_annual_streamlined", "annual_ytd"].contains(key) {
            pk = "ytd"
        }
        let led = try Ledger(book, periodKey: pk, now: now)
        let year = led.period.to.year
        let widgets: [ReportWidget]
        switch key {
        case "log_all": widgets = Self.logTitles.map { logWidget(led, $0.key) }
        case let k where k.hasPrefix("log_"): widgets = [logWidget(led, String(k.dropFirst(4)))]
        case "quick_prospects": widgets = Array(prospectsReport(led).prefix(2))
        case "quick_closings": widgets = Array(closingsReport(led).prefix(2))
        case "quick_profit": widgets = Array(profitROIReport(led).prefix(2))
        case "quick_current_month": widgets = summaryWidgets(ledger("month"))
        case "quick_annual_ytd", "ytd": widgets = summaryWidgets(led)
        case "quick_annual_streamlined": widgets = Array(summaryWidgets(led).prefix(6)) + [businessPlanReport(led)[0], topPerformers(led)]
        case "prospects": widgets = prospectsReport(led)
        case "conversion": widgets = conversionReport(led)
        case "source_conversion": widgets = sourceConversionReport(led)
        case "closings": widgets = closingsReport(led)
        case "income": widgets = incomeReport(led)
        case "expenses": widgets = expenseReport(led)
        case "mileage": widgets = mileageReport(led)
        case "activity": widgets = activityReport(led)
        case "efficiency": widgets = efficiencyReport(led)
        case "input_output": widgets = [inputOutput(led)]
        case "pnl": widgets = pnlReport(led)
        case "profit_roi": widgets = profitROIReport(led)
        case "relationships_ads": widgets = relationshipsAdsReport(led)
        case "overall_stats": widgets = overallReport(led)
        case "coaching_advice": widgets = coachingReport(led)
        case "business_plan": widgets = businessPlanReport(led)
        case "index": widgets = indexReport(led)
        case "annual_ytd": widgets = annualWidgets("ytd", year: year)
        case "annual_streamlined": widgets = annualWidgets("streamlined", year: year)
        case "annual_complete": widgets = annualWidgets("complete", year: year)
        default: widgets = monthReport(led)
        }
        return Report(key: key, title: title, period: led.period, widgets: widgets)
    }
}
