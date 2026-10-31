import Foundation

// Logsperity taxonomy: pillars, categories, activities, expense categories and pick lists (design §4,
// Appendix A and B). IDs are stable slugs so names can be corrected without breaking history. They match
// the simulator's `taxonomy.py` exactly, so data and tests carry over.

public enum Pillar: String, CaseIterable, Codable, Sendable, Identifiable {
    case clients, relationships, advertising, prospecting
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .clients: "Clients"
        case .relationships: "Relationships"
        case .advertising: "Advertising"
        case .prospecting: "Prospecting"
        }
    }
}

public enum SubPillar: String, CaseIterable, Codable, Sendable, Identifiable {
    case clients, personal, professional, internet, traditional, prospecting
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .clients: "Clients"
        case .personal: "Relationships – Personal"
        case .professional: "Relationships – Professional"
        case .internet: "Advertising – Internet"
        case .traditional: "Advertising – Traditional"
        case .prospecting: "Prospecting"
        }
    }
    public var pillar: Pillar {
        switch self {
        case .clients: .clients
        case .personal, .professional: .relationships
        case .internet, .traditional: .advertising
        case .prospecting: .prospecting
        }
    }
}

public struct TaxonomyItem: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let pillar: Pillar
    public let subPillar: SubPillar
}

public enum ExpenseGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    case clients, relationships
    case adInternet = "ad_internet", adTraditional = "ad_traditional"
    case prospecting, general
    case selfImprovement = "self_improvement"
    case technology, travel
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .clients: "Clients"
        case .relationships: "Relationships"
        case .adInternet: "Advertising – Internet"
        case .adTraditional: "Advertising – Traditional"
        case .prospecting: "Prospecting"
        case .general: "General"
        case .selfImprovement: "Self-Improvement"
        case .technology: "Technology"
        case .travel: "Travel"
        }
    }
    /// nil for the four "No Pillar" overhead groups.
    public var pillar: Pillar? {
        switch self {
        case .clients: .clients
        case .relationships: .relationships
        case .adInternet, .adTraditional: .advertising
        case .prospecting: .prospecting
        case .general, .selfImprovement, .technology, .travel: nil
        }
    }
}

public struct ExpenseCategory: Hashable, Sendable, Identifiable {
    public let id: String
    public let group: ExpenseGroup
    public let name: String
    public let irs: String
}

public enum Strength: String, CaseIterable, Codable, Sendable, Identifiable {
    case redHot = "red_hot", hot, medium, cold
    case noGo = "no_go"
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .redHot: "Red Hot"
        case .hot: "Hot"
        case .medium: "Medium"
        case .cold: "Cold"
        case .noGo: "No Go"
        }
    }
    public var colorHex: String {
        switch self {
        case .redHot: "#C2412D"
        case .hot: "#E8792B"
        case .medium: "#C98A12"
        case .cold: "#3B6FB6"
        case .noGo: "#7A7A7A"
        }
    }
    /// Probability a prospect closes, used for forecasts and focus.
    public var closeProbability: Double {
        switch self {
        case .redHot: 0.6
        case .hot: 0.4
        case .medium: 0.2
        case .cold: 0.08
        case .noGo: 0
        }
    }
}

public enum IncomeMode: String, CaseIterable, Codable, Sendable {
    case transaction, batch, type
}

public enum IncomeType: String, CaseIterable, Codable, Sendable, Identifiable {
    case commission
    case consultingFees = "consulting_fees"
    case profitSharing = "profit_sharing"
    case bonuses
    case baseWages = "base_wages"
    case allowance
    case referralFees = "referral_fees"
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .commission: "Commission"
        case .consultingFees: "Consulting Fees"
        case .profitSharing: "Profit Sharing"
        case .bonuses: "Bonuses/Incentives"
        case .baseWages: "Base Wages"
        case .allowance: "Allowance"
        case .referralFees: "Referral Fees"
        }
    }
}

public enum ReferralRequest: String, CaseIterable, Codable, Sendable, Identifiable {
    case yes, no
    case ask7 = "ask_7", ask14 = "ask_14", ask21 = "ask_21", ask30 = "ask_30", ask45 = "ask_45"
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        default: "Ask in \(askInDays!) days"
        }
    }
    public var askInDays: Int? {
        switch self {
        case .ask7: 7
        case .ask14: 14
        case .ask21: 21
        case .ask30: 30
        case .ask45: 45
        default: nil
        }
    }
}

public enum Capture: String, CaseIterable, Codable, Sendable {
    case manual, voice, receipt, gps, calendar, bank
}

public enum Taxonomy {
    public static let version = 1

    public static func slug(_ name: String) -> String {
        var out = ""
        var pendingUnderscore = false
        for ch in name.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                if pendingUnderscore && !out.isEmpty { out.append("_") }
                pendingUnderscore = false
                out.append(ch)
            } else {
                pendingUnderscore = true
            }
        }
        return out
    }

    private static let categoryNames: KeyValuePairs<SubPillar, [String]> = [
        .clients: ["Past Client", "Current Client", "Prospective Client"],
        .personal: ["Family", "Friend", "Social Group", "Church", "School", "Sports", "Alumni Group"],
        .professional: ["Accountant", "Appraiser", "Architect", "Attorney", "Banker", "Business Coach",
                        "Consultant", "Contractor", "Dentist", "Designer", "Doctor", "Engineer",
                        "Escrow Officer", "Financial Planner", "Insurance Agent", "Insurance Company",
                        "Lender", "Realtor", "Salesperson", "Therapist", "Vendor"],
        .internet: ["Website-Personal", "Website-Blog", "Website-Free", "Website-Paid", "Website-Video Site"],
        .traditional: ["Article", "Billboard", "Car Wrap", "Door Hanger", "Flyer", "Lead Generator",
                       "Magazine", "Mailer/Farming", "Newsletter", "Newspaper", "Promotion", "Radio",
                       "Sign", "Sponsorship", "Swag", "TV"],
        .prospecting: ["Cold Calls", "Committee", "Door Knocking", "Expired Listings", "Floor Time",
                       "Office Visits", "Open House", "Organization", "Network-Open Group", "Seminar",
                       "Trade Show"],
    ]

    private static let activityNames: KeyValuePairs<SubPillar, [String]> = [
        .clients: ["Past Client Interaction", "Current Client Interaction", "Marketing for Current Client",
                   "Prospective Client Interaction", "Client Appreciation Party", "Database Marketing",
                   "Email Campaigning", "Facebook Marketing", "Mail Campaigning", "Newsletter Campaigning",
                   "Personal Visit", "Twitter Marketing"],
        .personal: ["Relationship Building-Personal", "Community Involvement-Personal", "Socializing"],
        .professional: ["Relationship Building-Professional", "Networking-Closed Group", "Partner Coaching",
                        "Committee Involvement", "Organization Involvement",
                        "Community Involvement-Professional"],
        .internet: ["Website Set Up", "Blog Development", "Website Ad Set Up-Free", "Website Ad Set Up-Paid",
                    "Video Production"],
        .traditional: ["Article Writing", "Billboard Ad Set Up", "Car Wrap Set Up", "Door Hanger Set Up",
                       "Flyer Set Up", "Lead Generation", "Magazine Ad Set Up", "Mail Campaigning",
                       "Newsletter Set Up", "Newspaper Ad Set Up", "Promotion Set Up", "Radio Ad Set Up",
                       "Sign Set Up", "Sponsorship Set Up", "Swag Set Up", "TV Ad Set Up"],
        .prospecting: ["Cold Calling", "Committee Involvement", "Door Knocking", "Expired Listings Calling",
                       "Floor Time", "Office Visits", "Open Houses", "Organization Involvement",
                       "Networking-Open Group", "Seminar", "Trade Show"],
    ]

    private static func build(prefix: String, _ table: KeyValuePairs<SubPillar, [String]>) -> [TaxonomyItem] {
        var counts: [String: Int] = [:]
        for (_, items) in table { for n in items { counts[n, default: 0] += 1 } }
        var out: [TaxonomyItem] = []
        for (sub, items) in table {
            for n in items {
                var id = "\(prefix).\(slug(n))"
                if counts[n]! > 1 { id += ".\(sub.pillar.rawValue)" }  // duplicate names get a pillar suffix
                out.append(TaxonomyItem(id: id, name: n, pillar: sub.pillar, subPillar: sub))
            }
        }
        return out
    }

    public static let categories = build(prefix: "cat", categoryNames)
    public static let activities = build(prefix: "act", activityNames)
    public static let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    public static let activityByID = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })

    public static func categories(in pillar: Pillar) -> [TaxonomyItem] { categories.filter { $0.pillar == pillar } }
    public static func activities(in pillar: Pillar) -> [TaxonomyItem] { activities.filter { $0.pillar == pillar } }

    public static let irsCategories = ["Advertising", "Car & Truck", "Commissions/Fees", "Insurance",
                                       "Interest-Other", "Legal/Professional", "Office", "Meals/Entertainment",
                                       "Rent", "Repairs", "Supplies", "Taxes", "Travel", "Utilities", "Wages",
                                       "Other"]

    private static let expenseTable: KeyValuePairs<ExpenseGroup, [(String, String)]> = {
        let a = "Advertising", o = "Other", m = "Meals/Entertainment"
        return [
            .clients: [("Database Marketing", a), ("Client Appreciation Party", a), ("Client Refund", o),
                       ("Closing Gift", a), ("Entertainment", m), ("Mailers", a), ("Meal", m), ("Newsletter", a),
                       ("Printing", o), ("Referral Fee", a), ("Thank You Gifts", a)],
            .relationships: [("Database Marketing", a), ("Entertainment", m), ("Mailers", a), ("Meal", m),
                             ("Networking Dues", a), ("Newsletter", a), ("Printing", o), ("Referral Fee", a),
                             ("Thank You Gifts", a)],
            .adInternet: ["Domain Registration", "Internet Provider", "Website Ad", "Web Developer", "Web Hosting",
                          "Video Production"].map { ($0, a) },
            .adTraditional: ["Billboard Ad", "Car Wrap", "Flyer Set Up", "Lead Generation", "Promotion Set Up",
                             "Magazine Ad", "Mailers", "Mailing Cost", "Newsletter", "Newspaper Ad", "Radio Ad",
                             "Signs", "Sponsorship", "Swag", "TV Ad"].map { ($0, a) } + [("Printing", o)],
            .prospecting: [("Leave Behind Material", a), ("Seminar Production", a), ("Staging", a),
                           ("Trade Show", a), ("Printing", o)],
            .general: [("Bank Charges", o), ("Clothing", o), ("Donation", o), ("Drycleaning", o), ("Dues", o),
                       ("Equipment", "Office"), ("Insurance", "Insurance"), ("Legal", "Legal/Professional"),
                       ("License", o), ("Membership", o), ("Office Fees", "Office"), ("Office Supplies", "Office"),
                       ("Phone", o), ("Photography", a), ("Postage", o), ("Printing", o),
                       ("Professional Services", "Legal/Professional"), ("Repairs", "Repairs"),
                       ("Shipping", "Office"), ("Subscription", o), ("Tax Preparation", "Legal/Professional"),
                       ("Wages", "Wages")],
            .selfImprovement: [("Coaching Fees", "Legal/Professional"), ("Education", o), ("Event", o),
                               ("Marketing Consultant", "Legal/Professional"), ("Seminar", o), ("Training", o)],
            .technology: [("Data Storage", "Office"), ("Internet Provider", a), ("Software", o), ("Technology", o)],
            .travel: [("Car Expenses", "Car & Truck"), ("Car Wash", "Car & Truck"), ("Lodging", "Travel"),
                      ("Meal", "Travel"), ("Transportation", "Travel")],
        ]
    }()

    public static let expenseCategories: [ExpenseCategory] = expenseTable.flatMap { group, items in
        items.map { ExpenseCategory(id: "exp.\(group.rawValue).\(slug($0.0))", group: group, name: $0.0, irs: $0.1) }
    }
    public static let expenseCategoryByID = Dictionary(uniqueKeysWithValues: expenseCategories.map { ($0.id, $0) })
    public static func expenseCategories(in group: ExpenseGroup) -> [ExpenseCategory] {
        expenseCategories.filter { $0.group == group }
    }

    public static let planOfAction = ["Call", "Email", "Mail Business Cards", "Mail Letter", "Mail Information",
                                      "Mail Promotion", "Mail Newsletter", "Add to Database", "Add to Email Campaign",
                                      "Add to Phone Campaign", "Add to Mail Campaign", "Visit", "Refer to Other",
                                      "Refer to Notes", "Nothing Now"]
    public static let followUpDays = [5, 7, 10, 15, 21, 30, 45, 60, 75, 90, 120, 180, 250, 365]
    public static let professions = ["Accountant", "Appraiser", "Architect", "Attorney", "Banker", "Business Coach",
                                     "Consultant", "Contractor", "Dentist", "Designer", "Doctor", "Engineer",
                                     "Escrow Officer", "Financial Planner", "Insurance Agent", "Lender", "Realtor",
                                     "Salesperson", "Therapist", "Other"]
    public static let phoneTypes = ["Mobile", "Work", "Home", "Other"]
    public static let mileageReasons = ["Past Client Interaction", "Current Client Interaction",
                                        "Prospective Client Interaction", "Personal Visit",
                                        "Relationship Building-Personal", "Relationship Building-Professional",
                                        "Community Involvement-Personal", "Community Involvement-Professional",
                                        "Socializing", "Networking-Closed Group", "Networking-Open Group",
                                        "Partner Coaching", "Committee Involvement", "Organization Involvement",
                                        "Door Knocking", "Office Visits", "Open Houses", "Seminar", "Trade Show",
                                        "Closing", "Title Company", "Office"]

    /// IRS standard mileage rates by date (dollars per mile).
    public static let mileageRates: [(from: Day, to: Day, rate: Double)] = [
        (Day(2025, 1, 1), Day(2025, 12, 31), 0.70),
        (Day(2026, 1, 1), Day(2026, 6, 30), 0.725),
        (Day(2026, 7, 1), Day(2026, 12, 31), 0.76),
    ]

    public static func mileageRate(on d: Day) -> Double {
        if let r = mileageRates.first(where: { $0.from <= d && d <= $0.to }) { return r.rate }
        return d > mileageRates.last!.to ? mileageRates.last!.rate : mileageRates.first!.rate
    }
}
