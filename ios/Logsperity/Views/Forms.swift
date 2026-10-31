import LogsperityCore
import SwiftUI

// The six input screens (design §10). Each loads the record being edited, or a new one dated today.

// MARK: - Prospect (§10.1)

struct ProspectForm: View {
    @Environment(AppModel.self) private var model
    var editingID: RecordID?
    var prefill = Prefill()
    @State private var p = ProspectRecord(date: Day.today())
    @State private var source = ""
    @State private var referrerIsPastClient = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Contact") {
                TextField("First name(s)", text: $p.firstNames).keyboard(.name).textContentType(.givenName)
                TextField("Last name", text: $p.lastName).keyboard(.name).textContentType(.familyName)
                TextField("Phone", text: $p.phone1.orEmpty).keyboard(.phone)
                TextField("Email", text: $p.email1.orEmpty).keyboard(.email)
                TextField("Address", text: $p.address.orEmpty).textContentType(.fullStreetAddress)
                TextField("Zip", text: $p.zip.orEmpty).keyboard(.number)
                DatePicker("Date", selection: $p.date.asDate, displayedComponents: .date)
            }
            AttributionSection(attribution: $p.attribution, sourceName: $source)
            Section {
                Toggle("Referred by a past client", isOn: $referrerIsPastClient)
            } footer: {
                Text(source.isEmpty
                     ? "No source yet? Save it anyway — it waits in the Review queue as \"Where did they come from?\""
                     : "A referral from a past client counts under Clients (rule R2).")
            }
            Section("Follow-up") {
                StrengthPicker(strength: $p.strength)
                Picker("Plan of action", selection: $p.planOfAction) {
                    Text("None").tag(String?.none)
                    ForEach(Taxonomy.planOfAction, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                FollowUpPicker(followUp: $p.followUp, from: p.date)
            }
            Section("Notes") { TextField("Notes", text: $p.notes.orEmpty, axis: .vertical).lineLimit(2...6) }
        }
        .navigationTitle(editingID == nil ? "New prospect" : "Prospect").inlineTitle()
        .toolbar { FormToolbar(canSave: canSave, showNext: editingID == nil, save: save, reset: reset) }
        .onAppear(perform: load)
    }

    private var canSave: Bool {
        !(p.firstNames.isEmpty && p.lastName.isEmpty) && p.attribution.pillar != nil && p.attribution.categoryID != nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = prefill.prospect {
            p = r
            source = prefill.sourceName(r.attribution.sourceID, in: model.book)
        } else if let id = editingID, let r = model.book.prospects.first(where: { $0.id == id }) {
            p = r
            source = model.sourceName(r.attribution.sourceID)
        } else {
            p = ProspectRecord(date: model.today)
        }
    }

    private func save() -> Bool {
        p.attribution.sourceID = model.sourceID(named: source)
        p.attribution = p.attribution.normalized()
        LogRules.applyPastClientReferral(&p, referrerIsPastClient: referrerIsPastClient)
        if p.attribution.sourceID == nil {  // decision D3: unknown source → Review queue
            p.reviewed = false
            if !(p.notes ?? "").contains("HERB: still need the source.") {
                p.notes = [p.notes, "HERB: still need the source."].compactMap { $0 }.joined(separator: " ")
            }
        } else if editingID == nil || (p.notes ?? "").contains("HERB: still need the source.") {
            p.notes = p.notes?.replacingOccurrences(of: "HERB: still need the source.", with: "").trimmingCharacters(in: .whitespaces)
            if p.notes?.isEmpty == true { p.notes = nil }
            p.reviewed = true
        }
        if p.followUp == nil { p.followUp = LogRules.defaultFollowUp(strength: p.strength, from: p.date) }
        model.save(p)
        return true
    }

    private func reset() {
        let keep = p.attribution
        p = ProspectRecord(date: p.date)
        p.attribution = keep
        referrerIsPastClient = false
    }
}

// MARK: - Closing (§10.2)

struct ClosingForm: View {
    @Environment(AppModel.self) private var model
    var editingID: RecordID?
    var prefill = Prefill()
    @State private var c = ClosingRecord(date: Day.today())
    @State private var newClient = false
    @State private var first = ""
    @State private var last = ""
    @State private var source = ""
    @State private var addToIncome = true
    @State private var extra: [ExtraTx] = []
    @State private var error: String?
    @State private var loaded = false

    struct ExtraTx: Identifiable { let id = UUID(); var size: Double?; var income: Double? }

    var body: some View {
        Form {
            Section("Client") {
                if editingID == nil { Toggle("New client (not in Prospects)", isOn: $newClient) }
                if newClient {
                    TextField("First name(s)", text: $first).keyboard(.name)
                    TextField("Last name", text: $last).keyboard(.name)
                } else {
                    Picker("Choose from Prospects", selection: $c.prospectID) {
                        Text("Choose").tag(RecordID?.none)
                        ForEach(openProspects) { Text("\($0.fullName) · \(Format.shortDate($0.date))").tag(RecordID?.some($0.id)) }
                    }
                    .onChange(of: c.prospectID) { _, id in
                        if let p = model.book.prospects.first(where: { $0.id == id }) {
                            c.attribution = p.attribution
                            source = model.sourceName(p.attribution.sourceID)
                        }
                    }
                }
                DatePicker("Closing date", selection: $c.date.asDate, displayedComponents: .date)
            }
            if newClient { AttributionSection(attribution: $c.attribution, sourceName: $source) }
            Section("Transaction") {
                MoneyField("Transaction size", value: $c.transactionSize.optional)
                MoneyField("Income earned", value: $c.income.optional)
                if c.income == 0, c.transactionSize > 0 {
                    let yieldPct = model.ledger().avgClosingIncome.flatMap { inc in model.ledger().avgVolume.map { inc / $0 } } ?? model.plan.outputs.yieldPct
                    Button("Use your usual yield: \(Format.money(c.transactionSize * yieldPct))") {
                        c.income = (c.transactionSize * yieldPct).rounded()
                    }
                }
                if editingID == nil { Toggle("Add to Income Log", isOn: $addToIncome) }
            }
            if editingID == nil {
                Section {
                    ForEach($extra) { $x in
                        MoneyField("Size", value: $x.size)
                        MoneyField("Income", value: $x.income)
                    }
                    Button("Add a transaction") { extra.append(ExtraTx()) }
                } header: { Text("Additional transactions") } footer: {
                    Text("Other deals for the same client go on the Income log, not as extra closings (rule R3).")
                }
            }
            Section("After closing") {
                Picker("Request referral or review", selection: $c.referralRequest) {
                    ForEach(ReferralRequest.allCases) { Text($0.name).tag($0) }
                }
                DatePicker("Post-closing follow-up", selection: Binding(get: { (c.postClosingFollowUp ?? c.date.adding(days: 180)).date() },
                                                                        set: { c.postClosingFollowUp = Day(date: $0) }), displayedComponents: .date)
                TextField("Notes", text: $c.notes.orEmpty, axis: .vertical)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(editingID == nil ? "New closing" : "Closing").inlineTitle()
        .toolbar { FormToolbar(canSave: canSave, showNext: false, save: save, reset: {}) }
        .onAppear(perform: load)
    }

    private var openProspects: [ProspectRecord] {
        let closed = Set(model.book.closings.filter { $0.id != c.id }.compactMap(\.prospectID))
        return model.book.prospects.filter { !closed.contains($0.id) }.sorted { $0.date > $1.date }
    }

    private var canSave: Bool {
        (newClient ? !(first.isEmpty && last.isEmpty) && c.attribution.pillar != nil : c.prospectID != nil) && c.transactionSize > 0
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = prefill.closing {
            c = r
            if let p = prefill.prospect, !model.book.prospects.contains(where: { $0.id == p.id }) {
                newClient = true
                first = p.firstNames
                last = p.lastName
                source = prefill.sourceName(p.attribution.sourceID, in: model.book)
                c.prospectID = nil
            }
        } else if let id = editingID, let r = model.book.closings.first(where: { $0.id == id }) { c = r } else { c = ClosingRecord(date: model.today) }
        if c.postClosingFollowUp == nil { c.postClosingFollowUp = c.date.adding(days: 180) }
    }

    private func save() -> Bool {
        if newClient {
            var p = ProspectRecord(date: c.date)
            p.firstNames = first
            p.lastName = last
            p.attribution = c.attribution
            p.attribution.sourceID = model.sourceID(named: source)
            p.attribution = p.attribution.normalized()
            p.strength = .hot
            model.save(p)
            c.prospectID = p.id
            c.attribution = p.attribution
        }
        do {
            try model.save(c, addToIncome: addToIncome,
                           additional: extra.compactMap { x in x.size.flatMap { s in x.income.map { (s, $0) } } })
            return true
        } catch {
            self.error = "\(error)"
            return false
        }
    }
}

// MARK: - Income (§10.3)

struct IncomeForm: View {
    @Environment(AppModel.self) private var model
    var editingID: RecordID?
    var prefill = Prefill()
    @State private var i = IncomeRecord(date: Day.today())
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: $i.mode) {
                    Text("Transaction").tag(IncomeMode.transaction)
                    Text("Batch").tag(IncomeMode.batch)
                    Text("By type").tag(IncomeMode.type)
                }
                .pickerStyle(.segmented)
                DatePicker("Date", selection: $i.date.asDate, displayedComponents: .date)
            }
            switch i.mode {
            case .transaction:
                Section {
                    Picker("Closing", selection: $i.closingID) {
                        Text("Enter by hand").tag(RecordID?.none)
                        ForEach(model.book.closings.sorted { $0.date > $1.date }) { c in
                            Text("\(model.book.prospects.first { $0.id == c.prospectID }?.fullName ?? "Closing") · \(Format.shortDate(c.date))").tag(RecordID?.some(c.id))
                        }
                    }
                    .onChange(of: i.closingID) { _, id in
                        if let c = model.book.closings.first(where: { $0.id == id }) {
                            i.attribution = c.attribution
                            i.transactionSize = c.transactionSize
                            i.lastName = model.book.prospects.first { $0.id == c.prospectID }?.lastName
                        }
                    }
                    if i.closingID == nil {
                        TextField("Last name", text: $i.lastName.orEmpty)
                        MoneyField("Transaction size", value: $i.transactionSize)
                    }
                } footer: { Text("Use this for repeat clients (rule R4) or when \"Add to Income Log\" wasn't used.") }
            case .batch:
                Section {
                    Picker("Type", selection: $i.type) { ForEach(IncomeType.allCases) { Text($0.name).tag(IncomeType?.some($0)) } }
                    Stepper("Transactions: \(i.transactionCount ?? 1)", value: Binding(get: { i.transactionCount ?? 1 }, set: { i.transactionCount = $0 }), in: 1...50)
                    if i.amount > 0 { LabeledContent("Average per transaction", value: Format.money(i.amount / Double(i.transactionCount ?? 1))) }
                }
            case .type:
                Section {
                    Picker("Type", selection: $i.type) { ForEach(IncomeType.allCases) { Text($0.name).tag(IncomeType?.some($0)) } }
                    Picker("Pillar (optional)", selection: $i.attribution.pillar) {
                        Text("None").tag(Pillar?.none)
                        ForEach(Pillar.allCases) { Text($0.name).tag(Pillar?.some($0)) }
                    }
                }
            }
            Section {
                MoneyField("Amount", value: $i.amount.optional)
                TextField("Payer", text: $i.payer.orEmpty)
                Toggle("1099 expected", isOn: $i.expect1099)
                TextField("Notes", text: $i.notes.orEmpty, axis: .vertical)
            }
        }
        .navigationTitle(editingID == nil ? "New income" : "Income").inlineTitle()
        .toolbar { FormToolbar(canSave: i.amount > 0, showNext: editingID == nil, save: save, reset: { i = IncomeRecord(date: i.date) }) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = prefill.income { i = r } else if let id = editingID, let r = model.book.income.first(where: { $0.id == id }) { i = r } else {
                i = IncomeRecord(date: model.today)
                i.type = .commission
            }
        }
        .onChange(of: i.mode) { _, m in if m != .transaction, i.type == nil { i.type = .commission } }
    }

    private func save() -> Bool {
        if i.mode == .transaction { i.transactionCount = 1; i.type = .commission }
        model.save(i)
        return true
    }
}

// MARK: - Expense (§10.4)

struct ExpenseForm: View {
    @Environment(AppModel.self) private var model
    var editingID: RecordID?
    var prefill = Prefill()
    @State private var e = ExpenseRecord(date: Day.today())
    @State private var source = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $e.date.asDate, displayedComponents: .date)
                TextField("Vendor", text: $e.vendor)
                MoneyField("Amount", value: $e.amount.optional)
            }
            Section("Category") {
                Picker("Group", selection: $e.group) {
                    Section("Pillars") { ForEach(ExpenseGroup.allCases.filter { $0.pillar != nil }) { Text($0.name).tag($0) } }
                    Section("No pillar") { ForEach(ExpenseGroup.allCases.filter { $0.pillar == nil }) { Text($0.name).tag($0) } }
                }
                .onChange(of: e.group) { _, g in
                    if e.category?.group != g { e.categoryID = "" }
                    if g == .relationships, e.relationshipSubPillar == nil { e.relationshipSubPillar = .professional }
                }
                if e.group == .relationships {
                    Picker("Relationship", selection: $e.relationshipSubPillar) {
                        Text("Professional").tag(SubPillar?.some(.professional))
                        Text("Personal").tag(SubPillar?.some(.personal))
                    }
                }
                Picker("Category", selection: $e.categoryID) {
                    Text("Choose").tag("")
                    ForEach(Taxonomy.expenseCategories(in: e.group)) { Text($0.name).tag($0.id) }
                }
                if let cat = e.category { LabeledContent("IRS category", value: cat.irs) }
            }
            Section {
                SourceField(label: "For / with", name: $source, prompt: "Person or source (optional)")
                if e.category?.name == "Meal" || e.category?.name == "Entertainment" {
                    TextField("With whom", text: $e.withWhom.orEmpty)
                    TextField("Business purpose", text: $e.purpose.orEmpty)
                }
                TextField("Check #", text: $e.checkNumber.orEmpty).keyboard(.number)
                TextField("Card last 4", text: $e.cardLast4.orEmpty).keyboard(.number)
                Toggle("I have the receipt", isOn: $e.hasReceipt)
                TextField("Notes", text: $e.notes.orEmpty, axis: .vertical)
            } header: { Text("Details") } footer: {
                if e.amount >= 75 && !e.hasReceipt { Text("Keep a receipt for expenses of $75 or more.") }
            }
        }
        .navigationTitle(editingID == nil ? "New expense" : "Expense").inlineTitle()
        .toolbar { FormToolbar(canSave: e.amount > 0 && !e.categoryID.isEmpty, showNext: editingID == nil, save: save, reset: reset) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = prefill.expense {
                e = r
                source = prefill.sourceName(r.sourceID, in: model.book)
            } else if let id = editingID, let r = model.book.expenses.first(where: { $0.id == id }) {
                e = r
                source = model.sourceName(r.sourceID)
            } else { e = ExpenseRecord(date: model.today) }
        }
    }

    private func save() -> Bool {
        e.sourceID = model.sourceID(named: source)
        if e.group != .relationships { e.relationshipSubPillar = nil }
        model.save(e)
        return true
    }

    private func reset() {
        let (d, g) = (e.date, e.group)
        e = ExpenseRecord(date: d)
        e.group = g
        source = ""
    }
}

// MARK: - Mileage (§10.5)

struct TripForm: View {
    @Environment(AppModel.self) private var model
    var editingID: RecordID?
    var prefill = Prefill()
    @State private var t = TripRecord(date: Day.today())
    @State private var useMiles = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $t.date.asDate, displayedComponents: .date)
                Toggle("Business trip", isOn: $t.isBusiness)
                Picker("Reason", selection: $t.reason) {
                    Text("Choose").tag("")
                    ForEach(reasons, id: \.self) { Text($0).tag($0) }
                }
                TextField("Destination", text: $t.destination)
                if !t.destination.isEmpty || destinations.isEmpty {} else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(destinations, id: \.self) { d in Button(d) { t.destination = d }.buttonStyle(.bordered).controlSize(.small) } }
                    }
                }
            }
            Section {
                Picker("Distance", selection: $useMiles) {
                    Text("Odometer").tag(false)
                    Text("Miles").tag(true)
                }
                .pickerStyle(.segmented)
                if useMiles {
                    NumberField(label: "Miles", value: $t.gpsMiles)
                } else {
                    NumberField(label: "Beginning odometer", value: $t.odometerStart)
                    NumberField(label: "Ending odometer", value: $t.odometerEnd)
                }
                LabeledContent("Total", value: Format.miles(t.miles))
                if t.isBusiness {
                    LabeledContent("Deduction", value: Format.money(t.miles * Taxonomy.mileageRate(on: t.date), cents: true))
                }
            } footer: { Text("The beginning odometer starts from your last trip's ending (rule R6).") }
            Section { TextField("Notes", text: $t.notes.orEmpty, axis: .vertical) }
        }
        .navigationTitle(editingID == nil ? "New trip" : "Trip").inlineTitle()
        .toolbar { FormToolbar(canSave: t.miles > 0 && !t.reason.isEmpty, showNext: editingID == nil, save: save, reset: reset) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = prefill.trip ?? editingID.flatMap({ id in model.book.trips.first { $0.id == id } }) {
                t = r
                useMiles = r.gpsMiles != nil
            } else { reset() }
        }
        .onChange(of: useMiles) { _, m in if m { t.odometerStart = nil; t.odometerEnd = nil } else { t.gpsMiles = nil } }
    }

    private var reasons: [String] {
        Array(Set(Taxonomy.mileageReasons + model.book.trips.map(\.reason).filter { !$0.isEmpty })).sorted()
    }

    private var destinations: [String] {
        let counts = Dictionary(grouping: model.book.trips.map(\.destination).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(6).map(\.key)
    }

    private func save() -> Bool { model.save(t); return true }

    private func reset() {
        let d = editingID == nil && loaded ? t.date : model.today
        t = TripRecord(date: d)
        t.odometerStart = LogRules.defaultOdometerStart(for: d, trips: model.book.trips)
    }
}

// MARK: - Activity (§10.6)

struct ActivityForm: View {
    @Environment(AppModel.self) private var model
    var editingID: RecordID?
    var prefill = Prefill()
    @State private var a = ActivityRecord(date: Day.today())
    @State private var source = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section { DatePicker("Date", selection: $a.date.asDate, displayedComponents: .date) }
            AttributionSection(attribution: $a.attribution, sourceName: $source, showCategory: false, sourceLabel: "With whom")
            Section {
                Stepper("Time: \(Format.spokenMinutes(a.minutes))", value: $a.minutes, in: 15...720, step: 15)
                TextField("Notes", text: $a.notes.orEmpty, axis: .vertical)
            } footer: { Text("Business-building time, in 15-minute steps.") }
        }
        .navigationTitle(editingID == nil ? "New activity" : "Activity").inlineTitle()
        .toolbar { FormToolbar(canSave: a.attribution.activityID != nil, showNext: editingID == nil, save: save,
                               reset: { let d = a.date; a = ActivityRecord(date: d); a.minutes = 60; source = "" }) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = prefill.activity {
                a = r
                source = prefill.sourceName(r.attribution.sourceID, in: model.book)
            } else if let id = editingID, let r = model.book.activities.first(where: { $0.id == id }) {
                a = r
                source = model.sourceName(r.attribution.sourceID)
            } else {
                a = ActivityRecord(date: model.today)
                a.minutes = 60
            }
        }
    }

    private func save() -> Bool {
        a.attribution.sourceID = model.sourceID(named: source)
        a.attribution = a.attribution.normalized()
        a.minutes = LogRules.roundMinutes(a.minutes)
        model.save(a)
        return true
    }
}
