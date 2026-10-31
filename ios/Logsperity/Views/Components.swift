import LogsperityCore
import SwiftUI

// Shared building blocks for the six input screens (design §10, "shared behavior on all six screens").

/// A dollar amount field. Empty means nil.
struct MoneyField: View {
    let label: String
    @Binding var value: Double?
    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ label: String, value: Binding<Double?>) {
        self.label = label
        _value = value
    }

    var body: some View {
        LabeledContent(label) {
            TextField("$0", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboard(.decimal)
                .focused($focused)
                .onChange(of: text) { _, t in
                    let cleaned = t.filter { $0.isNumber || $0 == "." }
                    value = Double(cleaned).map { ($0 * 100).rounded() / 100 }
                }
                .onAppear { text = value.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.2f", $0) } ?? "" }
                .onChange(of: focused) { _, f in
                    if !f, let v = value { text = Format.money(v, cents: v != v.rounded()) }
                    if f, let v = value { text = v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
                }
        }
    }
}

/// Non-optional money binding helper.
extension Binding where Value == Double {
    var optional: Binding<Double?> { Binding<Double?>(get: { wrappedValue == 0 ? nil : wrappedValue }, set: { wrappedValue = $0 ?? 0 }) }
}

/// A plain number field (odometer, miles, count).
struct NumberField: View {
    let label: String
    @Binding var value: Double?
    var decimals = 1

    var body: some View {
        LabeledContent(label) {
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...decimals)))
                .multilineTextAlignment(.trailing)
                .keyboard(.decimal)
        }
    }
}

/// Free text with autocomplete from remembered sources (FR-13).
struct SourceField: View {
    @Environment(AppModel.self) private var model
    let label: String
    @Binding var name: String
    var prompt = "Who or what sent it"
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(label) {
                TextField(prompt, text: $name)
                    .multilineTextAlignment(.trailing)
                    .keyboard(.name)
                    .focused($focused)
            }
            if focused {
                let suggestions = model.sourceSuggestions(matching: name).filter { $0 != name }
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) { name = s; focused = false }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Pillar → Category and Pillar → Activity, filtered (FR-11, FR-12), plus Source.
struct AttributionSection: View {
    @Binding var attribution: Attribution
    @Binding var sourceName: String
    var showCategory = true
    var showActivity = true
    var showSource = true
    var sourceLabel = "Source"

    var body: some View {
        Section("Where it came from") {
            Picker("Pillar", selection: Binding(get: { attribution.pillar }, set: { p in
                attribution.pillar = p
                if let c = attribution.categoryID, Taxonomy.categoryByID[c]?.pillar != p { attribution.categoryID = nil }
                if let a = attribution.activityID, Taxonomy.activityByID[a]?.pillar != p { attribution.activityID = nil }
                attribution.subPillar = p == .clients ? .clients : p == .prospecting ? .prospecting : nil
            })) {
                Text("Choose").tag(Pillar?.none)
                ForEach(Pillar.allCases) { Text($0.name).tag(Pillar?.some($0)) }
            }
            if let pillar = attribution.pillar {
                if showCategory {
                    Picker("Category", selection: Binding(get: { attribution.categoryID }, set: { c in
                        attribution.categoryID = c
                        if let c, let item = Taxonomy.categoryByID[c] { attribution.subPillar = item.subPillar }
                    })) {
                        Text("Choose").tag(String?.none)
                        ForEach(groups(Taxonomy.categories(in: pillar)), id: \.0) { sub, items in
                            Section(sub.name) { ForEach(items) { Text($0.name).tag(String?.some($0.id)) } }
                        }
                    }
                }
                if showActivity {
                    Picker("Activity", selection: Binding(get: { attribution.activityID }, set: { a in
                        attribution.activityID = a
                        if attribution.subPillar == nil, let a, let item = Taxonomy.activityByID[a] { attribution.subPillar = item.subPillar }
                    })) {
                        Text("Choose").tag(String?.none)
                        ForEach(groups(Taxonomy.activities(in: pillar)), id: \.0) { sub, items in
                            Section(sub.name) { ForEach(items) { Text($0.name).tag(String?.some($0.id)) } }
                        }
                    }
                }
            }
            if showSource { SourceField(label: sourceLabel, name: $sourceName) }
        }
    }

    private func groups(_ items: [TaxonomyItem]) -> [(SubPillar, [TaxonomyItem])] {
        SubPillar.allCases.compactMap { sp in
            let g = items.filter { $0.subPillar == sp }
            return g.isEmpty ? nil : (sp, g)
        }
    }
}

struct StrengthPicker: View {
    @Binding var strength: Strength?
    var body: some View {
        Picker("Strength", selection: $strength) {
            Text("Not set").tag(Strength?.none)
            ForEach(Strength.allCases) { s in
                Label(s.name, systemImage: "circle.fill").foregroundStyle(Color(hex: s.colorHex)).tag(Strength?.some(s))
            }
        }
    }
}

/// Follow-up as a number of days (Appendix B) or a date.
struct FollowUpPicker: View {
    @Binding var followUp: Day?
    let from: Day

    var body: some View {
        Picker("Follow up in", selection: Binding<Int?>(get: {
            followUp.map { from.days(to: $0) }.flatMap { Taxonomy.followUpDays.contains($0) ? $0 : -1 }
        }, set: { d in
            if let d, d > 0 { followUp = from.adding(days: d) } else if d == nil { followUp = nil }
        })) {
            Text("No follow-up").tag(Int?.none)
            ForEach(Taxonomy.followUpDays, id: \.self) { Text("\($0) days").tag(Int?.some($0)) }
            if let f = followUp, !Taxonomy.followUpDays.contains(from.days(to: f)) { Text("Custom date").tag(Int?.some(-1)) }
        }
        if followUp != nil {
            DatePicker("Follow-up date", selection: Binding(get: { (followUp ?? from).date() }, set: { followUp = Day(date: $0) }),
                       displayedComponents: .date)
        }
    }
}

/// A rounded card used on Today and Coach.
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

struct Chip: View {
    let text: String
    var color: Color = .brandBlue
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule).foregroundStyle(color)
    }
}

extension InsightLevel {
    var color: Color {
        switch self {
        case .concern: .red
        case .watch: .orange
        case .win: .green
        case .info: .brandBlue
        }
    }
    var symbol: String {
        switch self {
        case .concern: "exclamationmark.triangle.fill"
        case .watch: "eye.fill"
        case .win: "star.fill"
        case .info: "info.circle.fill"
        }
    }
}
