import Foundation

// HERB as analyst and coach (design §16): the Logsperity Index summary, follow-ups, the §16.3 coaching rules,
// "what should I focus on this week" (§16.4) and the Review queue (§6.4). Swift port of herb.py's coaching half.

public struct Insight: Hashable, Sendable, Identifiable {
    public let key: String
    public let level: InsightLevel
    public let title: String
    public let text: String
    public let sample: Int?
    let impact: Double
    public var id: String { key }
}

public struct FollowUp: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case prospect, partner, review }
    public enum Chip: String, Sendable { case late, today, new, soon }
    public let id: String
    public let kind: Kind
    public let prospectID: RecordID?
    public let name: String
    public let reason: String
    public let due: Day
    public let chip: Chip
    let score: Double
}

public struct FocusItem: Hashable, Sendable {
    public let title: String
    public let why: String
    public let value: String?
    public let hours: Double
    public let activityID: String?
}

public struct Focus: Hashable, Sendable {
    public let say: String
    public let items: [FocusItem]
    public let drop: FocusItem?
}

public struct KPI: Hashable, Sendable, Identifiable {
    public let key: String
    public let label: String
    public let display: String
    public let sub: String
    public var id: String { key }
}

public struct ReviewItem: Hashable, Sendable, Identifiable {
    public enum Log: String, Sendable { case prospects, closings, income, expenses, trips, activities }
    public let log: Log
    public let recordID: RecordID
    public let capture: Capture
    public let title: String
    public let subtitle: String
    public let question: String
    public var id: String { "\(log.rawValue):\(recordID)" }
}

public struct Coach: Sendable {
    public let book: LogBook
    public let now: Day
    /// Insight keys the user dismissed.
    public let dismissed: Set<String>

    public init(_ book: LogBook, now: Day, dismissed: Set<String> = []) {
        self.book = book
        self.now = now
        self.dismissed = dismissed
    }

    var ytd: Ledger { try! Ledger(book, periodKey: "ytd", now: now) }

    // MARK: Index (§12)

    public static func indexSummary(_ led: Ledger) -> IndexSummary {
        let v = led.index
        let label = switch v {
        case nil: "No data yet"
        case let v? where v < 90: "Below the healthy baseline"
        case let v? where v < 110: "Healthy"
        case let v? where v < 150: "Strong"
        default: "Very strong"
        }
        func driver(_ key: String, _ label: String, _ value: Double?, _ bench: Double) -> IndexDriver {
            IndexDriver(key: key, label: label, value: value, display: Format.pct(value),
                        benchmarkDisplay: Format.pct(bench), ratio: ratio(value ?? 0, bench))
        }
        return IndexSummary(value: v, display: Format.num(v), label: label, drivers: [
            driver("conversion", "Conversion", led.conversion, IndexBenchmark.conversion),
            driver("netRoi", "Net ROI", led.netROI, IndexBenchmark.netROI),
            driver("margin", "Profit margin", led.margin, IndexBenchmark.margin),
        ])
    }

    // MARK: Follow-ups

    struct Drift {
        let source: SourceRecord
        let closings: Int
        let income: Double
        let lastTouch: Day
        let daysSince: Int
    }

    /// Referral partners with closings in the last year whose last touch is older than `days`.
    func partnerDrift(days: Int = 30) -> [Drift] {
        let since = now.adding(days: -365)
        var out: [Drift] = []
        for s in book.sources where s.kind == "person" {
            let cl = book.closings.filter {
                $0.attribution.sourceID == s.id && $0.attribution.subPillar == .professional && $0.date >= since
            }
            guard !cl.isEmpty else { continue }
            let touches = book.activities.filter { $0.attribution.sourceID == s.id }.map(\.date)
                + book.expenses.filter { $0.sourceID == s.id }.map(\.date)
                + book.prospects.filter { $0.attribution.sourceID == s.id }.map(\.date)
            guard let last = touches.max() else { continue }
            let gap = last.days(to: now)
            if gap > days {
                out.append(Drift(source: s, closings: cl.count, income: cl.reduce(0) { $0 + $1.income },
                                 lastTouch: last, daysSince: gap))
            }
        }
        return out.sorted { $0.income > $1.income }
    }

    public func followUps() -> [FollowUp] {
        var items: [FollowUp] = []
        let closed = Set(book.closings.compactMap(\.prospectID))
        let from = now.adding(days: -14)
        for p in book.prospects where !closed.contains(p.id) && p.strength != .noGo {
            guard let fu = p.followUp, from <= fu, fu <= now else { continue }
            var chip: FollowUp.Chip = fu < now ? .late : .today
            if p.date.days(to: now) <= 7 && (p.strength == .hot || p.strength == .redHot) && fu < now { chip = .new }
            let reason = p.notes?.isEmpty == false ? p.notes!
                : "\(p.strength?.name ?? "") prospect · via \(book.sourceName(p.attribution.sourceID) ?? Format.dash)"
            let score = (fu < now ? 100.0 : 40) + (p.strength == .redHot ? 30 : p.strength == .hot ? 15 : 0)
                + (chip == .new ? 20 : 0)
            items.append(FollowUp(id: "prospect:\(p.id)", kind: .prospect, prospectID: p.id, name: p.fullName,
                                  reason: reason, due: fu, chip: chip, score: score))
        }
        for d in partnerDrift().prefix(2) {
            items.append(FollowUp(id: "partner:\(d.source.id)", kind: .partner, prospectID: nil, name: d.source.name,
                                  reason: "Referral partner · \(d.daysSince) days since last contact (\(d.closings) closings, \(Format.money(d.income)) this year)",
                                  due: now, chip: .soon, score: 20 + min(40, d.income / 1000)))
        }
        for c in book.closings {
            guard let days = c.referralRequest.askInDays,
                  let p = book.prospects.first(where: { $0.id == c.prospectID }) else { continue }
            let due = c.date.adding(days: days)
            if now.adding(days: -7) <= due && due <= now {
                items.append(FollowUp(id: "closing:\(c.id)", kind: .review, prospectID: p.id, name: p.fullName,
                                      reason: "Ask for a review or referral — closed \(Format.relativeDay(c.date, now: now))",
                                      due: due, chip: .today, score: 30))
            }
        }
        return items.sorted { $0.score > $1.score }
    }

    // MARK: Coaching rules (§16.3)

    /// Prospects with no known source (D3) count, but aren't a source to coach on.
    static func isUnknownSource(_ r: BreakdownRow) -> Bool { r.key == nil || r.name == "Unknown" }

    static func noCloseSources(_ led: Ledger, minimum: Int = 3) -> [BreakdownRow] {
        led.breakdown(.source).filter { $0.prospects >= minimum && $0.closings == 0 && !isUnknownSource($0) }
            .sorted { $0.prospects > $1.prospects }
    }

    public func insights(periodKey: String = "ytd") -> [Insight] {
        let led = (try? Ledger(book, periodKey: periodKey, now: now)) ?? ytd
        var out: [Insight] = []
        func add(_ key: String, _ level: InsightLevel, _ title: String, _ text: String, sample: Int? = nil,
                 impact: Double = 0) {
            out.append(Insight(key: key, level: level, title: title, text: text, sample: sample, impact: impact))
        }
        let avgIncome = led.avgClosingIncome ?? led.plan.avgCommission

        // plan pace
        let tr = PlanTracking(book, year: now.year, now: now)
        for it in tr.items where ["income", "profit"].contains(it.key) {
            guard let pace = it.pacePct else { continue }
            if pace < 0.95 {
                let gap = it.projected - it.actual
                add("pace.\(it.key)", .concern, "\(it.label) is behind pace",
                    "You're \(Format.pct(1 - pace)) behind \(it.label.lowercased()) pace (\(it.displayActual) vs \(it.displayProjected) projected). The smallest fix: about \(Format.num(max(1, gap / avgIncome), decimals: 1)) more closings.",
                    impact: gap)
            } else if pace >= 1.05 {
                add("pace.\(it.key)", .win, "\(it.label) is ahead of pace",
                    "\(it.label) is at \(Format.pct(pace)) of pace — \(it.displayActual) vs \(it.displayProjected) projected by today.")
            }
        }
        // conversion watch / concern by category and activity
        for dim in [Dimension.category, .activity] {
            for r in led.breakdown(dim) where r.closings == 0 && r.key != nil {
                if r.prospects >= 4 {
                    add("conv.\(dim.rawValue).\(r.key!)", .concern, "\(r.name): \(r.prospects) prospects, 0 closings",
                        "\(r.name) has produced \(r.prospects) prospects and no closings. Four or more with none is a concern — consider dropping it or changing your approach.",
                        sample: r.prospects, impact: r.hours * 50 + Double(r.prospects) * 100)
                } else if r.prospects >= 2 {
                    add("conv.\(dim.rawValue).\(r.key!)", .watch, "Watch \(r.name)",
                        "\(r.name): \(r.prospects) prospects, no closings yet (early signal — keep an eye on it).",
                        sample: r.prospects, impact: Double(r.prospects) * 20)
                }
            }
        }
        // sources that never convert
        for r in Self.noCloseSources(led, minimum: 4) {
            add("source.\(r.key!)", .concern, "\(r.name) never converts",
                "\(r.name) sent \(r.prospects) prospects and none closed" + (r.expenses > 0 ? ", and cost you \(Format.money(r.expenses)) this year" : "") + ". Time to move on, or coach the source.",
                sample: r.prospects, impact: r.expenses + Double(r.prospects) * 100)
        }
        // recurring expense with no closings from its source
        let zombieGroups: Set<ExpenseGroup> = [.adInternet, .adTraditional, .technology, .prospecting]
        let byVendor = Dictionary(grouping: led.expenses.filter { zombieGroups.contains($0.group) }, by: \.vendor)
        for (vendor, rows) in byVendor.sorted(by: { $0.key < $1.key }) where rows.count >= 3 {
            guard let src = rows.compactMap(\.sourceID).first,
                  !led.closings.contains(where: { $0.attribution.sourceID == src }) else { continue }
            let total = rows.reduce(0) { $0 + $1.amount }
            add("zombie.\(vendor)", .concern, "\(vendor) isn't paying off",
                "You've paid \(Format.money(total)) for \(vendor) this year (\(rows.count) charges) with no closings from it. Consider cancelling.",
                impact: total)
        }
        // closings: biggest average deal by pillar
        let pil = led.breakdown(.pillar)
        if let b = pil.filter({ $0.closings >= 2 }).max(by: { ($0.avgVolume ?? 0) < ($1.avgVolume ?? 0) }) {
            add("closings.volume", .info, "\(b.name) closes your biggest deals",
                "\(b.name) averages \(Format.moneyK(b.avgVolume)) per closing vs \(Format.moneyK(led.avgVolume)) overall. Bigger deals mean more income per closing.",
                sample: b.closings)
        }
        // income: best income per closing by category
        if let c = led.breakdown(.category).filter({ $0.closings >= 2 }).max(by: { ($0.avgIncome ?? 0) < ($1.avgIncome ?? 0) }) {
            add("income.category", .win, "\(c.name) pays best per closing",
                "\(c.name) brought \(Format.money(c.closingIncome)) from \(c.closings) closings — \(Format.money(c.avgIncome)) each.",
                sample: c.closings)
        }
        // efficiency: hours per closing more than twice the best pillar's
        let eff = pil.filter { $0.closings > 0 && $0.hours > 0 }
        if eff.count >= 2, let best = eff.min(by: { $0.hoursPerClosing! < $1.hoursPerClosing! }),
           let worst = eff.max(by: { $0.hoursPerClosing! < $1.hoursPerClosing! }),
           worst.hoursPerClosing! > 2 * best.hoursPerClosing! {
            let moved = 4 * 52 / best.hoursPerClosing! - 4 * 52 / worst.hoursPerClosing!
            add("efficiency.pillar", .concern, "\(worst.name) takes too long per closing",
                "\(worst.name) takes \(Format.num(worst.hoursPerClosing, decimals: 1)) hours per closing vs \(Format.num(best.hoursPerClosing, decimals: 1)) for \(best.name). Moving 4 hours a week could add about \(Format.num(moved, decimals: 1)) closings a year.",
                sample: worst.closings, impact: moved * avgIncome)
        }
        // time sinks: lots of hours, little income
        let target = led.planOutputs.hourlyGross
        for r in led.breakdown(.activity) where r.key != nil && r.hours >= 20 && (r.incomePerHour ?? 0) < target {
            add("timesink.\(r.key!)", .concern, "\(r.name) is a time sink",
                "\(Format.num(r.hours)) hours on \(r.name) this year produced \(Format.money(r.income)) — \(Format.money(r.incomePerHour ?? 0)) an hour against your \(Format.money(target)) target.",
                sample: r.prospects, impact: r.hours * target)
        }
        // ROI with time
        let roi = led.pillarROI().filter { !["overhead", "total"].contains($0.key) && $0.roiWithTime != nil }
        if let w = roi.min(by: { $0.roiWithTime! < $1.roiWithTime! }), let b = roi.max(by: { $0.roiWithTime! < $1.roiWithTime! }),
           w.roiWithTime! < 1.5 {
            add("roi.pillar", .watch, "\(w.name) has the lowest return",
                "\(w.name) returns \(Format.money(w.roiWithTime! + 1, cents: true)) per dollar of time and money; \(b.name) returns \(Format.money(b.roiWithTime! + 1, cents: true)).")
        }
        // partner drift
        for d in partnerDrift().prefix(2) {
            add("drift.\(d.source.id)", .watch, "Reconnect with \(d.source.name)",
                "\(d.source.name) sent \(d.closings) closings (\(Format.money(d.income))) in the last year, but it's been \(d.daysSince) days since you were in touch.",
                sample: d.closings, impact: d.income / 4)
        }
        // prospects with no known source (D3)
        let blind = led.breakdown(.source).filter(Self.isUnknownSource).reduce(0) { $0 + $1.prospects }
        if blind > 0 {
            let s = blind == 1 ? "" : "s"
            add("source.unknown", .info, "\(blind) prospect\(s) with no source",
                "\(blind) prospect\(s) this period \(blind == 1 ? "has" : "have") no known source, so \(blind == 1 ? "it" : "they") can't show which sources pay. Fill them in from the Review queue.",
                impact: Double(blind) * 10)
        }
        // missing receipts
        let missing = led.expenses.filter { $0.amount >= 75 && !$0.hasReceipt }
        if !missing.isEmpty {
            add("receipts.missing", .info, "\(missing.count) receipts missing",
                "\(missing.count) expenses of $75 or more have no receipt. Snap them so they hold up in an audit.",
                impact: 10)
        }
        // logging gap
        if let last = book.activities.map(\.date).max(), last.days(to: now) > 3 {
            add("logging.gap", .info, "Nothing logged lately",
                "No business-building time logged since \(Format.relativeDay(last, now: now)).", impact: 5)
        }
        return out.filter { !dismissed.contains($0.key) }
            .sorted { ($0.level, -$0.impact) < ($1.level, -$1.impact) }
    }

    // MARK: Focus (§16.4)

    /// Top 3 actions by expected value per hour, plus one thing to drop.
    public func focus() -> Focus {
        let led = ytd
        let avgIncome = led.avgClosingIncome ?? led.plan.avgCommission
        struct Candidate { let item: FocusItem; let ev: Double; let boost: Double }
        var cands: [Candidate] = []
        let closed = Set(book.closings.compactMap(\.prospectID))
        let hot = book.prospects.filter {
            !closed.contains($0.id) && ($0.strength == .redHot || $0.strength == .hot)
                && ($0.followUp.map { $0 <= now.adding(days: 3) } ?? false) && $0.date >= now.adding(days: -60)
        }.sorted { ($0.strength == .redHot ? 0 : 1, $0.followUp!) < ($1.strength == .redHot ? 0 : 1, $1.followUp!) }
        if !hot.isEmpty {
            let value = hot.reduce(0) { $0 + $1.strength!.closeProbability } * avgIncome
            let names = hot.prefix(3).map(\.fullName).joined(separator: ", ")
            cands.append(Candidate(item: FocusItem(title: "Call your \(hot.count) hot prospect\(hot.count == 1 ? "" : "s")",
                                                   why: "\(names) — about \(Format.moneyK(value)) of likely income.",
                                                   value: Format.moneyK(value), hours: 0.25 * Double(hot.count), activityID: nil),
                                   ev: value, boost: 2))
        }
        let acts = led.breakdown(.activity).filter { $0.key != nil && $0.hours >= 5 && ($0.incomePerHour ?? 0) > 0 }
        if let b = acts.max(by: { $0.incomePerHour! < $1.incomePerHour! }) {
            cands.append(Candidate(item: FocusItem(title: "2 hours of \(b.name)",
                                                   why: "Your best return on time — \(Format.money(b.incomePerHour)) an hour, \(Format.pct(b.conversion)) conversion.",
                                                   value: Format.money(b.incomePerHour! * 2), hours: 2, activityID: b.key),
                                   ev: b.incomePerHour! * 2 * 0.5, boost: 1))
        }
        if let d = partnerDrift().first {
            cands.append(Candidate(item: FocusItem(title: "Coffee with \(d.source.name)",
                                                   why: "\(d.closings) closings (\(Format.money(d.income))) in the last year, but \(d.daysSince) days since you talked.",
                                                   value: Format.money(d.income / 12), hours: 1.5,
                                                   activityID: "act.relationship_building_professional"),
                                   ev: d.income / 12, boost: 1.2))
        }
        if let r = followUps().first(where: { $0.kind == .review }) {
            cands.append(Candidate(item: FocusItem(title: "Ask \(r.name) for a review",
                                                   why: "Your closing follow-up is due — past clients are your best source.",
                                                   value: nil, hours: 0.25, activityID: nil),
                                   ev: avgIncome * 0.1, boost: 1))
        }
        let items = cands.sorted { $0.ev / max(0.25, $0.item.hours) * $0.boost > $1.ev / max(0.25, $1.item.hours) * $1.boost }
            .prefix(3).map(\.item)
        var drop: FocusItem?
        let weak = led.breakdown(.activity).filter { $0.key != nil && $0.hours >= 10 && $0.closings <= 1 }
        if let w = weak.min(by: { ($0.incomePerHour ?? 0) < ($1.incomePerHour ?? 0) }) {
            drop = FocusItem(title: w.name,
                             why: "\(Format.num(w.hours)) hours this year, \(w.closings) closing\(w.closings == 1 ? "" : "s") — \(Format.money(w.incomePerHour ?? 0)) an hour.",
                             value: nil, hours: w.hours, activityID: w.key)
        }
        var say = items.isEmpty ? "Log a few prospects and activities and I'll have focus ideas for you."
            : "Three things this week: " + items.enumerated().map { "\($0.offset + 1). \($0.element.title) — \($0.element.why)" }.joined(separator: " ")
        if let drop { say += " One to drop: \(drop.title). \(drop.why)" }
        return Focus(say: say, items: Array(items), drop: drop)
    }

    // MARK: Today (S3)

    public func kpis() -> [KPI] {
        let led = ytd
        let pace = PlanTracking(book, year: now.year, now: now).item("income")?.pacePct
        return [
            KPI(key: "income", label: "Income YTD", display: Format.moneyK(led.incomeTotal), sub: "\(Format.pct(pace)) of pace"),
            KPI(key: "closings", label: "Closings YTD", display: String(led.closingCount), sub: "\(Format.moneyK(led.volume)) volume"),
            KPI(key: "prospects", label: "Prospects YTD", display: String(led.prospectCount), sub: "\(Format.pct(led.conversion)) convert"),
            KPI(key: "index", label: "Logsperity Index", display: Format.num(led.index), sub: Self.indexSummary(led).label),
        ]
    }

    // MARK: Review queue (§6.4)

    public func reviewItems() -> [ReviewItem] {
        var items: [ReviewItem] = []
        let byDateDesc: (Day, Day) -> Bool = { $0 > $1 }
        for t in book.trips.filter({ !$0.reviewed }).sorted(by: { byDateDesc($0.date, $1.date) }) {
            items.append(ReviewItem(log: .trips, recordID: t.id, capture: t.capture,
                                    title: "\(Format.num(t.miles, decimals: 1)) mi → \(t.destination)",
                                    subtitle: "\(Format.relativeDay(t.date, now: now).capitalized) · \(t.capture == .gps ? "detected by GPS" : "captured")",
                                    question: "Business trip to \(t.destination)?"))
        }
        for e in book.expenses.filter({ !$0.reviewed }).sorted(by: { byDateDesc($0.date, $1.date) }) {
            let how = e.capture == .bank ? "Card transaction" : e.capture == .receipt ? "Receipt photo" : "Captured"
            var q = "\(e.group.name) · \(e.category?.name ?? "?")"
            if let w = e.withWhom, !w.isEmpty { q += " with \(w)" }
            items.append(ReviewItem(log: .expenses, recordID: e.id, capture: e.capture,
                                    title: "\(Format.money(e.amount, cents: true)) · \(e.vendor)",
                                    subtitle: "\(how) · \(Format.relativeDay(e.date, now: now))", question: q + "?"))
        }
        for a in book.activities.filter({ !$0.reviewed }).sorted(by: { byDateDesc($0.date, $1.date) }) {
            let name = a.attribution.activityID.flatMap { Taxonomy.activityByID[$0]?.name } ?? "?"
            let with = book.sourceName(a.attribution.sourceID).map { " with \($0)" } ?? ""
            items.append(ReviewItem(log: .activities, recordID: a.id, capture: a.capture,
                                    title: "\(Format.spokenMinutes(a.minutes)) · \(name)",
                                    subtitle: "\(a.notes ?? "From your calendar") · \(Format.relativeDay(a.date, now: now))",
                                    question: "Log this as \(name)\(with)?"))
        }
        for p in book.prospects.filter({ !$0.reviewed }).sorted(by: { byDateDesc($0.date, $1.date) }) {
            let question: String
            if let missing = Self.parkedMissing(p.notes) {
                question = missing == "the source" ? "Where did \(p.fullName) come from?" : "Finish \(p.fullName) — add \(missing)?"
            } else {
                let cat = p.attribution.categoryID.flatMap { Taxonomy.categoryByID[$0]?.name } ?? ""
                question = "Save \(p.fullName) from \(book.sourceName(p.attribution.sourceID) ?? Format.dash) as a \(cat) prospect?"
            }
            items.append(ReviewItem(log: .prospects, recordID: p.id, capture: p.capture, title: "New prospect: \(p.fullName)",
                                    subtitle: p.notes ?? "Captured by voice", question: question))
        }
        for c in book.closings.filter({ !$0.reviewed }) {
            items.append(ReviewItem(log: .closings, recordID: c.id, capture: c.capture, title: "Closing · \(Format.money(c.income))",
                                    subtitle: Format.relativeDay(c.date, now: now), question: "Confirm this closing?"))
        }
        for i in book.income.filter({ !$0.reviewed }) {
            items.append(ReviewItem(log: .income, recordID: i.id, capture: i.capture, title: "Deposit · \(Format.money(i.amount))",
                                    subtitle: Format.relativeDay(i.date, now: now), question: "Confirm this income?"))
        }
        return items
    }

    /// "HERB: still need the address and the source." → "the address and the source".
    static func parkedMissing(_ notes: String?) -> String? {
        guard let notes, let r = notes.range(of: "HERB: still need ") else { return nil }
        let rest = notes[r.upperBound...]
        guard let dot = rest.firstIndex(of: ".") else { return nil }
        return String(rest[..<dot])
    }
}
