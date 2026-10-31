import Foundation

// Report widgets (CONTRACT.md "Widget JSON"): every report, the Coach screen and the Annual Report are lists
// of these. The app draws each kind once; the engine decides what goes in them.

public enum ValueFormat: String, Sendable {
    case money, money0, pct, num, num1, hours, miles, text

    public func format(_ v: Double?) -> String {
        switch self {
        case .money, .money0: Format.money(v)
        case .pct: Format.pct(v)
        case .num: Format.num(v)
        case .num1: Format.num(v, decimals: 1)
        case .hours: Format.hours(v)
        case .miles: Format.miles(v)
        case .text: v.map { String($0) } ?? Format.dash
        }
    }
}

/// A table cell: text shown as is, or a number formatted by its column.
public enum Cell: Hashable, Sendable {
    case text(String)
    case number(Double?)

    public func display(_ format: ValueFormat?) -> String {
        switch self {
        case .text(let s): s
        case .number(let v): (format ?? .num).format(v)
        }
    }
}

public struct Column: Hashable, Sendable {
    public let key: String
    public let label: String
    public let alignRight: Bool
    public let format: ValueFormat?

    public init(_ key: String, _ label: String, right: Bool = false, _ format: ValueFormat? = nil) {
        self.key = key
        self.label = label
        alignRight = right
        self.format = format
    }
}

public typealias TableRow = [String: Cell]

public struct StatItem: Hashable, Sendable {
    public let label: String
    public let display: String
    public let caption: String?
    public let formula: String?

    public init(_ label: String, _ display: String, caption: String? = nil, formula: String? = nil) {
        self.label = label
        self.display = display
        self.caption = caption
        self.formula = formula
    }
}

public struct ChartItem: Hashable, Sendable {
    public enum Role: String, Sendable { case profit, expense }
    public let label: String
    public let value: Double
    public let display: String
    public let role: Role?

    public init(_ label: String, _ value: Double, _ display: String, role: Role? = nil) {
        self.label = label
        self.value = value
        self.display = display
        self.role = role
    }
}

public struct ProgressItem: Hashable, Sendable {
    public let label: String
    public let actual: Double
    public let projected: Double
    public let goal: Double
    public let displayActual: String
    public let displayProjected: String
    public let displayGoal: String
    public let pacePct: Double?
}

public struct IndexDriver: Hashable, Sendable {
    public let key: String
    public let label: String
    public let value: Double?
    public let display: String
    public let benchmarkDisplay: String
    /// Value ÷ healthy benchmark (1.0 = at the benchmark).
    public let ratio: Double?
}

public struct IndexSummary: Hashable, Sendable {
    public let value: Double?
    public let display: String
    public let label: String
    public let drivers: [IndexDriver]
}

public enum InsightLevel: String, Sendable, Comparable {
    case concern, watch, win, info

    var rank: Int { [.concern: 0, .watch: 1, .win: 2, .info: 3][self]! }
    public static func < (a: InsightLevel, b: InsightLevel) -> Bool { a.rank < b.rank }
}

public struct ListItem: Hashable, Sendable {
    public let title: String
    public let text: String
    public let level: InsightLevel?
}

public struct ColumnSeriesItem: Hashable, Sendable {
    public let label: String
    public let values: [Double]
    public let displays: [String]
}

public struct Widget: Identifiable, Sendable {
    public enum Content: Sendable {
        case stat(value: Double?, display: String, caption: String?, formula: String?)
        case stats([StatItem])
        case table(columns: [Column], rows: [TableRow], total: TableRow?, note: String?)
        case bar([ChartItem], horizontal: Bool)
        case pie([ChartItem], center: String?, caption: String?)
        case stack([ChartItem])
        case progress([ProgressItem])
        case index(IndexSummary)
        case text([String], pageBreak: Bool)
        case list([ListItem])
        case columns(series: [String], items: [ColumnSeriesItem])
    }

    public let id = UUID()
    public let title: String
    /// Grid columns on a wide page (1–3); phones show one per row.
    public let span: Int
    public let content: Content

    public init(_ title: String, span: Int = 1, _ content: Content) {
        self.title = title
        self.span = span
        self.content = content
    }
}
