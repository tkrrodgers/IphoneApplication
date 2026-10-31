import Charts
import LogsperityCore
import SwiftUI

/// Draws any report widget. Style follows the 2018 Annual Report (design §15.1): a blue header bar, big
/// numbers with their formula underneath in italics.
struct WidgetCard: View {
    let widget: ReportWidget

    var body: some View {
        if case .text(_, let pageBreak) = widget.content, pageBreak {
            Text(widget.title).font(.title2.weight(.light)).foregroundStyle(.secondary).padding(.top, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(widget.title.uppercased())
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brandBlue)
                WidgetBody(content: widget.content).padding(12)
            }
            .background(.background.secondary)
            .clipShape(.rect(cornerRadius: 10))
        }
    }
}

struct WidgetBody: View {
    let content: ReportWidget.Content

    var body: some View {
        switch content {
        case .stat(_, let display, let caption, let formula):
            VStack(alignment: .leading, spacing: 4) {
                Text(display).font(.system(.largeTitle, design: .serif)).monospacedDigit()
                if let caption { Text(caption).font(.subheadline).foregroundStyle(.secondary) }
                if let formula { Text(formula).font(.caption).italic().foregroundStyle(.secondary) }
            }
        case .stats(let items):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items, id: \.label) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).font(.caption).foregroundStyle(.secondary)
                        Text(s.display).font(.system(.title2, design: .serif)).monospacedDigit()
                        if let c = s.caption { Text(c).font(.caption).foregroundStyle(.secondary) }
                        if let f = s.formula { Text(f).font(.caption2).italic().foregroundStyle(.secondary) }
                    }
                }
            }
        case .table(let columns, let rows, let total, let note):
            TableWidget(columns: columns, rows: rows, total: total, note: note)
        case .bar(let items, let horizontal):
            if items.isEmpty { EmptyWidget() } else { BarWidget(items: items, horizontal: horizontal) }
        case .pie(let items, let center, let caption):
            PieWidget(items: items, center: center, caption: caption)
        case .stack(let items):
            StackWidget(items: items)
        case .progress(let items):
            VStack(spacing: 14) { ForEach(items, id: \.label) { ProgressRow(item: $0) } }
        case .index(let summary):
            IndexWidget(summary: summary)
        case .text(let paragraphs, _):
            VStack(alignment: .leading, spacing: 8) { ForEach(paragraphs, id: \.self) { Text($0).font(.subheadline) } }
        case .list(let items):
            if items.isEmpty { EmptyWidget(text: "Nothing to flag.") }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.title) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(i.title, systemImage: (i.level ?? .info).symbol).font(.subheadline.bold()).foregroundStyle((i.level ?? .info).color)
                        Text(i.text).font(.caption)
                    }
                }
            }
        case .columns(let series, let items):
            ColumnsWidget(series: series, items: items)
        }
    }
}

struct EmptyWidget: View {
    var text = "No data for this period."
    var body: some View { Text(text).font(.subheadline).foregroundStyle(.secondary) }
}

private let taupe = Color(red: 0xB5 / 255, green: 0xAC / 255, blue: 0xA5 / 255)
private let palette: [Color] = [Color(red: 0x5B / 255, green: 0x6B / 255, blue: 0xBF / 255), .expenseOrange, .profitTeal, .brandGold,
                                taupe, .purple, .pink, .gray]

struct TableWidget: View {
    let columns: [Column]
    let rows: [ReportRow]
    let total: ReportRow?
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty { EmptyWidget() } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow { ForEach(columns, id: \.key) { c in cell(Text(c.label).font(.caption.bold()).foregroundStyle(.secondary), c) } }
                        Divider()
                        ForEach(Array(rows.prefix(200).enumerated()), id: \.offset) { _, r in
                            GridRow { ForEach(columns, id: \.key) { c in cell(Text(r[c.key]?.display(c.format) ?? "").font(.caption), c) } }
                        }
                        if let total {
                            Divider()
                            GridRow { ForEach(columns, id: \.key) { c in cell(Text(total[c.key]?.display(c.format) ?? "").font(.caption.bold()), c) } }
                        }
                    }
                    .monospacedDigit()
                }
                if rows.count > 200 { Text("Showing 200 of \(rows.count) rows.").font(.caption2).foregroundStyle(.secondary) }
            }
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func cell(_ t: some View, _ c: Column) -> some View {
        t.gridColumnAlignment(c.alignRight ? .trailing : .leading).lineLimit(1)
    }
}

struct BarWidget: View {
    let items: [ChartItem]
    let horizontal: Bool

    var body: some View {
        Chart(Array(items.enumerated()), id: \.offset) { _, i in
            if horizontal {
                BarMark(x: .value("Value", i.value), y: .value("Item", i.label))
                    .foregroundStyle(taupe)
                    .annotation(position: .trailing) { Text(i.display).font(.caption2) }
            } else {
                BarMark(x: .value("Item", i.label), y: .value("Value", i.value))
                    .foregroundStyle(taupe)
                    .annotation(position: .top) { Text(i.display).font(.caption2) }
            }
        }
        .chartXAxis(horizontal ? .hidden : .automatic)
        .frame(height: horizontal ? CGFloat(max(1, items.count)) * 34 + 10 : 200)
    }
}

struct PieWidget: View {
    let items: [ChartItem]
    let center: String?
    let caption: String?

    var body: some View {
        VStack(alignment: .leading) {
            if items.allSatisfy({ $0.value <= 0 }) { EmptyWidget() } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(Array(items.enumerated()), id: \.offset) { n, i in
                        SectorMark(angle: .value("Value", max(0, i.value)), innerRadius: .ratio(center == nil ? 0 : 0.6), angularInset: 1)
                            .foregroundStyle(palette[n % palette.count])
                    }
                    .frame(width: 120, height: 120)
                    .overlay { if let center { Text(center).font(.title3.bold()) } }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { n, i in
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(palette[n % palette.count]).frame(width: 8, height: 8).padding(.top, 4)
                                VStack(alignment: .leading) {
                                    Text(i.label).font(.caption.bold())
                                    Text(i.display).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if let caption { Text(caption).font(.caption).italic().foregroundStyle(.secondary) }
        }
    }
}

struct StackWidget: View {
    let items: [ChartItem]
    var body: some View {
        let total = max(1, items.reduce(0) { $0 + max(0, $1.value) })
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, i in
                        Rectangle().fill(i.role == .profit ? Color.profitTeal : Color.expenseOrange)
                            .frame(width: geo.size.width * max(0, i.value) / total)
                    }
                }
            }
            .frame(height: 28).clipShape(.rect(cornerRadius: 6))
            ForEach(items, id: \.label) { i in
                LabeledContent(i.label, value: i.display).font(.caption).monospacedDigit()
            }
        }
    }
}

struct ProgressRow: View {
    let item: ProgressItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.label).font(.subheadline.bold())
                Spacer()
                Text("\(Format.pct(item.pacePct)) of pace").font(.caption)
                    .foregroundStyle((item.pacePct ?? 0) >= 0.95 ? Color.green : Color.orange)
            }
            ProgressView(value: min(1, item.goal > 0 ? item.actual / item.goal : 0))
                .tint((item.pacePct ?? 0) >= 0.95 ? .green : .orange)
            HStack {
                Text("Now \(item.displayActual)")
                Spacer()
                Text("Projected \(item.displayProjected)")
                Spacer()
                Text("Goal \(item.displayGoal)")
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

struct IndexWidget: View {
    let summary: IndexSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.display).font(.system(size: 52, weight: .regular, design: .serif)).monospacedDigit()
                Text(summary.label).font(.headline).foregroundStyle(.secondary)
            }
            ForEach(summary.drivers, id: \.key) { d in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(d.label).font(.caption.bold())
                        Spacer()
                        Text("\(d.display) vs \(d.benchmarkDisplay) healthy").font(.caption).monospacedDigit()
                    }
                    ProgressView(value: min(1, max(0, (d.ratio ?? 0) / 2)))
                        .tint((d.ratio ?? 0) >= 1 ? .green : .orange)
                }
            }
            Text("100 = a healthy business").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ColumnsWidget: View {
    let series: [String]
    let items: [ColumnSeriesItem]

    var body: some View {
        if items.isEmpty { EmptyWidget() } else if series.count == 1 {
            Chart(Array(items.enumerated()), id: \.offset) { _, i in
                BarMark(x: .value("Month", i.label), y: .value(series[0], i.values.first ?? 0)).foregroundStyle(taupe)
            }
            .frame(height: 180)
        } else {
            // Series on different scales (hours, counts, $k): one small chart each.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(series.enumerated()), id: \.offset) { s, name in
                    Text(name).font(.caption.bold())
                    Chart(Array(items.enumerated()), id: \.offset) { _, i in
                        BarMark(x: .value("Item", i.label), y: .value(name, i.values[s])).foregroundStyle(palette[s % palette.count])
                    }
                    .frame(height: 90)
                }
            }
        }
    }
}
