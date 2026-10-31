import LogsperityCore
import SwiftUI

/// Log tab (S13): the six logs, each a searchable list with add, edit and delete.
struct LogHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                ForEach(LogKind.allCases) { k in
                    NavigationLink(value: k) {
                        Label {
                            HStack {
                                Text(k.title)
                                Spacer()
                                Text(count(k)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        } icon: { Image(systemName: k.symbol) }
                    }
                }
                Section {
                    NavigationLink { ReviewQueueView() } label: {
                        Label("Review queue (\(model.coach.reviewItems().count))", systemImage: "tray.full")
                    }
                }
            }
            .navigationTitle("Log")
            .navigationDestination(for: LogKind.self) { LogListView(kind: $0) }
        }
    }

    private func count(_ k: LogKind) -> String {
        let led = model.ledger("ytd")
        return switch k {
        case .prospects: "\(led.prospectCount) YTD"
        case .closings: "\(led.closingCount) YTD"
        case .income: Format.moneyK(led.incomeTotal)
        case .expenses: Format.moneyK(led.expensesTotal)
        case .trips: Format.miles(led.businessMiles)
        case .activities: Format.hours(led.bbHours)
        }
    }
}

struct LogRow: Identifiable {
    let id: RecordID
    let date: Day
    let title: String
    let subtitle: String
    let value: String
    let needsReview: Bool
}

struct LogListView: View {
    @Environment(AppModel.self) private var model
    let kind: LogKind
    @State private var search = ""
    @State private var editing: RecordID?
    @State private var adding = false

    var body: some View {
        let rows = self.rows.filter { search.isEmpty || "\($0.title) \($0.subtitle)".localizedCaseInsensitiveContains(search) }
        List {
            if rows.isEmpty {
                ContentUnavailableView("No \(kind.title.lowercased()) yet", systemImage: kind.symbol,
                                       description: Text("Tap + to add one, or tell HERB."))
            }
            ForEach(rows) { r in
                Button { editing = r.id } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(r.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                if r.needsReview { Chip(text: "Review", color: .orange) }
                            }
                            Text(r.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(r.value).monospacedDigit().foregroundStyle(.primary)
                            Text(Format.shortDate(r.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { model.delete(kind, id: r.id) }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle(kind.title)
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add \(kind.singular)") }
        .sheet(isPresented: $adding) { NavigationStack { LogForm(kind: kind) } }
        .sheet(item: Binding(get: { editing.map(EditTarget.init) }, set: { editing = $0?.id })) { t in
            NavigationStack { LogForm(kind: kind, editingID: t.id) }
        }
    }

    private struct EditTarget: Identifiable { let id: RecordID }

    private var rows: [LogRow] {
        let b = model.book
        func cat(_ a: Attribution) -> String { a.categoryID.flatMap { Taxonomy.categoryByID[$0]?.name } ?? a.pillar?.name ?? "" }
        let out: [LogRow] = switch kind {
        case .prospects: b.prospects.map { p in
            LogRow(id: p.id, date: p.date, title: p.fullName.isEmpty ? "(no name)" : p.fullName,
                   subtitle: [cat(p.attribution), model.sourceName(p.attribution.sourceID)].filter { !$0.isEmpty }.joined(separator: " · "),
                   value: p.strength?.name ?? "", needsReview: !p.reviewed)
        }
        case .closings: b.closings.map { c in
            LogRow(id: c.id, date: c.date, title: b.prospects.first { $0.id == c.prospectID }?.fullName ?? "Closing",
                   subtitle: "\(Format.moneyK(c.transactionSize)) volume · \(cat(c.attribution))", value: Format.money(c.income),
                   needsReview: !c.reviewed)
        }
        case .income: b.income.map { i in
            LogRow(id: i.id, date: i.date, title: i.mode == .transaction ? (i.lastName ?? "Transaction") : (i.type?.name ?? "Income"),
                   subtitle: [i.mode == .batch ? "Batch of \(i.transactionCount ?? 0)" : nil, i.payer].compactMap { $0 }.joined(separator: " · "),
                   value: Format.money(i.amount), needsReview: !i.reviewed)
        }
        case .expenses: b.expenses.map { e in
            LogRow(id: e.id, date: e.date, title: e.vendor.isEmpty ? (e.category?.name ?? "Expense") : e.vendor,
                   subtitle: "\(e.category?.name ?? "") → \(e.irs)", value: Format.money(e.amount, cents: true), needsReview: !e.reviewed)
        }
        case .trips: b.trips.map { t in
            LogRow(id: t.id, date: t.date, title: t.destination.isEmpty ? "Trip" : t.destination,
                   subtitle: t.isBusiness ? t.reason : "Personal", value: Format.miles(t.miles), needsReview: !t.reviewed)
        }
        case .activities: b.activities.map { a in
            LogRow(id: a.id, date: a.date, title: a.attribution.activityID.flatMap { Taxonomy.activityByID[$0]?.name } ?? "Activity",
                   subtitle: [a.attribution.pillar?.name, b.sourceName(a.attribution.sourceID)].compactMap { $0 }.joined(separator: " · "),
                   value: Format.hours(Double(a.minutes) / 60), needsReview: !a.reviewed)
        }
        }
        return out.sorted { $0.date > $1.date }
    }
}

/// Picks the right input screen.
struct LogForm: View {
    let kind: LogKind
    var editingID: RecordID?
    /// Unsaved records from HERB ("Edit" on a draft): the form opens with them filled in.
    var prefill: [LogChange] = []

    var body: some View {
        let pre = Prefill(changes: prefill)
        switch kind {
        case .prospects: ProspectForm(editingID: editingID, prefill: pre)
        case .closings: ClosingForm(editingID: editingID, prefill: pre)
        case .income: IncomeForm(editingID: editingID, prefill: pre)
        case .expenses: ExpenseForm(editingID: editingID, prefill: pre)
        case .trips: TripForm(editingID: editingID, prefill: pre)
        case .activities: ActivityForm(editingID: editingID, prefill: pre)
        }
    }
}

/// Records HERB drafted but hasn't saved, for pre-filling a form.
struct Prefill {
    var changes: [LogChange] = []

    var prospect: ProspectRecord? { changes.lazy.compactMap { if case .upsertProspect(let r) = $0 { r } else { nil } }.first }
    var closing: ClosingRecord? { changes.lazy.compactMap { if case .upsertClosing(let r) = $0 { r } else { nil } }.first }
    var income: IncomeRecord? { changes.lazy.compactMap { if case .upsertIncome(let r) = $0 { r } else { nil } }.first }
    var expense: ExpenseRecord? { changes.lazy.compactMap { if case .upsertExpense(let r) = $0 { r } else { nil } }.first }
    var trip: TripRecord? { changes.lazy.compactMap { if case .upsertTrip(let r) = $0 { r } else { nil } }.first }
    var activity: ActivityRecord? { changes.lazy.compactMap { if case .upsertActivity(let r) = $0 { r } else { nil } }.first }

    /// A source's name, whether it already exists or HERB would create it.
    func sourceName(_ id: RecordID?, in book: LogBook) -> String {
        guard let id else { return "" }
        for c in changes { if case .addSource(let s) = c, s.id == id { return s.name } }
        return book.sourceName(id) ?? ""
    }
}

/// Save · Save & Next · Cancel (design §10).
struct FormToolbar: ToolbarContent {
    @Environment(\.dismiss) private var dismiss
    let canSave: Bool
    var showNext = true
    let save: () -> Bool
    let reset: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { if save() { dismiss() } }.disabled(!canSave).bold()
        }
        if showNext {
            ToolbarItem(placement: .formBottom) {
                Button("Save & Next") { if save() { reset() } }.disabled(!canSave)
            }
        }
    }
}
