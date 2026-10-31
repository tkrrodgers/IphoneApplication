import Foundation

// Plain value types for the six logs (design §18; simulator schema in CONTRACT.md). The app stores these in
// SwiftData and hands snapshots to the engine, so every calculation is testable without a database.
// Money is in dollars. IDs are UUID strings, so records sync through iCloud without collisions.

public typealias RecordID = String

public func newRecordID() -> RecordID { UUID().uuidString }

/// Where a prospect, closing, income entry or activity came from (design §4).
public struct Attribution: Hashable, Codable, Sendable {
    public var pillar: Pillar?
    public var subPillar: SubPillar?
    public var categoryID: String?
    public var activityID: String?
    public var sourceID: RecordID?

    public init(pillar: Pillar? = nil, subPillar: SubPillar? = nil, categoryID: String? = nil,
                activityID: String? = nil, sourceID: RecordID? = nil) {
        self.pillar = pillar
        self.subPillar = subPillar
        self.categoryID = categoryID
        self.activityID = activityID
        self.sourceID = sourceID
    }

    /// Fills in pillar and sub-pillar from the category or activity when they're missing.
    public func normalized() -> Attribution {
        var a = self
        let item = categoryID.flatMap { Taxonomy.categoryByID[$0] } ?? activityID.flatMap { Taxonomy.activityByID[$0] }
        if a.subPillar == nil, let item, a.pillar == nil || a.pillar == item.pillar { a.subPillar = item.subPillar }
        if a.pillar == nil { a.pillar = a.subPillar?.pillar ?? item?.pillar }
        return a
    }
}

public struct SourceRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: RecordID
    public var name: String
    public var kind: String?  // person | company | venue | online

    public init(id: RecordID = newRecordID(), name: String, kind: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// "Zillow" and "zillow.com" are the same source (issue I8).
    public static func normalize(_ name: String) -> String {
        var s = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [".com", ".net", ".org"] where s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        return s.filter { $0.isLetter || $0.isNumber }
    }
}

public struct ProspectRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: RecordID = newRecordID()
    public var date: Day
    public var firstNames = ""
    public var lastName = ""
    public var phone1: String?
    public var phone1Type: String?
    public var phone2: String?
    public var phone2Type: String?
    public var email1: String?
    public var email2: String?
    public var address: String?
    public var zip: String?
    public var city: String?
    public var state: String?
    public var attribution = Attribution()
    public var originallyFromSourceID: RecordID?
    public var strength: Strength?
    public var planOfAction: String?
    public var followUp: Day?
    public var notes: String?
    public var capture: Capture = .manual
    public var reviewed = true

    public init(date: Day) { self.date = date }

    public var fullName: String { [firstNames, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

public struct ClosingRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: RecordID = newRecordID()
    public var date: Day
    public var prospectID: RecordID?
    public var attribution = Attribution()
    public var transactionSize: Double = 0
    public var income: Double = 0
    public var referralRequest: ReferralRequest = .no
    public var postClosingFollowUp: Day?
    public var notes: String?
    public var capture: Capture = .manual
    public var reviewed = true

    public init(date: Day) { self.date = date }
}

public struct IncomeRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: RecordID = newRecordID()
    public var date: Day
    public var mode: IncomeMode = .type
    public var closingID: RecordID?
    public var attribution = Attribution()
    public var type: IncomeType?
    public var transactionCount: Int?
    public var transactionSize: Double?
    public var lastName: String?
    public var amount: Double = 0
    public var payer: String?
    public var expect1099 = true
    public var notes: String?
    public var capture: Capture = .manual
    public var reviewed = true

    public init(date: Day) { self.date = date }
}

public struct ExpenseRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: RecordID = newRecordID()
    public var date: Day
    public var vendor = ""
    public var amount: Double = 0
    public var group: ExpenseGroup = .general
    public var relationshipSubPillar: SubPillar?  // personal | professional (fixes issue I4)
    public var categoryID = ""
    public var sourceID: RecordID?
    public var checkNumber: String?
    public var cardLast4: String?
    public var purpose: String?
    public var withWhom: String?
    public var hasReceipt = false
    public var notes: String?
    public var capture: Capture = .manual
    public var reviewed = true

    public init(date: Day) { self.date = date }

    public var category: ExpenseCategory? { Taxonomy.expenseCategoryByID[categoryID] }
    public var irs: String { category?.irs ?? "Other" }
    public var pillar: Pillar? { group.pillar }
    public var subPillar: SubPillar? {
        switch group {
        case .clients: .clients
        case .adInternet: .internet
        case .adTraditional: .traditional
        case .prospecting: .prospecting
        case .relationships: relationshipSubPillar
        default: nil
        }
    }
}

public struct TripRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: RecordID = newRecordID()
    public var date: Day
    public var reason = ""
    public var destination = ""
    public var odometerStart: Double?
    public var odometerEnd: Double?
    public var gpsMiles: Double?
    public var isBusiness = true
    public var activityID: String?
    public var sourceID: RecordID?
    public var notes: String?
    public var capture: Capture = .manual
    public var reviewed = true

    public init(date: Day) { self.date = date }

    public var miles: Double {
        if let gpsMiles { return gpsMiles }
        guard let s = odometerStart, let e = odometerEnd else { return 0 }
        return max(0, e - s)
    }
}

public struct ActivityRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: RecordID = newRecordID()
    public var date: Day
    public var attribution = Attribution()
    public var minutes = 0
    public var notes: String?
    public var capture: Capture = .manual
    public var reviewed = true

    public init(date: Day) { self.date = date }
}

/// Business Plan Set Up inputs for one year (design §9.1).
public struct PlanInputs: Hashable, Codable, Sendable {
    public var grossIncomeGoal: Double
    public var netProfitGoal: Double
    public var avgCommission: Double
    public var avgTransactionSize: Double
    public var hoursPerWeek: Double
    public var vacationWeeks: Double

    public init(grossIncomeGoal: Double, netProfitGoal: Double, avgCommission: Double, avgTransactionSize: Double,
                hoursPerWeek: Double, vacationWeeks: Double) {
        self.grossIncomeGoal = grossIncomeGoal
        self.netProfitGoal = netProfitGoal
        self.avgCommission = avgCommission
        self.avgTransactionSize = avgTransactionSize
        self.hoursPerWeek = hoursPerWeek
        self.vacationWeeks = vacationWeeks
    }

    /// The 2018 model's example plan, used until the user sets their own.
    public static let `default` = PlanInputs(grossIncomeGoal: 150_000, netProfitGoal: 125_000, avgCommission: 6_500,
                                             avgTransactionSize: 335_000, hoursPerWeek: 40, vacationWeeks: 0)
}

/// Everything the engine needs: the six logs, sources and plans. The app builds one from SwiftData.
public struct LogBook: Codable, Sendable {
    public var prospects: [ProspectRecord] = []
    public var closings: [ClosingRecord] = []
    public var income: [IncomeRecord] = []
    public var expenses: [ExpenseRecord] = []
    public var trips: [TripRecord] = []
    public var activities: [ActivityRecord] = []
    public var sources: [SourceRecord] = []
    public var plans: [Int: PlanInputs] = [:]

    public init() {}

    public func plan(for year: Int) -> PlanInputs { plans[year] ?? .default }
    public func sourceName(_ id: RecordID?) -> String? { id.flatMap { id in sources.first { $0.id == id }?.name } }
}
