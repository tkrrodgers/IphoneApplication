import Foundation

// Things that save a busy user typing (pilot feedback, Nov 2026): hints (partial entries HERB finishes later),
// filling in a known source's pillar, category and activity, monthly recurring charges, and moving saved logs onto
// renamed list items.

// MARK: - Hints

extension LogRules {
    /// The note that marks a hint, and that the Review queue reads to ask the user to finish it.
    public static func hintNote(missing: [String]) -> String { "HERB: still need \(joinAnd(missing))." }

    /// Notes with the hint marker taken out (nil when nothing else is left).
    public static func removingHintNote(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let cleaned = notes.replacingOccurrences(of: #"HERB: still need [^.]*\."#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    public static func isHint(_ notes: String?) -> Bool { notes?.contains("HERB: still need ") == true }

    /// What a prospect still needs for the numbers to work: the fields shown in red on the input screen.
    public static func missing(_ p: ProspectRecord) -> [String] {
        var out: [String] = []
        if p.firstNames.trimmingCharacters(in: .whitespaces).isEmpty { out.append("the first name") }
        if p.lastName.trimmingCharacters(in: .whitespaces).isEmpty { out.append("the last name") }
        if p.attribution.pillar == nil { out.append("the pillar") }
        if p.attribution.categoryID == nil { out.append("the category") }
        if p.attribution.sourceID == nil { out.append("the source") }
        if p.attribution.activityID == nil { out.append("the activity") }
        return out
    }

    public static func missing(_ e: ExpenseRecord) -> [String] {
        var out: [String] = []
        if e.amount <= 0 { out.append("the amount") }
        if e.category == nil { out.append("the category") }
        return out
    }

    public static func missing(_ t: TripRecord) -> [String] {
        var out: [String] = []
        if t.miles <= 0 { out.append("the miles") }
        if t.reason.trimmingCharacters(in: .whitespaces).isEmpty { out.append("the reason") }
        return out
    }

    /// Marks a record as a hint (it waits in the Review queue) or, once complete, clears the marker.
    static func settingHint(_ notes: inout String?, _ reviewed: inout Bool, missing: [String]) {
        notes = removingHintNote(notes)
        if missing.isEmpty {
            reviewed = true
        } else {
            notes = [notes, hintNote(missing: missing)].compactMap { $0 }.joined(separator: " ")
            reviewed = false
        }
    }

    public static func markHint(_ p: inout ProspectRecord) { settingHint(&p.notes, &p.reviewed, missing: missing(p)) }
    public static func markHint(_ e: inout ExpenseRecord) { settingHint(&e.notes, &e.reviewed, missing: missing(e)) }
    public static func markHint(_ t: inout TripRecord) { settingHint(&t.notes, &t.reviewed, missing: missing(t)) }

    /// Capitalizes each word of a vendor name ("cedar grill" → "Cedar Grill"), leaving the rest of each word alone
    /// ("McDonald's", "AT&T").
    public static func capitalizedWords(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: false)
            .map { w in w.first.map { String($0).uppercased() + w.dropFirst() } ?? "" }
            .joined(separator: " ")
    }
}

// MARK: - Filling in from a known source

extension LogBook {
    /// The pillar, category and activity this source's past entries usually have, so a form can fill them in when
    /// the user picks a source they've used before.
    public func usualAttribution(forSource id: RecordID) -> Attribution? {
        let mine = (prospects.map(\.attribution) + activities.map(\.attribution)).filter { $0.sourceID == id && $0.pillar != nil }
        guard let pillar = Self.mostCommon(mine.compactMap(\.pillar)) else { return nil }
        let inPillar = mine.filter { $0.pillar == pillar }
        var a = Attribution(pillar: pillar, sourceID: id)
        a.categoryID = Self.mostCommon(inPillar.compactMap(\.categoryID))
        a.activityID = Self.mostCommon(inPillar.compactMap(\.activityID))
        return a.normalized()
    }

    /// The most frequent value; ties go to the one that sorts first, so the answer doesn't change between runs.
    static func mostCommon<T: Hashable>(_ xs: [T]) -> T? {
        Dictionary(grouping: xs, by: { $0 }).max { a, b in
            a.value.count != b.value.count ? a.value.count < b.value.count : "\(a.key)" > "\(b.key)"
        }?.key
    }
}

// MARK: - Recurring charges

extension LogBook {
    /// Monthly charges logged last month that aren't logged yet this month. HERB asks whether each one is still
    /// running ("Still paying Adobe $54.99?").
    public func recurringDue(now: Day) -> [ExpenseRecord] {
        let lastMonth = Day(now.year, now.month, 1).adding(days: -1).monthKey
        let key = { (e: ExpenseRecord) in "\(e.vendor.lowercased())|\(e.categoryID)" }
        let loggedThisMonth = Set(expenses.filter { $0.date.monthKey == now.monthKey }.map(key))
        var seen = Set<String>()
        var out: [ExpenseRecord] = []
        for e in expenses.filter({ $0.recurring == true && $0.date.monthKey == lastMonth }).sorted(by: { $0.date > $1.date }) {
            let k = key(e)
            guard !loggedThisMonth.contains(k), seen.insert(k).inserted else { continue }
            out.append(e)
        }
        return out.sorted { $0.vendor.localizedCaseInsensitiveCompare($1.vendor) == .orderedAscending }
    }
}

extension ExpenseRecord {
    /// This month's copy of a recurring charge.
    public func renewed(on day: Day) -> ExpenseRecord {
        var e = self
        e.id = newRecordID()
        e.date = day
        e.hasReceipt = false
        e.checkNumber = nil
        e.notes = nil
        e.capture = .manual
        e.reviewed = true
        return e
    }
}

// MARK: - Renamed list items

extension LogBook {
    /// Moves saved entries onto renamed or replaced list items (`Taxonomy.renamedIDs`), e.g. "Networking-Open Group"
    /// → "Networking". Safe to run on every load.
    public func migratingTaxonomy() -> LogBook {
        func fix(_ a: Attribution) -> Attribution {
            var a = a
            if let c = a.categoryID, let n = Taxonomy.renamedIDs[c] { a.categoryID = n }
            if let x = a.activityID, let n = Taxonomy.renamedIDs[x] { a.activityID = n }
            return a
        }
        let renamedReasons = ["Networking-Open Group": "Networking", "Networking-Closed Group": "Networking"]
        var b = self
        for i in b.prospects.indices { b.prospects[i].attribution = fix(b.prospects[i].attribution) }
        for i in b.closings.indices { b.closings[i].attribution = fix(b.closings[i].attribution) }
        for i in b.income.indices { b.income[i].attribution = fix(b.income[i].attribution) }
        for i in b.activities.indices { b.activities[i].attribution = fix(b.activities[i].attribution) }
        for i in b.trips.indices {
            if let x = b.trips[i].activityID, let n = Taxonomy.renamedIDs[x] { b.trips[i].activityID = n }
            if let r = renamedReasons[b.trips[i].reason] { b.trips[i].reason = r }
        }
        return b
    }
}
