import Foundation
import LogsperityCore
import Observation

enum LogKind: String, CaseIterable, Identifiable {
    case prospects, closings, income, expenses, trips, activities
    var id: String { rawValue }
    var title: String {
        switch self {
        case .prospects: "Prospects"
        case .closings: "Closings"
        case .income: "Income"
        case .expenses: "Expenses"
        case .trips: "Mileage"
        case .activities: "Activity"
        }
    }
    var singular: String {
        switch self {
        case .prospects: "Prospect"
        case .closings: "Closing"
        case .income: "Income"
        case .expenses: "Expense"
        case .trips: "Trip"
        case .activities: "Activity"
        }
    }
    var symbol: String {
        switch self {
        case .prospects: "person.crop.circle.badge.plus"
        case .closings: "checkmark.seal"
        case .income: "dollarsign.circle"
        case .expenses: "creditcard"
        case .trips: "car"
        case .activities: "figure.run"
        }
    }
}

/// The app's single source of truth: the log book, settings and today's date. Screens read it and call its
/// methods; every number they show comes from LogsperityCore.
@MainActor @Observable
final class AppModel {
    private(set) var book: LogBook
    private(set) var settings: AppSettings
    private(set) var today = Day.today()
    var lastError: String?
    private let store: FileStore

    init(store: FileStore = FileStore()) {
        self.store = store
        book = store.loadBook() ?? LogBook()
        settings = store.loadSettings() ?? AppSettings()
    }

    /// An in-memory model for previews and tests.
    static func preview(sample: Bool = true) -> AppModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let m = AppModel(store: FileStore(directory: dir))
        if sample { m.loadSampleYear() }
        m.settings.onboarded = true
        m.settings.name = SampleYear.ownerName
        return m
    }

    func refreshToday() { today = Day.today() }

    // MARK: Engine views

    var coach: Coach { Coach(book, now: today, dismissed: Set(settings.dismissedInsights)) }
    var reports: Reports { Reports(book, now: today, dismissed: Set(settings.dismissedInsights)) }
    func ledger(_ periodKey: String = "ytd") -> Ledger {
        (try? Ledger(book, periodKey: periodKey, now: today)) ?? Ledger(book, period: try! Period.parse("ytd", now: today), now: today)
    }
    var plan: PlanInputs { book.plan(for: today.year) }

    // MARK: Saving

    private func persist() {
        do {
            try store.saveBook(book)
            try store.saveSettings(settings)
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        persist()
        Reminders.schedule(settings)
    }

    private static func upsert<T: Identifiable>(_ item: T, into list: inout [T]) where T.ID == RecordID {
        if let i = list.firstIndex(where: { $0.id == item.id }) { list[i] = item } else { list.append(item) }
    }

    func save(_ p: ProspectRecord) { Self.upsert(p, into: &book.prospects); persist() }
    func save(_ i: IncomeRecord) { Self.upsert(i, into: &book.income); persist() }
    func save(_ e: ExpenseRecord) { Self.upsert(e, into: &book.expenses); persist() }
    func save(_ t: TripRecord) { Self.upsert(t, into: &book.trips); persist() }
    func save(_ a: ActivityRecord) { Self.upsert(a, into: &book.activities); persist() }

    /// Saves a closing with rules R3 and R5: one closing per prospect; "Add to Income Log" and additional
    /// transactions become income entries. Editing a closing updates its linked income entry.
    func save(_ c: ClosingRecord, addToIncome: Bool = true, additional: [(transactionSize: Double, income: Double)] = []) throws {
        if let pid = c.prospectID, let p = book.prospects.first(where: { $0.id == pid }) {
            try LogRules.checkOneClosing(prospect: p, closings: book.closings, editing: c.id)
        }
        let isNew = !book.closings.contains { $0.id == c.id }
        Self.upsert(c, into: &book.closings)
        let lastName = book.prospects.first { $0.id == c.prospectID }?.lastName
        if isNew {
            book.income += LogRules.incomeRows(for: c, lastName: lastName, addToIncome: addToIncome, additional: additional)
        } else if let i = book.income.firstIndex(where: { $0.closingID == c.id }) {
            book.income[i].amount = c.income
            book.income[i].transactionSize = c.transactionSize
            book.income[i].attribution = c.attribution
            book.income[i].date = c.date
        }
        persist()
    }

    func savePlan(_ inputs: PlanInputs, year: Int) throws {
        try inputs.validate()
        book.plans[year] = inputs
        persist()
    }

    /// Finds a source by name (Zillow = zillow.com, issue I8) or creates it. Empty names return nil.
    func sourceID(named name: String, kind: String = "person") -> RecordID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let norm = SourceRecord.normalize(trimmed)
        if let s = book.sources.first(where: { SourceRecord.normalize($0.name) == norm }) { return s.id }
        let s = SourceRecord(name: trimmed, kind: kind)
        book.sources.append(s)
        persist()
        return s.id
    }

    func sourceName(_ id: RecordID?) -> String { book.sourceName(id) ?? "" }

    /// Previously used names for autocomplete, most used first.
    func sourceSuggestions(matching text: String) -> [String] {
        let q = text.lowercased()
        var uses: [RecordID: Int] = [:]
        for p in book.prospects { if let s = p.attribution.sourceID { uses[s, default: 0] += 1 } }
        for a in book.activities { if let s = a.attribution.sourceID { uses[s, default: 0] += 1 } }
        return book.sources.filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .sorted { (uses[$0.id] ?? 0, $1.name) > (uses[$1.id] ?? 0, $0.name) }
            .prefix(6).map(\.name)
    }

    func delete(_ kind: LogKind, id: RecordID) {
        switch kind {
        case .prospects:
            book.prospects.removeAll { $0.id == id }
        case .closings:
            book.closings.removeAll { $0.id == id }
            book.income.removeAll { $0.closingID == id }
        case .income: book.income.removeAll { $0.id == id }
        case .expenses: book.expenses.removeAll { $0.id == id }
        case .trips: book.trips.removeAll { $0.id == id }
        case .activities: book.activities.removeAll { $0.id == id }
        }
        persist()
    }

    // MARK: Review queue (§6.4)

    func confirmReview(_ item: ReviewItem) {
        let id = item.recordID
        switch item.log {
        case .prospects: if let i = book.prospects.firstIndex(where: { $0.id == id }) { book.prospects[i].reviewed = true }
        case .closings: if let i = book.closings.firstIndex(where: { $0.id == id }) { book.closings[i].reviewed = true }
        case .income: if let i = book.income.firstIndex(where: { $0.id == id }) { book.income[i].reviewed = true }
        case .expenses: if let i = book.expenses.firstIndex(where: { $0.id == id }) { book.expenses[i].reviewed = true }
        case .trips: if let i = book.trips.firstIndex(where: { $0.id == id }) { book.trips[i].reviewed = true }
        case .activities: if let i = book.activities.firstIndex(where: { $0.id == id }) { book.activities[i].reviewed = true }
        }
        persist()
    }

    /// Dismissing an auto-captured item deletes it.
    func dismissReview(_ item: ReviewItem) {
        delete(LogKind(rawValue: item.log.rawValue)!, id: item.recordID)
    }

    func dismissInsight(_ key: String) {
        updateSettings { if !$0.dismissedInsights.contains(key) { $0.dismissedInsights.append(key) } }
    }

    // MARK: Sample data and reset

    func loadSampleYear() {
        book = SampleYear.build(now: today)
        settings.usingSampleData = true
        persist()
    }

    func eraseAllData() {
        book = LogBook()
        settings.usingSampleData = false
        settings.dismissedInsights = []
        persist()
    }

    func exportURL() -> URL? { try? store.exportURL(book: book) }
}
