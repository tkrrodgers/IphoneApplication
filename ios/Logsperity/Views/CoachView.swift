import Charts
import LogsperityCore
import SwiftUI

/// Coach (S17, design §16): Logsperity Index, Business Plan tracker, this week's focus and coaching insights.
struct CoachView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let coach = model.coach
        let led = model.ledger("ytd")
        let tracking = PlanTracking(model.book, year: model.today.year, now: model.today)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WidgetCard(widget: ReportWidget("Logsperity Index", .index(Coach.indexSummary(led))))
                    let trend = indexTrend(model.book, year: model.today.year, now: model.today).filter { $0.value != nil }
                    if trend.count > 1 {
                        Card(title: "Index by month") {
                            Chart(trend, id: \.month) { t in
                                LineMark(x: .value("Month", t.label), y: .value("Index", t.value ?? 0)).foregroundStyle(Color.brandBlue)
                                RuleMark(y: .value("Healthy", 100)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4]))
                            }
                            .frame(height: 140)
                        }
                    }
                    Card(title: "Business plan — \(Format.pct(tracking.elapsedFraction)) of the year") {
                        ForEach(tracking.items, id: \.key) { i in
                            ProgressRow(item: ProgressItem(label: i.label, actual: i.actual, projected: i.projected, goal: i.goal,
                                                           displayActual: i.displayActual, displayProjected: i.displayProjected,
                                                           displayGoal: i.displayGoal, pacePct: i.pacePct))
                        }
                        Text("Year-end forecast: \(Format.money(tracking.forecast.value))").font(.caption).foregroundStyle(.secondary)
                    }
                    let focus = coach.focus()
                    Card(title: "This week's focus") {
                        Text(focus.say).font(.subheadline)
                    }
                    Text("Insights").font(.title3.bold())
                    let insights = coach.insights()
                    if insights.isEmpty {
                        Text("No coaching flags right now. Keep logging and HERB will spot patterns.").foregroundStyle(.secondary)
                    }
                    ForEach(insights) { i in
                        Card {
                            HStack(alignment: .top) {
                                Label(i.title, systemImage: i.level.symbol).font(.subheadline.bold()).foregroundStyle(i.level.color)
                                Spacer()
                                Menu {
                                    Button("Dismiss", systemImage: "xmark") { model.dismissInsight(i.key) }
                                } label: { Image(systemName: "ellipsis").padding(4) }
                                .accessibilityLabel("Insight options")
                            }
                            Text(i.text).font(.subheadline)
                            if let n = i.sample, n < 5 { Text("Early signal — based on \(n).").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Coach")
        }
    }
}

/// Review queue (S18, §6.4): items HERB captured on its own, one tap to confirm or dismiss.
struct ReviewQueueView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ReviewItem?

    var body: some View {
        let items = model.coach.reviewItems()
        List {
            if items.isEmpty {
                ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("Nothing is waiting for you."))
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.headline)
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                    Text(item.question).font(.subheadline)
                    HStack {
                        Button("Yes") { model.confirmReview(item) }.buttonStyle(.borderedProminent)
                        Button("Edit") { editing = item }.buttonStyle(.bordered)
                        Spacer()
                        Button("Dismiss", role: .destructive) { model.dismissReview(item) }.buttonStyle(.borderless)
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Review queue")
        .sheet(item: $editing) { item in
            NavigationStack { LogForm(kind: LogKind(rawValue: item.log.rawValue)!, editingID: item.recordID) }
                .onDisappear { model.confirmReview(item) }
        }
    }
}
