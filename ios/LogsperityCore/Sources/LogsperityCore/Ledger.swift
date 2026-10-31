import Foundation

/// A dimension to break the logs down by.
public enum Dimension: String, CaseIterable, Sendable {
    case pillar, subPillar, category, activity, source
}

/// One row of a breakdown: everything Logsperity measures for one pillar, category, activity or source.
public struct BreakdownRow: Hashable, Sendable {
    public var key: String?
    public var name: String
    public var pillar: Pillar?
    public var prospects = 0
    public var closings = 0
    public var volume = 0.0
    public var closingIncome = 0.0
    public var income = 0.0
    public var hours = 0.0
    public var expenses = 0.0

    public var conversion: Double? { ratio(Double(closings), Double(prospects)) }
    public var avgVolume: Double? { ratio(volume, Double(closings)) }
    public var avgIncome: Double? { ratio(closingIncome, Double(closings)) }
    public var incomePerHour: Double? { ratio(income, hours) }
    public var hoursPerProspect: Double? { ratio(hours, Double(prospects)) }
    public var hoursPerClosing: Double? { ratio(hours, Double(closings)) }
}

/// Profit and ROI for one pillar, the overhead row or the total (design §11.5).
public struct ROIRow: Hashable, Sendable {
    public var key: String
    public var name: String
    public var income: Double
    public var expenses: Double
    public var hours: Double
    public var wages: Double
    public var margin: Double?
    public var roi: Double?
    public var roiWithTime: Double?
    public var label = ""

    public var profit: Double { income - expenses }
    public var capital: Double { expenses + wages }
    public var profitWithTime: Double { income - capital }
}

public struct MonthRow: Hashable, Sendable {
    public var month: String
    public var label: String
    public var prospects = 0
    public var closings = 0
    public var volume = 0.0
    public var income = 0.0
    public var expenses = 0.0
    public var miles = 0.0
    public var deduction = 0.0
    public var bbHours = 0.0
    public var profit: Double { income - expenses }
}

/// All six logs for one period, with the §11 metrics. The Swift twin of the simulator's `calc.Ledger`.
public struct Ledger: Sendable {
    public let period: Period
    public let now: Day
    public let book: LogBook
    public let prospects: [ProspectRecord]
    public let closings: [ClosingRecord]
    public let income: [IncomeRecord]
    public let expenses: [ExpenseRecord]
    public let trips: [TripRecord]
    public let activities: [ActivityRecord]
    public let plan: PlanInputs
    public let planOutputs: PlanOutputs

    public init(_ book: LogBook, period: Period, now: Day) {
        self.period = period
        self.now = now
        self.book = book
        prospects = book.prospects.filter { period.contains($0.date) }.sorted { $0.date < $1.date }
        closings = book.closings.filter { period.contains($0.date) }.sorted { $0.date < $1.date }
        income = book.income.filter { period.contains($0.date) }.sorted { $0.date < $1.date }
        expenses = book.expenses.filter { period.contains($0.date) }.sorted { $0.date < $1.date }
        trips = book.trips.filter { period.contains($0.date) }.sorted { $0.date < $1.date }
        activities = book.activities.filter { period.contains($0.date) }.sorted { $0.date < $1.date }
        plan = book.plan(for: period.to.year)
        planOutputs = plan.outputs
    }

    public init(_ book: LogBook, periodKey: String = "ytd", now: Day) throws {
        self.init(book, period: try Period.parse(periodKey, now: now), now: now)
    }

    // MARK: Counts and totals (§11.2)

    public var prospectCount: Int { prospects.count }
    public var closingCount: Int { closings.count }
    public var volume: Double { closings.reduce(0) { $0 + $1.transactionSize } }
    public var closingIncome: Double { closings.reduce(0) { $0 + $1.income } }
    public var incomeTotal: Double { income.reduce(0) { $0 + $1.amount } }
    public var nonTransactionIncome: Double { income.filter { $0.mode != .transaction }.reduce(0) { $0 + $1.amount } }
    public var cashExpenses: Double { expenses.reduce(0) { $0 + $1.amount } }
    public var businessTrips: [TripRecord] { trips.filter(\.isBusiness) }
    public var businessMiles: Double { businessTrips.reduce(0) { $0 + $1.miles } }
    public var mileageDeduction: Double {
        businessTrips.reduce(0) { $0 + $1.miles * Taxonomy.mileageRate(on: $1.date) }
    }
    public var expensesTotal: Double { cashExpenses + mileageDeduction }
    public var bbHours: Double { Double(activities.reduce(0) { $0 + $1.minutes }) / 60 }

    /// Total work hours from the plan, pro-rated to the part of the period up to today (issue I13).
    public var workHours: Double {
        let end = min(period.to, now)
        if end < period.from { return 0 }
        let days = Double(period.from.days(to: end) + 1)
        return planOutputs.annualWorkHours * days / Double(Day.daysInYear(period.from.year))
    }

    // MARK: Conversion and efficiency (§11.3, §11.4)

    public var conversion: Double? { ratio(Double(closingCount), Double(prospectCount)) }
    public var avgVolume: Double? { ratio(volume, Double(closingCount)) }
    public var avgClosingIncome: Double? { ratio(closingIncome, Double(closingCount)) }
    public var hoursPerProspect: Double? { ratio(bbHours, Double(prospectCount)) }
    public var hoursPerClosing: Double? { ratio(bbHours, Double(closingCount)) }
    public var profit: Double { incomeTotal - expensesTotal }
    public var margin: Double? { ratio(profit, incomeTotal) }
    public var hourlyGross: Double? { ratio(incomeTotal, workHours) }
    public var hourlyNet: Double? { ratio(profit, workHours) }
    public var incomePerBBHour: Double? { ratio(incomeTotal, bbHours) }
    public var profitPerBBHour: Double? { ratio(profit, bbHours) }
    public var bbHoursPerWeek: Double {
        let end = min(period.to, now)
        let weeks = max(1.0 / 7, Double(period.from.days(to: end) + 1) / 7)
        return bbHours / weeks
    }

    // MARK: Profit and ROI (§11.5)

    public var wagesInvested: Double { bbHours * (hourlyGross ?? 0) }
    public var netROI: Double? {
        let capital = expensesTotal + wagesInvested
        return ratio(incomeTotal - capital, capital)
    }
    public var index: Double? { logsperityIndex(netROI: netROI, margin: margin, conversion: conversion) }

    // MARK: Breakdowns

    public func name(for dim: Dimension, key: String?) -> String {
        guard let key else { return dim == .source ? "Unknown" : "Unassigned" }  // D3: Unknown is its own line
        switch dim {
        case .pillar: return Pillar(rawValue: key)?.name ?? key
        case .subPillar: return SubPillar(rawValue: key)?.name ?? key
        case .category: return Taxonomy.categoryByID[key]?.name ?? key
        case .activity: return Taxonomy.activityByID[key]?.name ?? key
        case .source: return book.sourceName(key) ?? "Unknown"
        }
    }

    private static func key(_ a: Attribution, _ dim: Dimension) -> String? {
        switch dim {
        case .pillar: a.pillar?.rawValue
        case .subPillar: a.subPillar?.rawValue
        case .category: a.categoryID
        case .activity: a.activityID
        case .source: a.sourceID
        }
    }

    /// Per-item prospects, closings, conversion, volume, income, hours and expenses for one dimension.
    public func breakdown(_ dim: Dimension) -> [BreakdownRow] {
        // Optional keys: nil groups items with no value ("Unassigned"/"Unknown").
        var acc: [String?: BreakdownRow] = [:]
        func row(_ k: String?) -> BreakdownRow { acc[k] ?? BreakdownRow(key: k, name: name(for: dim, key: k)) }
        for p in prospects {
            let k = Self.key(p.attribution, dim)
            var r = row(k); r.prospects += 1; acc[k] = r
        }
        for c in closings {
            let k = Self.key(c.attribution, dim)
            var r = row(k); r.closings += 1; r.volume += c.transactionSize; r.closingIncome += c.income; acc[k] = r
        }
        for i in income {
            guard let k = Self.key(i.attribution, dim) else { continue }
            var r = row(k); r.income += i.amount; acc[k] = r
        }
        if dim != .category {
            for a in activities {
                let k = Self.key(a.attribution, dim)
                var r = row(k); r.hours += Double(a.minutes) / 60; acc[k] = r
            }
        }
        for e in expenses {
            let k: String?
            switch dim {
            case .pillar: k = e.pillar?.rawValue
            case .subPillar: guard let sp = e.subPillar else { continue }; k = sp.rawValue
            case .source: guard let s = e.sourceID else { continue }; k = s
            default: continue
            }
            var r = row(k); r.expenses += e.amount; acc[k] = r
        }
        var out = Array(acc.values)
        for i in out.indices {
            if dim == .category { out[i].pillar = out[i].key.flatMap { Taxonomy.categoryByID[$0]?.pillar } }
            if dim == .activity { out[i].pillar = out[i].key.flatMap { Taxonomy.activityByID[$0]?.pillar } }
        }
        switch dim {
        case .pillar:
            out.removeAll { $0.key == nil }  // overhead expenses are reported separately
            for p in Pillar.allCases where !out.contains(where: { $0.key == p.rawValue }) {
                out.append(BreakdownRow(key: p.rawValue, name: p.name))
            }
            let order = Pillar.allCases.map(\.rawValue)
            out.sort { order.firstIndex(of: $0.key!)! < order.firstIndex(of: $1.key!)! }
            for i in out.indices { out[i].pillar = Pillar(rawValue: out[i].key!) }
        case .subPillar:
            out.removeAll { $0.key == nil }
            for s in SubPillar.allCases where !out.contains(where: { $0.key == s.rawValue }) {
                out.append(BreakdownRow(key: s.rawValue, name: s.name))
            }
            let order = SubPillar.allCases.map(\.rawValue)
            out.sort { (order.firstIndex(of: $0.key!) ?? 9) < (order.firstIndex(of: $1.key!) ?? 9) }
        default:
            out.sort { ($0.prospects, $0.closings, $1.name) > ($1.prospects, $1.closings, $0.name) }
        }
        return out
    }

    public var overheadExpenses: Double {
        expenses.filter { $0.pillar == nil }.reduce(0) { $0 + $1.amount } + mileageDeduction
    }

    /// §11.5 per pillar, plus an overhead row (issue I3) and the overall total.
    public func pillarROI() -> [ROIRow] {
        let hg = hourlyGross ?? 0
        var rows: [ROIRow] = breakdown(.pillar).map { r in
            let wages = r.hours * hg
            let capital = r.expenses + wages
            return ROIRow(key: r.key!, name: r.name, income: r.income, expenses: r.expenses, hours: r.hours,
                          wages: wages, margin: ratio(r.income - r.expenses, r.income),
                          roi: ratio(r.income - r.expenses, r.expenses),
                          roiWithTime: ratio(r.income - capital, capital))
        }
        let unattributed = incomeTotal - rows.reduce(0) { $0 + $1.income }
        let ranked = rows.filter { $0.roiWithTime != nil }
        if ranked.count >= 2 {
            let best = ranked.max { $0.roiWithTime! < $1.roiWithTime! }!.key
            let worst = ranked.min { $0.roiWithTime! < $1.roiWithTime! }!.key
            for i in rows.indices { rows[i].label = rows[i].key == best ? "Best" : rows[i].key == worst ? "Worst" : "" }
        }
        rows.append(ROIRow(key: "overhead", name: "Overhead & unassigned income", income: unattributed,
                           expenses: overheadExpenses, hours: 0, wages: 0, margin: nil, roi: nil, roiWithTime: nil))
        rows.append(ROIRow(key: "total", name: "Total", income: incomeTotal, expenses: expensesTotal, hours: bbHours,
                           wages: wagesInvested, margin: margin, roi: ratio(profit, expensesTotal),
                           roiWithTime: netROI))
        return rows
    }

    // MARK: Time series

    public var months: [(year: Int, month: Int)] { period.months(now: now) }

    public func byMonth() -> [MonthRow] {
        months.map { y, m in
            let key = String(format: "%04d-%02d", y, m)
            var r = MonthRow(month: key, label: monthAbbreviations[m - 1])
            r.prospects = prospects.filter { $0.date.monthKey == key }.count
            let cl = closings.filter { $0.date.monthKey == key }
            r.closings = cl.count
            r.volume = cl.reduce(0) { $0 + $1.transactionSize }
            r.income = income.filter { $0.date.monthKey == key }.reduce(0) { $0 + $1.amount }
            let tr = trips.filter { $0.date.monthKey == key && $0.isBusiness }
            r.miles = tr.reduce(0) { $0 + $1.miles }
            r.deduction = tr.reduce(0) { $0 + $1.miles * Taxonomy.mileageRate(on: $1.date) }
            r.expenses = expenses.filter { $0.date.monthKey == key }.reduce(0) { $0 + $1.amount } + r.deduction
            r.bbHours = Double(activities.filter { $0.date.monthKey == key }.reduce(0) { $0 + $1.minutes }) / 60
            return r
        }
    }

    /// Months from the first month with data to the end of the period (issue I5: not always 12).
    public var monthsInUse: Int {
        let ms = byMonth()
        if let first = ms.firstIndex(where: { $0.prospects > 0 || $0.closings > 0 || $0.income != 0 || $0.expenses != 0 || $0.bbHours > 0 }) {
            return ms.count - first
        }
        return max(1, ms.count)
    }
}

// MARK: - Logsperity Index (§12)

/// 100 × [(0.5 × Net ROI + margin) ÷ 2.5 + conversion]; 100 = healthy (200% ROI, 75% kept, 30% conversion).
public func logsperityIndex(netROI: Double?, margin: Double?, conversion: Double?) -> Double? {
    guard let netROI, let margin, let conversion else { return nil }
    return 100 * ((0.5 * netROI + margin) / 2.5 + conversion)
}

public enum IndexBenchmark {
    public static let conversion = 0.30
    public static let netROI = 2.0
    public static let margin = 0.75
}

/// The index for year-to-date through each month (cumulative, so it's stable).
public func indexTrend(_ book: LogBook, year: Int, now: Day) -> [(month: String, label: String, value: Double?)] {
    var out: [(String, String, Double?)] = []
    for m in 1...12 {
        if Day(year, m, 1) > now { break }
        let p = Period(key: "custom", label: monthAbbreviations[m - 1], from: Day(year, 1, 1),
                       to: min(Day.monthEnd(year, m), now))
        out.append((String(format: "%04d-%02d", year, m), monthAbbreviations[m - 1], Ledger(book, period: p, now: now).index))
    }
    return out
}
