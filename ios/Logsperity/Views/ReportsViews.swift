import LogsperityCore
import SwiftUI

/// Reports menu (S14, §14.1): Logs · Quick Stats · Detailed Reports · Monthly & YTD.
struct ReportsMenuView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(Reports.menu) { group in
                    Section(group.title) {
                        ForEach(group.items, id: \.key) { item in
                            NavigationLink(item.title, value: item.key)
                        }
                    }
                }
            }
            .navigationTitle("Reports")
            .navigationDestination(for: String.self) { ReportView(key: $0) }
        }
    }
}

/// Report viewer (S15) with a period picker and Share as PDF.
struct ReportView: View {
    @Environment(AppModel.self) private var model
    let key: String
    @State private var periodKey = "ytd"
    @State private var pdf: URL?

    private var fixedPeriod: Bool {
        key.hasPrefix("month_") || ["ytd", "quick_annual_ytd", "quick_annual_streamlined", "annual_ytd", "quick_current_month"].contains(key)
    }

    var body: some View {
        let report = try? model.reports.build(key, periodKey: periodKey)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let report {
                    if !fixedPeriod {
                        Picker("Period", selection: $periodKey) {
                            ForEach(Period.pickerChoices(now: model.today), id: \.key) { Text($0.label).tag($0.key) }
                        }
                        .pickerStyle(.menu)
                    }
                    Text(report.period.label).font(.subheadline).foregroundStyle(.secondary)
                    ForEach(report.widgets) { WidgetCard(widget: $0) }
                } else {
                    ContentUnavailableView("Report unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .padding()
        }
        .navigationTitle(Reports.titles[key] ?? "Report").inlineTitle()
        .toolbar {
            if let report {
                if let pdf {
                    ShareLink(item: pdf) { Image(systemName: "square.and.arrow.up") }
                } else {
                    Button { pdf = PDFExport.render(PrintableReport(report: report, owner: model.settings.name), fileName: report.title) } label: {
                        Image(systemName: "doc.richtext")
                    }
                    .accessibilityLabel("Make a PDF")
                }
            }
        }
        .onChange(of: periodKey) { _, _ in pdf = nil }
    }
}

/// The report laid out for paper.
struct PrintableReport: View {
    let report: Report
    let owner: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.title).font(.largeTitle.weight(.light))
            Text([owner, report.period.label].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
            ForEach(report.widgets) { WidgetCard(widget: $0) }
            Text("Logsperity by Prosperity Simplified").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
