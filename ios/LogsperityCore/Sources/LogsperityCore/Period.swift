import Foundation

public let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                         "October", "November", "December"]
public let monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

public enum PeriodError: Error, Equatable {
    case unknown(String)
}

/// A date range for reports and calculations. Keys match the simulator's `period` query parameter:
/// `ytd` · `month` · `month:YYYY-MM` · `q:YYYY-N` · `year:YYYY` · `last30` · `custom:YYYY-MM-DD:YYYY-MM-DD`.
public struct Period: Hashable, Sendable {
    public let key: String
    public let label: String
    public let from: Day
    public let to: Day

    public init(key: String, label: String, from: Day, to: Day) {
        self.key = key
        self.label = label
        self.from = from
        self.to = to
    }

    public var days: Int { from.days(to: to) + 1 }
    public func contains(_ d: Day) -> Bool { from <= d && d <= to }

    public static func parse(_ key: String? = nil, now: Day) throws -> Period {
        let key = (key ?? "ytd").trimmingCharacters(in: .whitespaces)
        func ints(_ s: Substring) -> [Int]? {
            let parts = s.split(separator: "-").map { Int($0) }
            return parts.contains(nil) ? nil : parts.compactMap { $0 }
        }
        switch key {
        case "ytd":
            return Period(key: key, label: "\(now.year) year to date", from: now.startOfYear, to: now)
        case "month":
            return Period(key: key, label: "\(monthNames[now.month - 1]) \(now.year) to date",
                          from: now.startOfMonth, to: now)
        case "last30":
            return Period(key: key, label: "Last 30 days", from: now.adding(days: -29), to: now)
        default: break
        }
        if key.hasPrefix("month:"), let v = ints(key.dropFirst(6)), v.count == 2, (1...12).contains(v[1]) {
            return Period(key: key, label: "\(monthNames[v[1] - 1]) \(v[0])", from: Day(v[0], v[1], 1),
                          to: .monthEnd(v[0], v[1]))
        }
        if key.hasPrefix("q:"), let v = ints(key.dropFirst(2)), v.count == 2, (1...4).contains(v[1]) {
            let m0 = 3 * (v[1] - 1) + 1
            return Period(key: key, label: "Q\(v[1]) \(v[0])", from: Day(v[0], m0, 1), to: .monthEnd(v[0], m0 + 2))
        }
        if key.hasPrefix("year:"), let y = Int(key.dropFirst(5)) {
            return Period(key: key, label: String(y), from: Day(y, 1, 1), to: Day(y, 12, 31))
        }
        if key.hasPrefix("custom:") {
            let parts = key.split(separator: ":")
            if parts.count == 3, var a = Day(iso: String(parts[1])), var b = Day(iso: String(parts[2])) {
                if b < a { swap(&a, &b) }
                return Period(key: key, label: "\(Format.shortDate(a, withYear: true)) – \(Format.shortDate(b, withYear: true))",
                              from: a, to: b)
            }
        }
        throw PeriodError.unknown(key)
    }

    /// Same-length period immediately before this one (months map to the previous month).
    public var previous: Period {
        if key == "month" || key.hasPrefix("month:") {
            let prevLast = from.adding(days: -1)
            return Period(key: "month:\(prevLast.monthKey)", label: "\(monthNames[prevLast.month - 1]) \(prevLast.year)",
                          from: prevLast.startOfMonth, to: prevLast)
        }
        let to = from.adding(days: -1)
        return Period(key: "custom", label: "Previous period", from: to.adding(days: -(days - 1)), to: to)
    }

    public var sameLastYear: Period {
        func back(_ d: Day) -> Day {
            d.month == 2 && d.day == 29 ? Day(d.year - 1, 2, 28) : Day(d.year - 1, d.month, d.day)
        }
        return Period(key: "custom", label: "Same period \(from.year - 1)", from: back(from), to: back(to))
    }

    /// Month starts covered by the period, clipped to `now` for current periods.
    public func months(now: Day) -> [(year: Int, month: Int)] {
        let end = min(to, max(now, from))
        var out: [(Int, Int)] = []
        var (y, m) = (from.year, from.month)
        while Day(y, m, 1) <= end {
            out.append((y, m))
            m += 1
            if m == 13 { (y, m) = (y + 1, 1) }
        }
        return out
    }

    /// Standard choices for period pickers.
    public static func pickerChoices(now: Day) -> [(key: String, label: String)] {
        let q = (now.month - 1) / 3 + 1
        return [("month", "This month"), ("month:\(now.adding(days: -now.day).monthKey)", "Last month"),
                ("q:\(now.year)-\(q)", "This quarter"), ("ytd", "Year to date"), ("last30", "Last 30 days"),
                ("year:\(now.year - 1)", "Last year")]
    }
}
