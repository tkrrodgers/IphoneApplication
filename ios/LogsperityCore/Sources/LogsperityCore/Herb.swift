import Foundation

// HERB, the assistant (design §6, §16, §17): the public entry point and the types the app sees.
// Swift port of herb-sim/herb.py (parsing and intents) and dialog.py (follow-up questions, §17.2).
//
// Pure and deterministic: the engine reads a LogBook snapshot and never changes it. Anything to save comes back
// as `LogChange`s for the app to apply (then build the next `Herb` from the updated book). The conversation
// state travels with each turn (`HerbDialogState`), so the app can keep it on the device or in Siri's context.
// Code computes, HERB narrates: every number in a reply comes from the Ledger and is formatted with `Format`.

// MARK: Values

/// A JSON-like value: the draft's fields and HERB's notes about the conversation, kept loosely typed so the
/// dialog policy can tell "not said" (absent) from "said: none" (`.null`), as the simulator does.
public enum HerbValue: Hashable, Sendable, Codable, ExpressibleByStringLiteral, ExpressibleByFloatLiteral,
                       ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case list([HerbValue])
    case object([String: HerbValue])

    public init(stringLiteral v: String) { self = .string(v) }
    public init(floatLiteral v: Double) { self = .number(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(nilLiteral: ()) { self = .null }
    public init(_ s: String?) { self = s.map { .string($0) } ?? .null }
    public init(_ x: Double?) { self = x.map { .number($0) } ?? .null }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var number: Double? { if case .number(let x) = self { x } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var list: [HerbValue]? { if case .list(let l) = self { l } else { nil } }
    public var object: [String: HerbValue]? { if case .object(let o) = self { o } else { nil } }

    /// Python truthiness.
    public var truthy: Bool {
        switch self {
        case .null: false
        case .bool(let b): b
        case .number(let x): x != 0
        case .string(let s): !s.isEmpty
        case .list(let l): !l.isEmpty
        case .object(let o): !o.isEmpty
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let x = try? c.decode(Double.self) { self = .number(x) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let l = try? c.decode([HerbValue].self) { self = .list(l) }
        else { self = .object(try c.decode([String: HerbValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let x): try c.encode(x)
        case .string(let s): try c.encode(s)
        case .list(let l): try c.encode(l)
        case .object(let o): try c.encode(o)
        }
    }
}

public typealias HerbFields = [String: HerbValue]

extension Dictionary where Key == String, Value == HerbValue {
    func str(_ k: String) -> String? { self[k]?.string }
    /// The string when it's non-empty (Python's `d.get(k)` used as a condition).
    func text(_ k: String) -> String? { self[k]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    func num(_ k: String) -> Double? { self[k]?.number }
    func has(_ k: String) -> Bool { self[k]?.truthy ?? false }
    func day(_ k: String) -> Day? { self[k]?.string.flatMap { Day(iso: $0) } }
    func strings(_ k: String) -> [String] { self[k]?.list?.compactMap(\.string) ?? [] }
    mutating func setDefault(_ k: String, _ v: HerbValue) { if self[k] == nil { self[k] = v } }
}

// MARK: Settings and state

/// How many follow-up questions HERB asks (design §17.2 "Question style").
public enum HerbQuestionStyle: String, Codable, Sendable, CaseIterable {
    case quick, balanced, thorough
}

/// The owner's HERB preferences. HERB updates the learned-skip fields itself (`HerbReply.settings`).
public struct HerbSettings: Hashable, Codable, Sendable {
    public var questionStyle: HerbQuestionStyle
    /// Used in greetings ("Hi Marcus").
    public var ownerFirstName: String?
    /// Fills in the state when an address names only a city.
    public var homeState: String?
    /// Optional fields skipped in a row (reset when the user gives one).
    public var skipCounts: [String: Int]
    /// Fields HERB stopped offering after three skips ("I notice you usually skip addresses…").
    public var neverAsk: [String]

    public init(questionStyle: HerbQuestionStyle = .balanced, ownerFirstName: String? = nil, homeState: String? = nil,
                skipCounts: [String: Int] = [:], neverAsk: [String] = []) {
        self.questionStyle = questionStyle
        self.ownerFirstName = ownerFirstName
        self.homeState = homeState
        self.skipCounts = skipCounts
        self.neverAsk = neverAsk
    }
}

/// The question HERB is waiting on.
public struct HerbPending: Hashable, Codable, Sendable {
    /// value · choice · default · offer · confirm · change · next · chainOffer
    public var type: String
    /// The field being asked for.
    public var slot: String?
    /// The fields in a grouped offer ("address and phone number?").
    public var slots: [String]?
    /// The suggested default (a follow-up date or an income estimate).
    public var value: HerbValue?
    var say: String?

    init(_ type: String, slot: String? = nil, slots: [String]? = nil, value: HerbValue? = nil) {
        self.type = type
        self.slot = slot
        self.slots = slots
        self.value = value
    }

    /// What the reply reports: the question without its text or default.
    var brief: HerbPending { HerbPending(type, slot: slot, slots: slots) }
}

/// One lead after another (a batch, or the leads an activity produced).
struct HerbChain: Hashable, Codable, Sendable {
    var total: Int?
    var i: Int
    var saved: Int
    var defaults: HerbFields
    var known: [String]
}

/// A conversation in progress (nil = none). Opaque to the app: store it and send it back with the next turn.
public struct HerbDialogState: Hashable, Codable, Sendable {
    var v = 1
    var log: String
    var frame: String
    var id: RecordID?
    var data: HerbFields
    var meta: HerbFields
    var known: [String]
    var skipped: [String] = []
    var queue: [String] = []
    var offered: [String] = []
    var pending: HerbPending?
    var turns = 0
    var tries = 0
    var chain: HerbChain?
    var queued: String?

    init(log: String, frame: String? = nil, data: HerbFields = [:], known: [String] = [], meta: HerbFields = [:]) {
        self.log = log
        self.frame = frame ?? log
        self.data = data
        self.meta = meta
        self.known = known
    }

    /// The question HERB asked last.
    public var pendingQuestion: HerbPending? { pending?.brief }
}

// MARK: Replies

public enum HerbIntent: String, Codable, Sendable {
    case help, review, focus, report, pace, index, conversion, efficiency, roi, plan, smalltalk, unknown
    case followUps = "follow_ups", sourcesNoClose = "sources_no_close", topSources = "top_sources"
    case incomeSummary = "income_summary", expensesSummary = "expenses_summary", mileageSummary = "mileage_summary"
    case logTrip = "log_trip", logClosing = "log_closing", logExpense = "log_expense", logIncome = "log_income"
    case logProspect = "log_prospect", logActivity = "log_activity", updateProspect = "update_prospect"

    public var isLog: Bool { rawValue.hasPrefix("log_") }
}

public enum HerbLog: String, Codable, Sendable, CaseIterable {
    case prospects, closings, income, expenses, trips, activities
}

/// Somewhere the app should open.
public enum HerbTarget: Hashable, Sendable {
    case report(String)
    case emailReport(String)
    case receiptScanner
    case today
    case review
    case businessPlan

    /// The simulator's target string ("report:month_03", "expense:scan").
    public var key: String {
        switch self {
        case .report(let k): "report:\(k)"
        case .emailReport(let k): "email:\(k)"
        case .receiptScanner: "expense:scan"
        case .today: "today"
        case .review: "review"
        case .businessPlan: "plan"
        }
    }
}

/// A quick-reply button.
public struct HerbAction: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Send this text as the user's next turn.
        case reply(String)
        /// Open the draft in its form (with everything filled in).
        case editDraft
        case open(HerbTarget)
        /// Show/speak this text without a new turn (simulated actions like "Draft texts").
        case say(String)
    }
    public let label: String
    public let kind: Kind

    public init(_ label: String, _ kind: Kind) {
        self.label = label
        self.kind = kind
    }

    static func reply(_ label: String, _ text: String? = nil) -> HerbAction { HerbAction(label, .reply(text ?? label)) }
}

public struct HerbCard: Hashable, Sendable {
    public let title: String
    public let subtitle: String?
    public let value: String?
    public let chip: String?

    public init(title: String, subtitle: String? = nil, value: String? = nil, chip: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.chip = chip
    }
}

/// One line of the draft card. `asking` marks the field HERB is asking about.
public struct HerbSummaryRow: Hashable, Sendable {
    public let label: String
    public let value: String
    public let asking: Bool
}

/// The record being built. Nothing is saved until the user says yes (or taps Save → `Herb.confirm`).
public struct HerbDraft: Hashable, Sendable {
    public let log: HerbLog
    /// Set when the draft updates an existing record.
    public let recordID: RecordID?
    /// The fields as HERB has them (camelCase, like the simulator's API).
    public let data: HerbFields
    public let summary: [HerbSummaryRow]
}

/// What the app should do with the trip tracker.
public enum HerbTripCommand: Hashable, Sendable {
    case start(destination: String?)
    case end
}

/// A trip the app is tracking (GPS lives in the app; the engine has no clock).
public struct HerbActiveTrip: Hashable, Codable, Sendable {
    public var destination: String?
    public var gpsMiles: Double?
    public var minutes: Int?

    public init(destination: String? = nil, gpsMiles: Double? = nil, minutes: Int? = nil) {
        self.destination = destination
        self.gpsMiles = gpsMiles
        self.minutes = minutes
    }
}

/// A record to add or replace (matched by id), or a new source. Apply in order.
public enum LogChange: Hashable, Sendable {
    case upsertProspect(ProspectRecord)
    case upsertClosing(ClosingRecord)
    case upsertIncome(IncomeRecord)
    case upsertExpense(ExpenseRecord)
    case upsertTrip(TripRecord)
    case upsertActivity(ActivityRecord)
    case addSource(SourceRecord)
}

public struct HerbReply: Sendable {
    public var intent: HerbIntent
    /// What HERB speaks.
    public var say: String
    public var display: String?
    public var cards: [HerbCard] = []
    public var actions: [HerbAction] = []
    public var draft: HerbDraft?
    /// The question HERB just asked, if any.
    public var pending: HerbPending?
    /// Send back with the next turn; nil when the conversation is over.
    public var state: HerbDialogState?
    /// Records to save now (only after the user said yes, or "finish later").
    public var changes: [LogChange] = []
    /// The log saved this turn.
    public var saved: HerbLog?
    /// New settings when HERB learned something (skip counts), else nil.
    public var settings: HerbSettings?
    /// Listen for an answer without the wake phrase (§17.2 voice turn-taking).
    public var followUp = false
    /// Open the draft in its form.
    public var openForm = false
    public var trip: HerbTripCommand?

    init(_ intent: HerbIntent, _ say: String, cards: [HerbCard] = [], actions: [HerbAction] = [], display: String? = nil,
         followUp: Bool = false) {
        self.intent = intent
        self.say = say
        self.cards = cards
        self.actions = actions
        self.display = display
        self.followUp = followUp
    }
}

/// The result of saving a draft.
public struct HerbSaved: Sendable {
    public let say: String
    public let changes: [LogChange]
}

// MARK: Entry point

public struct Herb: Sendable {
    public let book: LogBook
    public let now: Day
    public let settings: HerbSettings
    /// Hour of day (0–23) for greetings; nil says "Hello".
    public let hour: Int?
    public let activeTrip: HerbActiveTrip?

    public init(book: LogBook, now: Day, settings: HerbSettings = HerbSettings(), hour: Int? = nil,
                activeTrip: HerbActiveTrip? = nil) {
        self.book = book
        self.now = now
        self.settings = settings
        self.hour = hour
        self.activeTrip = activeTrip
    }

    var session: HerbSession { HerbSession(book: book, now: now, settings: settings, hour: hour, activeTrip: activeTrip) }

    /// One turn. `state` is what the previous reply returned (nil to start fresh).
    public func respond(to text: String, state: HerbDialogState?) -> HerbReply {
        var s = session
        let t = HerbParse.stripWake(text.trimmed)
        var out = state.map { s.turn($0, t) } ?? s.route(t)
        out.changes = s.changes
        out.settings = s.settings != settings ? s.settings : nil
        return out
    }

    /// The Save button: the changes for a draft (an update when it has a record id).
    public func confirm(_ draft: HerbDraft) throws -> HerbSaved {
        var s = session
        try s.save(log: draft.log, data: draft.data, id: draft.recordID)
        let say: String
        if draft.recordID != nil { say = "Updated." } else {
            say = switch draft.log {
            case .prospects: "Saved. I'll remind you to follow up."
            case .closings: "Saved, and added to your income log."
            case .income: "Income saved."
            case .expenses: "Expense saved."
            case .trips: "Trip saved."
            case .activities: "Activity saved."
            }
        }
        return HerbSaved(say: say, changes: s.changes)
    }
}

extension LogBook {
    /// The book with HERB's changes applied (records replaced by id, new ones appended).
    public func applying(_ changes: [LogChange]) -> LogBook {
        var b = self
        func upsert<T: Identifiable>(_ list: inout [T], _ r: T) {
            if let i = list.firstIndex(where: { $0.id == r.id }) { list[i] = r } else { list.append(r) }
        }
        for c in changes {
            switch c {
            case .upsertProspect(let r): upsert(&b.prospects, r)
            case .upsertClosing(let r): upsert(&b.closings, r)
            case .upsertIncome(let r): upsert(&b.income, r)
            case .upsertExpense(let r): upsert(&b.expenses, r)
            case .upsertTrip(let r): upsert(&b.trips, r)
            case .upsertActivity(let r): upsert(&b.activities, r)
            case .addSource(let s): upsert(&b.sources, s)
            }
        }
        return b
    }
}

/// One turn's working copy: the book as HERB sees it (including anything saved this turn), the settings as
/// HERB has learned them, and the changes to hand back.
struct HerbSession {
    var book: LogBook
    let now: Day
    var settings: HerbSettings
    let hour: Int?
    let activeTrip: HerbActiveTrip?
    var changes: [LogChange] = []

    init(book: LogBook, now: Day, settings: HerbSettings, hour: Int?, activeTrip: HerbActiveTrip?) {
        self.book = book
        self.now = now
        self.settings = settings
        self.hour = hour
        self.activeTrip = activeTrip
    }

    mutating func commit(_ cs: [LogChange]) {
        book = book.applying(cs)
        changes += cs
    }
}
