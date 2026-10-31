import LogsperityCore
import SwiftUI

/// First run (design §8.2): welcome, account set up, business plan, reminder, HERB style.
/// The pilot has no sign-in: data stays on this iPhone.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var settings = AppSettings()
    @State private var plan = PlanInputs.default

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: welcome
                case 1: AccountForm(settings: $settings).navigationTitle("About you")
                case 2: PlanForm(inputs: $plan).navigationTitle("Your business plan")
                default: finish
                }
            }
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .cancellationAction) { Button("Back") { step -= 1 } }
                }
                if step == 1 || step == 2 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Next") { step += 1 }
                            .disabled(step == 1 && (settings.name.isEmpty || settings.profession.isEmpty))
                            .disabled(step == 2 && plan.netProfitGoal > plan.grossIncomeGoal)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear { settings = model.settings }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Logsperity").font(.largeTitle.bold()).foregroundStyle(Color.brandBlue)
                Text("Know Your Numbers. Maximize Your Time. Multiply Your Prosperity.").font(.title3)
                VStack(alignment: .leading, spacing: 14) {
                    feature("square.and.pencil", "Six logs", "Prospects, closings, income, expenses, mileage and activity — about a minute a day.")
                    feature("chart.bar", "Your numbers", "Conversion, hourly rates, ROI by pillar and the Logsperity Index, calculated for you.")
                    feature("waveform", "HERB", "Say \"New prospect Kevin Morales, Ruth Alvarez sent him\" and HERB fills it in, asks what's missing, and saves only when you say yes.")
                    feature("lock.shield", "Private", "Everything stays on this iPhone. Prosperity Simplified receives nothing.")
                }
                Text("Pilot version — free while you test it.").font(.footnote).foregroundStyle(.secondary)
                Button { step = 1 } label: { Text("Get started").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Explore with a sample year first") {
                    model.loadSampleYear()
                    model.updateSettings { $0.onboarded = true; $0.name = SampleYear.ownerName; $0.profession = SampleYear.profession; $0.company = SampleYear.company }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.brandBlue).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }

    private var finish: some View {
        Form {
            Section {
                Toggle("Daily reminder to log", isOn: $settings.remindersOn)
                if settings.remindersOn { ReminderTimePicker(minutes: $settings.reminderMinutes) }
            } footer: { Text("One notification a day at your chosen time.") }
            Section("How much should HERB ask?") {
                Picker("Follow-up questions", selection: $settings.questionStyle) {
                    Text("Quick — required only").tag("quick")
                    Text("Balanced").tag("balanced")
                    Text("Thorough — everything").tag("thorough")
                }
                .pickerStyle(.inline).labelsHidden()
            }
            Section {
                Button("Start using Logsperity") {
                    Task {
                        if settings.remindersOn { settings.remindersOn = await Reminders.requestPermission() }
                        try? model.savePlan(plan, year: model.today.year)
                        var s = settings
                        s.onboarded = true
                        model.updateSettings { $0 = s }
                    }
                }
                .frame(maxWidth: .infinity).bold()
            }
        }
        .navigationTitle("Almost done")
    }
}

struct ReminderTimePicker: View {
    @Binding var minutes: Int
    var body: some View {
        Picker("Time", selection: $minutes) {
            ForEach(Array(stride(from: 6 * 60, through: 22 * 60, by: 30)), id: \.self) { m in
                Text(Self.label(m)).tag(m)
            }
        }
    }
    static func label(_ m: Int) -> String {
        let h = m / 60, mm = m % 60
        return String(format: "%d:%02d %@", h % 12 == 0 ? 12 : h % 12, mm, h < 12 ? "am" : "pm")
    }
}

/// Account Set Up fields (design §8.1). No payment fields: billing will go through Apple (D1).
struct AccountForm: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $settings.name).keyboard(.name).textContentType(.name)
                TextField("Title", text: $settings.title)
                TextField("Company", text: $settings.company).textContentType(.organizationName)
                Picker("Profession", selection: $settings.profession) {
                    Text("Choose").tag("")
                    ForEach(Taxonomy.professions, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Contact") {
                TextField("Email", text: $settings.email).keyboard(.email).textContentType(.emailAddress)
                TextField("Phone", text: $settings.phone).keyboard(.phone)
                TextField("Address", text: $settings.address).textContentType(.streetAddressLine1)
                TextField("Zip", text: $settings.zip).keyboard(.number).textContentType(.postalCode)
                TextField("City", text: $settings.city).textContentType(.addressCity)
                TextField("State", text: $settings.state).textContentType(.addressState)
            }
        }
    }
}

/// Business Plan Set Up (design §9) with the live "This Is Your Business" outputs.
struct PlanForm: View {
    @Binding var inputs: PlanInputs

    var body: some View {
        let o = inputs.outputs
        Form {
            Section {
                MoneyField("Annual gross income goal", value: $inputs.grossIncomeGoal.optional)
                MoneyField("Annual net profit goal", value: $inputs.netProfitGoal.optional)
                MoneyField("Average commission per transaction", value: $inputs.avgCommission.optional)
                MoneyField("Average transaction size", value: $inputs.avgTransactionSize.optional)
                Stepper("Hours per week: \(Int(inputs.hoursPerWeek))", value: $inputs.hoursPerWeek, in: 1...80)
                Stepper("Weeks of vacation: \(Int(inputs.vacationWeeks))", value: $inputs.vacationWeeks, in: 0...12)
            } footer: {
                if inputs.netProfitGoal > inputs.grossIncomeGoal {
                    Text("Net profit can't be more than gross income.").foregroundStyle(.red)
                }
            }
            Section("This is your business") {
                row("Monthly gross income", Format.money(o.monthlyGross))
                row("Monthly net profit", Format.money(o.monthlyNet))
                row("Annual projected expenses", Format.money(o.annualExpenses))
                row("Your yield per transaction", Format.pct(o.yieldPct, decimals: 2))
                row("Transactions needed per year", Format.num(o.annualTransactions, decimals: 1))
                row("Transactions needed per month", Format.num(o.monthlyTransactions, decimals: 2))
                row("Volume needed per year", Format.money(o.annualVolume))
                row("Work hours per year", Format.num(o.annualWorkHours))
                row("Hourly rate (gross)", Format.money(o.hourlyGross, cents: true))
                row("Hourly rate (net)", Format.money(o.hourlyNet, cents: true))
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value).monospacedDigit()
    }
}
