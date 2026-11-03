import LogsperityCore
import SwiftUI

// The six input screens (design §10). Each loads the record being edited, or a new one dated today.

// MARK: - Prospect (§10.1)

struct ProspectForm: View {
    @Environment(AppModel.self) private var model
    var editingID: RecordID?
    var prefill = Prefill()
    @State private var p = ProspectRecord(date: Day.today())
    /// Couples: a second first name, saved as "Tom & Ana".
    @State private var first = ""
    @State private var second = ""
    @State private var source = ""
    @State private var referrerIsPastClient = false
    @State private var loaded = false

    // The order and the red required fields follow the Prospects Input screen: date, names, pillar, category, source
    // and activity are what the numbers need; the rest is optional.
    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $p.date.asDate, displayedComponents: .date)
                TextField(text: $p.lastName, prompt: requiredPrompt("Last name", p.lastName)) { Text("Last name") }
                    .keyboard(.name).textContentType(.familyName)
                TextField(text: $first, prompt: requiredPrompt("First name", first)) { Text("First name") }
                    .keyboard(.name).textContentType(.givenName)
                TextField("Second first name (couples)", text: $second).keyboard(.name)
            } header: { Text("Who") } footer: {
                Text("Fields in red are needed for your numbers. In a hurry? Save it as a hint and HERB will ask for the rest later.")
            }
            AttributionSection(attribution: $p.attribution, sourceName: $source, required: true)
            Section {
                Toggle("Referred by a past client", isOn: $referrerIsPastClient)
            } footer: { Text("A referral from a past client counts under Clients (rule R2).") }
            Section("Contact") {
                TextField("Phone 1", text: $p.phone1.orEmpty).keyboard(.phone)
                TextField("Phone 2", text: $p.phone2.orEmpty).keyboard(.phone)
                TextField("Email 1", text: $p.email1.orEmpty).keyboard(.email)
                TextField("Email 2", text: $p.email2.orEmpty).keyboard(.email)
                TextField("Mailing address", text: $p.address.orEmpty).textContentType(.streetAddressLine1)
                TextField("City", text: $p.city.orEmpty).textContentType(.addressCity)
                TextField("State", text: $p.state.orEmpty).textContentType(.addressState)
                TextField("Postal code", text: $p.zip.orEmpty).keyboard(.number).textContentType(.postalCode)
            }
            Section("Follow-up") {
                StrengthPicker(strength: $p.strength)
                Picker("Plan of action", selection: $p.planOfAction) {
                    Text("None").tag(String?.none)
                    ForEach(Taxonomy.planOfAction, id: \.self) { Text($0).tag(String?.some($0)) }
                    if let plan = p.planOfAction, !Taxonomy.planOfAction.contains(plan) { Text(plan).tag(String?.some(plan)) }  // a retired plan
                }
                FollowUpPicker(followUp: $p.followUp, from: p.date)
            }
            Section("Notes") { TextField("Notes", text: $p.notes.orEmpty, axis: .vertical).lineLimit(2...6) }
        }
        .navigationTitle(editingID == nil ? "New prospect" : "Prospect").inlineTitle()
        .toolbar { FormToolbar(canSave: hasSomething, showNext: editingID == nil, isHint: !isComplete, save: save, reset: reset) }
        .onAppear(perform: load)
    }

    private func requiredPrompt(_ label: String, _ value: String) -> Text {
        Text(label).foregroundStyle(value.isEmpty ? Color.red.opacity(0.75) : Color.secondary)
    }

    private var firstNames: String {
        [first, second].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " & ")
    }

    /// Everything the numbers need (the red fields).
    private var isComplete: Bool {
        !first.isEmpty && !p.lastName.isEmpty && p.attribution.pillar != nil && p.attribution.categoryID != nil
            && !source.trimmingCharacters(in: .whitespaces).isEmpty && p.attribution.activityID != nil
    }

    /// Enough to save at least a hint.
    private var hasSomething: Bool {
        !(first + second + p.lastName + source).trimmingCharacters(in: .whitespaces).isEmpty
            || !(p.notes ?? "").isEmpty || !(p.phone1 ?? "").isEmpty
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
        let names = p.firstNames.components(separatedBy: " & ")
        first = names.first ?? ""
        second = names.dropFirst().joined(separator: " & ")
        p.notes = LogRules.removingHintNote(p.notes)  // the marker is HERB's; it's set again on save if still needed
    }

    private func save() -> Bool {
        p.firstNames = firstNames
        p.attribution.sourceID = model.sourceID(named: source)
        p.attribution = p.attribution.normalized()
        LogRules.applyPastClientReferral(&p, referrerIsPastClient: referrerIsPastClient)
        LogRules.markHint(&p)  // anything missing → a hint in the Review queue (decision D3 for an unknown source)
        if p.followUp == nil { p.followUp = LogRules.defaultFollowUp(strength: p.strength, from: p.date) }
        model.save(p)
        return true
    }

    /// Save & Next: a blank form, keeping only the date.
    private func reset() {
        p = ProspectRecord(date: p.date)
        first = ""
        second = ""
        source = ""
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
                        ForEach(openProspects) { p in
                            Text([p.lastName, p.firstNames].filter { !$0.isEmpty }.joined(separator: ", ")).tag(RecordID?.some(p.id))
                        }
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
        return model.book.prospects.filter { !closed.contains($0.id) }.sorted {
            ($0.lastName.lowercased(), $0.firstNames.lowercased()) < ($1.lastName.lowercased(), $1.firstNames.lowercased())
        }
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
    /// A new expense starts with no group chosen (not "General").
    @State private var groupChosen = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $e.date.asDate, displayedComponents: .date)
                TextField("Vendor", text: $e.vendor).keyboard(.name)  // capitalizes each word
                MoneyField("Amount", value: $e.amount.optional)
            }
            Section {
                Picker(selection: Binding<ExpenseGroup?>(get: { groupChosen ? e.group : nil }, set: { g in
                    guard let g else { return }
                    groupChosen = true
                    if e.category?.group != g { e.categoryID = "" }
                    e.group = g
                    if g == .relationships, e.relationshipSubPillar == nil { e.relationshipSubPillar = .professional }
                })) {
                    if !groupChosen { Text("Choose").tag(ExpenseGroup?.none) }
                    Section("Pillars") { ForEach(ExpenseGroup.allCases.filter { $0.pillar != nil }) { Text($0.name).tag(ExpenseGroup?.some($0)) } }
                    Section("No pillar") { ForEach(ExpenseGroup.allCases.filter { $0.pillar == nil }) { Text($0.name).tag(ExpenseGroup?.some($0)) } }
                } label: { RequiredLabel("Group", missing: !groupChosen) }
                if groupChosen && e.group == .relationships {
                    Picker("Relationship", selection: $e.relationshipSubPillar) {
                        Text("Professional").tag(SubPillar?.some(.professional))
                        Text("Personal").tag(SubPillar?.some(.personal))
                    }
                }
                if groupChosen {
                    Picker(selection: $e.categoryID) {
                        Text("Choose").tag("")
                        ForEach(Taxonomy.expenseCategories(in: e.group)) { Text($0.name).tag($0.id) }
                    } label: { RequiredLabel("Category", missing: e.categoryID.isEmpty) }
                }
                if let cat = e.category { LabeledContent("IRS category", value: cat.irs) }
            } header: { Text("Category") }
            Section {
                Toggle("Recurring monthly charge", isOn: Binding(get: { e.recurring == true }, set: { e.recurring = $0 ? true : nil }))
            } footer: {
                Text("Subscriptions and dues. At the start of each month HERB asks whether it's still running and logs it for you.")
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
        .toolbar { FormToolbar(canSave: e.amount > 0 || !e.vendor.isEmpty, showNext: editingID == nil,
                               isHint: e.amount <= 0 || e.categoryID.isEmpty, save: save, reset: reset) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = prefill.expense {
                e = r
                source = prefill.sourceName(r.sourceID, in: model.book)
                groupChosen = true
            } else if let id = editingID, let r = model.book.expenses.first(where: { $0.id == id }) {
                e = r
                source = model.sourceName(r.sourceID)
                groupChosen = !r.categoryID.isEmpty || !LogRules.isHint(r.notes)
            } else { e = ExpenseRecord(date: model.today) }
            e.notes = LogRules.removingHintNote(e.notes)
        }
    }

    private func save() -> Bool {
        e.vendor = LogRules.capitalizedWords(e.vendor.trimmingCharacters(in: .whitespaces))
        e.sourceID = model.sourceID(named: source)
        if e.group != .relationships { e.relationshipSubPillar = nil }
        LogRules.markHint(&e)
        model.save(e)
        return true
    }

    /// Save & Next: a blank form, keeping only the date.
    private func reset() {
        e = ExpenseRecord(date: e.date)
        groupChosen = false
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
    @FocusState private var reasonFocused: Bool

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $t.date.asDate, displayedComponents: .date)
                Toggle("Business trip", isOn: $t.isBusiness)
                TextField(text: $t.reason, prompt: Text("Reason").foregroundStyle(t.reason.isEmpty ? Color.red.opacity(0.75) : Color.secondary)) {
                    Text("Reason")
                }
                .focused($reasonFocused)
                if reasonFocused || t.reason.isEmpty {
                    let matches = reasons.filter { t.reason.isEmpty || ($0.localizedCaseInsensitiveContains(t.reason) && $0 != t.reason) }
                    if !matches.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(matches.prefix(12), id: \.self) { r in
                                    Button(r) { t.reason = r; reasonFocused = false }.buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                    }
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
        .toolbar { FormToolbar(canSave: t.miles > 0 || !t.reason.isEmpty || !t.destination.isEmpty, showNext: editingID == nil,
                               isHint: t.miles <= 0 || t.reason.trimmingCharacters(in: .whitespaces).isEmpty, save: save, reset: reset) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = prefill.trip ?? editingID.flatMap({ id in model.book.trips.first { $0.id == id } }) {
                t = r
                t.notes = LogRules.removingHintNote(t.notes)
                useMiles = r.gpsMiles != nil
            } else { reset() }
        }
        .onChange(of: useMiles) { _, m in if m { t.odometerStart = nil; t.odometerEnd = nil } else { t.gpsMiles = nil } }
    }

    /// Reasons you've used before, most used first, then the standard list.
    private var reasons: [String] {
        let counts = Dictionary(grouping: model.book.trips.map(\.reason).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        let used = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        return used + Taxonomy.mileageReasons.filter { !counts.keys.contains($0) }
    }

    private var destinations: [String] {
        let counts = Dictionary(grouping: model.book.trips.map(\.destination).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(6).map(\.key)
    }

    private func save() -> Bool {
        t.reason = t.reason.trimmingCharacters(in: .whitespaces)
        LogRules.markHint(&t)
        model.save(t)
        return true
    }

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
