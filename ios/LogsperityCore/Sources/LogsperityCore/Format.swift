import Foundation

/// Display formats shared by reports and HERB (US English, like the simulator). nil shows as "—".
public enum Format {
    public static let dash = "—"

    static func grouped(_ x: Double, decimals: Int) -> String {
        let s = String(format: "%.\(decimals)f", abs(x))
        let parts = s.split(separator: ".", maxSplits: 1)
        var whole = String(parts[0])
        var out = ""
        while whole.count > 3 {
            out = "," + whole.suffix(3) + out
            whole.removeLast(3)
        }
        out = whole + out
        if parts.count == 2 { out += "." + parts[1] }
        return out
    }

    public static func money(_ x: Double?, cents: Bool = false) -> String {
        guard let x else { return dash }
        let s = "$" + grouped(x, decimals: cents ? 2 : 0)
        return x < 0 && s != "$0" ? "-" + s : s
    }

    /// Compact money for tiles: $7.73M, $644.2k, $9,500.
    public static func moneyK(_ x: Double?) -> String {
        guard let x else { return dash }
        if abs(x) >= 1_000_000 { return String(format: "$%.2fM", x / 1_000_000) }
        if abs(x) >= 10_000 { return String(format: "$%.1fk", x / 1000) }
        return money(x)
    }

    public static func pct(_ x: Double?, decimals: Int = 0) -> String {
        guard let x else { return dash }
        return String(format: "%.\(decimals)f%%", x * 100)
    }

    public static func num(_ x: Double?, decimals: Int = 0) -> String {
        guard let x else { return dash }
        return (x < 0 ? "-" : "") + grouped(x, decimals: decimals)
    }

    public static func hours(_ x: Double?) -> String {
        guard let x else { return dash }
        return grouped(x, decimals: 1) + " h"
    }

    public static func miles(_ x: Double?) -> String {
        guard let x else { return dash }
        return grouped(x, decimals: 1) + " mi"
    }

    /// "Oct 30" or "Oct 30, 2026".
    public static func shortDate(_ d: Day, withYear: Bool = false) -> String {
        let s = "\(monthAbbreviations[d.month - 1]) \(d.day)"
        return withYear ? s + ", \(d.year)" : s
    }

    /// "Monday, Nov 2".
    public static func spokenDate(_ d: Day) -> String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return "\(names[d.weekday]), \(shortDate(d))"
    }
}

public func ratio(_ a: Double, _ b: Double) -> Double? { b != 0 ? a / b : nil }
