import Foundation

/// Business plan tracking (design §11.6): current vs projected-to-date vs annual goal.
public struct PlanTracking: Sendable {
    public struct Item: Hashable, Sendable {
        public let key: String
        public let label: String
        public let actual: Double
        public let projected: Double
        public let goal: Double
        public var pacePct: Double? { ratio(actual, projected) }
        public let displayActual: String
        public let displayProjected: String
        public let displayGoal: String
    }

    public struct Forecast: Hashable, Sendable {
        public let value: Double
        public let ytd: Double
        public let pipeline: Double
        public let runRate: Double
    }

    public let year: Int
    public let elapsedFraction: Double
    public let items: [Item]
    public let forecast: Forecast

    public init(_ book: LogBook, year: Int? = nil, now: Day) {
        let year = year ?? now.year
        let inputs = book.plan(for: year)
        let out = inputs.outputs
        let frac = LogsperityCore.elapsedFraction(year: year, now: now)
        let led = Ledger(book, period: Period(key: "ytd", label: String(year), from: Day(year, 1, 1),
                                              to: min(Day(year, 12, 31), now)), now: now)
        self.year = year
        elapsedFraction = frac
        let txFormat: (Double) -> String = { Format.num($0, decimals: $0.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1) }
        let spec: [(String, String, Double, Double, (Double) -> String)] = [
            ("income", "Income", led.incomeTotal, inputs.grossIncomeGoal, { Format.money($0) }),
            ("profit", "Profit", led.profit, inputs.netProfitGoal, { Format.money($0) }),
            ("closings", "Transactions", Double(led.closingCount), out.annualTransactions, txFormat),
            ("volume", "Volume", led.volume, out.annualVolume, { Format.moneyK($0) }),
        ]
        items = spec.map { key, label, actual, goal, fmt in
            let proj = goal * frac
            return Item(key: key, label: label, actual: actual, projected: proj, goal: goal,
                        displayActual: fmt(actual), displayProjected: fmt(proj), displayGoal: fmt(goal))
        }
        forecast = Self.forecastIncome(book, ledger: led, now: now)
    }

    public func item(_ key: String) -> Item? { items.first { $0.key == key } }

    /// Year-end forecast = YTD + open pipeline (by strength) + half of the trailing 8-week run rate.
    static func forecastIncome(_ book: LogBook, ledger led: Ledger, now: Day) -> Forecast {
        let remainingDays = Double(max(0, now.days(to: Day(now.year, 12, 31))))
        let avgIncome = led.avgClosingIncome ?? led.plan.avgCommission
        let closed = Set(book.closings.compactMap(\.prospectID))
        let since = now.adding(days: -120)
        let open = book.prospects.filter { !closed.contains($0.id) && $0.date >= since }
        let pipeline = open.reduce(0) { $0 + ($1.strength?.closeProbability ?? 0.1) } * avgIncome * 0.5
        let recent = Ledger(book, period: Period(key: "custom", label: "8w", from: now.adding(days: -55), to: now),
                            now: now).incomeTotal
        let run = recent / 56 * remainingDays * 0.5
        return Forecast(value: led.incomeTotal + pipeline + run, ytd: led.incomeTotal, pipeline: pipeline, runRate: run)
    }
}
