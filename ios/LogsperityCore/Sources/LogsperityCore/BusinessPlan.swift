import Foundation

public enum PlanError: Error, Equatable {
    case netExceedsGross
}

/// "This Is Your Business" — the calculated side of Business Plan Set Up (design §9.2).
public struct PlanOutputs: Hashable, Sendable {
    public let monthlyGross: Double
    public let monthlyNet: Double
    public let annualExpenses: Double
    public let monthlyExpenses: Double
    public let yieldPct: Double
    public let annualTransactions: Double
    public let monthlyTransactions: Double
    public let annualVolume: Double
    public let monthlyVolume: Double
    public let annualWorkHours: Double
    public let hourlyGross: Double
    public let hourlyNet: Double

    public init(_ i: PlanInputs) {
        let tx = ratio(i.grossIncomeGoal, i.avgCommission) ?? 0
        let workHours = (52 - i.vacationWeeks) * i.hoursPerWeek
        monthlyGross = i.grossIncomeGoal / 12
        monthlyNet = i.netProfitGoal / 12
        annualExpenses = i.grossIncomeGoal - i.netProfitGoal
        monthlyExpenses = annualExpenses / 12
        yieldPct = ratio(i.avgCommission, i.avgTransactionSize) ?? 0
        annualTransactions = tx
        monthlyTransactions = tx / 12
        annualVolume = tx * i.avgTransactionSize
        monthlyVolume = annualVolume / 12
        annualWorkHours = workHours
        hourlyGross = ratio(i.grossIncomeGoal, workHours) ?? 0
        hourlyNet = ratio(i.netProfitGoal, workHours) ?? 0
    }
}

extension PlanInputs {
    public var outputs: PlanOutputs { PlanOutputs(self) }

    public func validate() throws {
        if netProfitGoal > grossIncomeGoal { throw PlanError.netExceedsGross }
    }
}

/// §9.3: continue the chain past transactions using the user's own rates.
public struct PlanExtended: Hashable, Sendable {
    public let conversion: Double?
    public let prospectsNeeded: Double?
    public let prospectsPerWeek: Double?
    public let hoursPerProspect: Double?
    public let bbHoursNeeded: Double?
    public let bbHoursPerWeek: Double?

    public init(inputs: PlanInputs, ledger: Ledger) {
        let conv = ledger.conversion
        let hpp = ledger.hoursPerProspect
        let weeks = max(1, 52 - inputs.vacationWeeks)
        let needed = conv.flatMap { $0 > 0 ? inputs.outputs.annualTransactions / $0 : nil }
        let bb = needed.flatMap { n in hpp.map { n * $0 } }
        conversion = conv
        prospectsNeeded = needed
        prospectsPerWeek = needed.map { $0 / weeks }
        hoursPerProspect = hpp
        bbHoursNeeded = bb
        bbHoursPerWeek = bb.map { $0 / weeks }
    }
}

/// Fraction of the plan year elapsed (replaces the 2018 "put a 1 in each month", issue I6).
public func elapsedFraction(year: Int, now: Day) -> Double {
    if year < now.year { return 1 }
    if year > now.year { return 0 }
    return Double(Day(year, 1, 1).days(to: now) + 1) / Double(Day.daysInYear(year))
}
