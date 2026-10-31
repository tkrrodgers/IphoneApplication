import LogsperityCore
import SwiftUI

/// Today (S3): Ask HERB, key numbers, this week's focus, follow-ups due, Review queue, quick-add.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Binding var showHerb: Bool
    @State private var adding: LogKind?

    var body: some View {
        let coach = model.coach
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Format.spokenDate(model.today)).font(.subheadline).foregroundStyle(.secondary)
                    AskHerbButton { showHerb = true }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(coach.kpis()) { k in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(k.label).font(.caption).foregroundStyle(.secondary)
                                Text(k.display).font(.title2.bold()).monospacedDigit()
                                Text(k.sub).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.secondary, in: .rect(cornerRadius: 14))
                        }
                    }

                    let review = coach.reviewItems()
                    if !review.isEmpty {
                        NavigationLink { ReviewQueueView() } label: {
                            HStack {
                                Image(systemName: "tray.full.fill").foregroundStyle(Color.brandBlue)
                                Text("HERB logged \(review.count) item\(review.count == 1 ? "" : "s") for you to review")
                                    .foregroundStyle(.primary).multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding().background(Color.brandBlue.opacity(0.08), in: .rect(cornerRadius: 14))
                        }
                    }

                    let focus = coach.focus()
                    if !focus.items.isEmpty {
                        Card(title: "This week's focus") {
                            ForEach(Array(focus.items.enumerated()), id: \.offset) { i, f in
                                HStack(alignment: .top) {
                                    Text("\(i + 1)").font(.headline).foregroundStyle(Color.brandBlue).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.title).font(.subheadline.bold())
                                        Text(f.why).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    let followUps = coach.followUps()
                    Card(title: "Follow-ups") {
                        if followUps.isEmpty {
                            Text("Nothing due. Nice work.").foregroundStyle(.secondary)
                        }
                        ForEach(followUps.prefix(8)) { f in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(f.name).font(.subheadline.bold())
                                    Spacer()
                                    Chip(text: f.chip.rawValue.capitalized, color: f.chip == .late ? .red : f.chip == .new ? .orange : .brandBlue)
                                }
                                Text(f.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            if f.id != followUps.prefix(8).last?.id { Divider() }
                        }
                    }

                    if let insight = coach.insights().first {
                        Card {
                            Label(insight.title, systemImage: insight.level.symbol).font(.subheadline.bold()).foregroundStyle(insight.level.color)
                            Text(insight.text).font(.subheadline)
                        }
                    }

                    Card(title: "Quick add") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                            ForEach(LogKind.allCases) { k in
                                Button { adding = k } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: k.symbol).font(.title2)
                                        Text(k.singular).font(.caption)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 60)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(model.settings.firstName.isEmpty ? "Today" : "Hi, \(model.settings.firstName)")
            .sheet(item: $adding) { kind in NavigationStack { LogForm(kind: kind) } }
        }
    }
}
