import Foundation

/// A calendar date with no time or time zone, like the simulator's ISO `YYYY-MM-DD` strings.
/// Arithmetic uses day numbers, so results never shift with the phone's time zone.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`; returns nil for anything else or an impossible date.
    public init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...Day.daysInMonth(y, m)).contains(d) else { return nil }
        self.init(y, m, d)
    }

    /// Today's date in the given calendar (the phone's, by default).
    public static func today(calendar: Calendar = .current) -> Day { Day(date: Date(), calendar: calendar) }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(c.year!, c.month!, c.day!)
    }

    /// Midnight at the start of this day in the given calendar.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }
    /// `YYYY-MM`, used to bucket rows by month.
    public var monthKey: String { String(format: "%04d-%02d", year, month) }

    public static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }
    public static func daysInYear(_ y: Int) -> Int { isLeap(y) ? 366 : 365 }
    public static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return isLeap(y) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
    public static func monthEnd(_ y: Int, _ m: Int) -> Day { Day(y, m, daysInMonth(y, m)) }

    /// Days since 1970-01-01 (proleptic Gregorian).
    public var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public init(ordinal z0: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    public func adding(days n: Int) -> Day { Day(ordinal: ordinal + n) }
    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: Day) -> Int { other.ordinal - ordinal }
    /// 0 = Monday … 6 = Sunday, like Python's `weekday()`.
    public var weekday: Int { ((ordinal % 7) + 7 + 3) % 7 }
    public var startOfYear: Day { Day(year, 1, 1) }
    public var startOfMonth: Day { Day(year, month, 1) }

    public static func < (a: Day, b: Day) -> Bool { a.ordinal < b.ordinal }
}
