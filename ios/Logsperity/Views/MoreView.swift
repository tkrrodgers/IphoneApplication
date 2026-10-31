import LogsperityCore
import SwiftUI

/// More (design §7): Account · Business Plan Set Up · Input Cheat Sheet · HERB · Help · Data & privacy.
struct MoreView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmErase = false
    @State private var confirmSample = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AccountScreen() } label: { Label("Account", systemImage: "person.crop.circle") }
                    NavigationLink { PlanScreen() } label: { Label("Business Plan Set Up", systemImage: "target") }
                    NavigationLink { CheatSheetView() } label: { Label("Input Cheat Sheet", systemImage: "book") }
                    NavigationLink { HerbSettingsView() } label: { Label("HERB", systemImage: "waveform") }
                }
                Section("Help") {
                    Link(destination: AppConfig.supportURL) {
                        Label("Email customer service", systemImage: "envelope")
                    }
                    NavigationLink { AboutPilotView() } label: { Label("About this pilot", systemImage: "info.circle") }
                }
                Section {
                    if let url = model.exportURL() {
                        ShareLink(item: url) { Label("Export my data", systemImage: "square.and.arrow.up") }
                    }
                    Button { confirmSample = true } label: { Label("Load a sample year", systemImage: "wand.and.stars") }
                    Button(role: .destructive) { confirmErase = true } label: { Label("Erase all data", systemImage: "trash") }
                } header: { Text("Data & privacy") } footer: {
                    Text("Your logs are stored only on this iPhone. Prosperity Simplified does not receive them."
                         + (model.settings.usingSampleData ? " You're looking at sample data for a fictional mortgage broker." : ""))
                }
            }
            .navigationTitle("More")
            .confirmationDialog("Replace your logs with a sample year?", isPresented: $confirmSample, titleVisibility: .visible) {
                Button("Replace with sample data", role: .destructive) { model.loadSampleYear() }
            } message: { Text("This erases what you've logged.") }
            .confirmationDialog("Erase everything you've logged?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) { model.eraseAllData() }
            } message: { Text("This can't be undone. Export your data first if you want a copy.") }
        }
    }
}

struct AccountScreen: View {
    @Environment(AppModel.self) private var model
    @State private var settings = AppSettings()

    var body: some View {
        AccountForm(settings: $settings)
            .navigationTitle("Account")
            .onAppear { settings = model.settings }
            .onDisappear { let s = settings; model.updateSettings { $0 = s } }
            .safeAreaInset(edge: .bottom) {
                Text("Pilot: free while you test it. Subscriptions will go through Apple — Logsperity never asks for a card number.")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
    }
}

struct PlanScreen: View {
    @Environment(AppModel.self) private var model
    @State private var year = Day.today().year
    @State private var inputs = PlanInputs.default

    var body: some View {
        PlanForm(inputs: $inputs)
            .navigationTitle("\(String(year)) business plan")
            .toolbar {
                Menu(String(year)) {
                    ForEach((year - 2)...(year + 1), id: \.self) { y in Button(String(y)) { year = y } }
                }
            }
            .onAppear { year = model.today.year; inputs = model.book.plan(for: year) }
            .onChange(of: year) { _, y in inputs = model.book.plan(for: y) }
            .onDisappear { try? model.savePlan(inputs, year: year) }
    }
}

struct HerbSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("Follow-up questions", selection: Binding(get: { model.settings.questionStyle },
                                                               set: { v in model.updateSettings { $0.questionStyle = v } })) {
                    Text("Quick — required only").tag("quick")
                    Text("Balanced").tag("balanced")
                    Text("Thorough — everything").tag("thorough")
                }
                .pickerStyle(.inline)
            } footer: { Text("HERB always asks where a new prospect came from. \"I don't know\" is fine — it waits in the Review queue.") }
            Section {
                Toggle("HERB speaks replies", isOn: Binding(get: { model.settings.herbSpeaks }, set: { v in model.updateSettings { $0.herbSpeaks = v } }))
                if !model.settings.herbSkipCounts.filter({ $0.value >= 3 }).isEmpty {
                    Button("Ask me about skipped fields again") { model.updateSettings { $0.herbSkipCounts = [:] } }
                }
            }
            Section("Daily reminder") {
                Toggle("Remind me to log", isOn: Binding(get: { model.settings.remindersOn }, set: { on in
                    Task {
                        let ok = on ? await Reminders.requestPermission() : false
                        model.updateSettings { $0.remindersOn = ok }
                    }
                }))
                if model.settings.remindersOn {
                    ReminderTimePicker(minutes: Binding(get: { model.settings.reminderMinutes }, set: { v in model.updateSettings { $0.reminderMinutes = v } }))
                }
            }
        }
        .navigationTitle("HERB")
    }
}

/// The Input Cheat Sheet (FR-24): pillars, categories and activities, searchable.
struct CheatSheetView: View {
    @State private var search = ""

    var body: some View {
        List {
            Section {
                Text("**Pillar** — where business comes from. **Category** — who or what the lead is. **Source** — the specific person, company or venue. **Activity** — what you did to produce it.")
                    .font(.subheadline)
            }
            ForEach(Pillar.allCases) { p in
                let cats = Taxonomy.categories(in: p).filter(matches)
                let acts = Taxonomy.activities(in: p).filter(matches)
                if !cats.isEmpty || !acts.isEmpty {
                    Section(p.name) {
                        if !cats.isEmpty { LabeledContent("Categories") { Text(cats.map(\.name).joined(separator: ", ")).font(.caption) } }
                        if !acts.isEmpty { LabeledContent("Activities") { Text(acts.map(\.name).joined(separator: ", ")).font(.caption) } }
                    }
                }
            }
            Section("Rules HERB follows for you") {
                Text("Log every inquiry as a prospect, however weak (R1).")
                Text("A referral from a past client goes under Clients (R2).")
                Text("Several deals for one client: one closing, the rest as income (R3, R4).")
                Text("One closing per prospect (R5).")
                Text("A trip's beginning odometer starts at the last ending (R6).")
            }
            .font(.subheadline)
        }
        .searchable(text: $search)
        .navigationTitle("Input Cheat Sheet")
    }

    private func matches(_ i: TaxonomyItem) -> Bool { search.isEmpty || i.name.localizedCaseInsensitiveContains(search) }
}

struct AboutPilotView: View {
    var body: some View {
        List {
            Section {
                Text("Thanks for testing Logsperity. This pilot covers the six logs, reports, coaching and HERB by text or voice.")
                Text("Coming next: iCloud sync between your devices, receipt scanning, automatic mileage, calendar activities and bank statement import.")
                Text("Send feedback from TestFlight: take a screenshot in the app and tap Share Beta Feedback.")
            }
            Section {
                Text("Tax notes (IRS categories, mileage rates) are for organizing your records, not tax advice. Review them with your CPA.")
            }
            .font(.footnote)
        }
        .navigationTitle("About this pilot")
    }
}
