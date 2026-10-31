import Foundation

/// The 2018 model's 12 scorecard tabs as one generic pivot (design §13):
/// rows = items of a dimension, columns = months, value = a measure.
public struct Scorecard: Sendable {
    public enum Log: String, Sendable { case prospects, closings, income, expenses, activities }
    public enum Measure: String, Sendable { case quantity, income, volume, amount, minutes }
    public enum Dim: String, Sendable { case pillar, subPillar, category, activity, source, irs, group, type }

    public struct Row: Hashable, Sendable {
        public let key: String?
        public let name: String
        public let subPillar: SubPillar?
        public let values: [Double]
        public var total: Double { values.reduce(0, +) }
    }

    public let period: Period
    public let months: [String]
    public let rows: [Row]
    public let subPillarTotals: [SubPillar: Double]
    public var total: Double { rows.reduce(0) { $0 + $1.total } }

    public init(_ book: LogBook, log: Log, measure: Measure, dimension: Dim, periodKey: String = "ytd", now: Day) throws {
        let led = try Ledger(book, periodKey: periodKey, now: now)
        period = led.period
        let months = led.months.map { String(format: "%04d-%02d", $0.year, $0.month) }
        self.months = months

        // (date, attribution-ish fields, value) for each row of the chosen log
        typealias Item = (date: Day, key: String?, value: Double)
        func attr(_ a: Attribution) -> String? {
            switch dimension {
            case .pillar: a.pillar?.rawValue
            case .subPillar: a.subPillar?.rawValue
            case .category: a.categoryID
            case .activity: a.activityID
            case .source: a.sourceID
            default: nil
            }
        }
        let items: [Item]
        switch log {
        case .prospects:
            items = led.prospects.map { ($0.date, attr($0.attribution), 1) }
        case .closings:
            items = led.closings.map { c in
                (c.date, attr(c.attribution), measure == .income ? c.income : measure == .volume ? c.transactionSize : 1)
            }
        case .income:
            items = led.income.map { i in
                (i.date, dimension == .type ? i.type?.rawValue : attr(i.attribution), measure == .quantity ? 1 : i.amount)
            }
        case .expenses:
            items = led.expenses.map { e in
                let key: String? = switch dimension {
                case .irs: e.irs
                case .group: e.group.rawValue
                case .pillar: e.pillar?.rawValue
                case .subPillar: e.subPillar?.rawValue
                case .category: e.categoryID
                case .source: e.sourceID
                default: nil
                }
                return (e.date, key, measure == .quantity ? 1 : e.amount)
            }
        case .activities:
            items = led.activities.map { ($0.date, attr($0.attribution), measure == .quantity ? 1 : Double($0.minutes)) }
        }

        var acc: [String?: [Double]] = [:]
        var order: [String?] = []
        for it in items {
            guard let mi = months.firstIndex(of: it.date.monthKey) else { continue }
            if acc[it.key] == nil { acc[it.key] = Array(repeating: 0, count: months.count); order.append(it.key) }
            acc[it.key]![mi] += it.value
        }
        var rows: [Row] = order.map { k in
            let name: String
            var sp: SubPillar?
            switch dimension {
            case .irs: name = k ?? "Other"
            case .type: name = k.flatMap { IncomeType(rawValue: $0)?.name } ?? k ?? "Transaction"
            case .group: name = k.flatMap { ExpenseGroup(rawValue: $0)?.name } ?? k ?? ""
            case .pillar: name = led.name(for: .pillar, key: k)
            case .subPillar: name = led.name(for: .subPillar, key: k)
            case .category:
                name = led.name(for: .category, key: k)
                sp = k.flatMap { Taxonomy.categoryByID[$0]?.subPillar }
            case .activity:
                name = led.name(for: .activity, key: k)
                sp = k.flatMap { Taxonomy.activityByID[$0]?.subPillar }
            case .source: name = led.name(for: .source, key: k)
            }
            return Row(key: k, name: name, subPillar: sp, values: acc[k]!)
        }
        rows.sort { $0.total > $1.total }
        self.rows = rows
        var sub: [SubPillar: Double] = [:]
        for r in rows { if let s = r.subPillar { sub[s, default: 0] += r.total } }
        subPillarTotals = sub
    }
}
