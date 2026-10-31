import Foundation

/// The Quick Reference Guide's logging rules (design §5), enforced in code so users don't have to remember them.
public enum LogRuleError: Error, Equatable, CustomStringConvertible {
    case prospectAlreadyClosed(name: String)
    case missing(String)

    public var description: String {
        switch self {
        case .prospectAlreadyClosed(let name):
            "\(name) already has a closing. Log later transactions for this client as income (repeat client)."
        case .missing(let field): "\(field) is required."
        }
    }
}

public enum LogRules {
    /// Activity time is logged in 15-minute steps (FR-23). Rounds to the nearest step, at least 15 minutes.
    public static func roundMinutes(_ minutes: Int) -> Int {
        max(15, Int((Double(minutes) / 15).rounded(.toNearestOrEven)) * 15)
    }

    /// R6: a trip's beginning odometer defaults to the previous trip's ending.
    public static func defaultOdometerStart(for date: Day, trips: [TripRecord]) -> Double? {
        trips.filter { $0.odometerEnd != nil && $0.date <= date }
            .max { ($0.date, $0.odometerEnd!) < ($1.date, $1.odometerEnd!) }?.odometerEnd
    }

    /// R5: one closing per prospect (keeps conversion honest; the 2018 sample showed 300%).
    public static func checkOneClosing(prospect: ProspectRecord, closings: [ClosingRecord], editing: RecordID? = nil) throws {
        if closings.contains(where: { $0.prospectID == prospect.id && $0.id != editing }) {
            throw LogRuleError.prospectAlreadyClosed(name: prospect.fullName)
        }
    }

    /// Builds a closing from a prospect, carrying over its attribution (FR-15).
    public static func closing(from prospect: ProspectRecord, date: Day, transactionSize: Double, income: Double) -> ClosingRecord {
        var c = ClosingRecord(date: date)
        c.prospectID = prospect.id
        c.attribution = prospect.attribution
        c.transactionSize = transactionSize
        c.income = income
        return c
    }

    /// "Add to Income Log?" yes (FR-16) and R3's additional transactions: the income rows a closing creates.
    /// The first is linked to the closing; additional transactions are income, not extra closings.
    public static func incomeRows(for closing: ClosingRecord, lastName: String?, addToIncome: Bool,
                                  additional: [(transactionSize: Double, income: Double)] = []) -> [IncomeRecord] {
        var rows: [IncomeRecord] = []
        func row(size: Double, amount: Double, linked: Bool) -> IncomeRecord {
            var i = IncomeRecord(date: closing.date)
            i.mode = .transaction
            i.closingID = linked ? closing.id : nil
            i.attribution = closing.attribution
            i.transactionCount = 1
            i.transactionSize = size
            i.lastName = lastName
            i.amount = amount
            return i
        }
        if addToIncome { rows.append(row(size: closing.transactionSize, amount: closing.income, linked: true)) }
        for a in additional { rows.append(row(size: a.transactionSize, amount: a.income, linked: false)) }
        return rows
    }

    /// R2: a referral from a past client goes under Clients, keeping the first source as "originally from".
    public static func applyPastClientReferral(_ p: inout ProspectRecord, referrerIsPastClient: Bool) {
        guard referrerIsPastClient else { return }
        if p.attribution.pillar != .clients { p.originallyFromSourceID = p.originallyFromSourceID ?? p.attribution.sourceID }
        p.attribution.pillar = .clients
        p.attribution.subPillar = .clients
        p.attribution.categoryID = "cat.past_client"
    }

    /// The default follow-up from a lead's strength (design §17.2 rule 5): hot → next business day, medium → 3 days,
    /// cold → 2 weeks, each rolled past a weekend; no-go → none. Same rule HERB uses.
    public static func defaultFollowUp(strength: Strength?, from d: Day) -> Day? {
        let days: Int
        switch strength {
        case .redHot, .hot: days = 1
        case .cold: days = 14
        case .noGo: return nil
        default: days = 3
        }
        var n = d.adding(days: days)
        while n.weekday >= 5 { n = n.adding(days: 1) }
        return n
    }

    public static func nextBusinessDay(after d: Day) -> Day {
        var n = d.adding(days: 1)
        while n.weekday >= 5 { n = n.adding(days: 1) }
        return n
    }
}
