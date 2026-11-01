import LogsperityCore
import SwiftUI

/// Ask HERB (S19): talk or type. HERB fills in drafts, asks one question at a time (design §17.2), saves only on
/// "yes", and answers questions about your numbers. Push-to-talk: tap the mic, speak, tap again to send.
struct HerbView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [Message] = []
    @State private var state: HerbDialogState?
    @State private var draft: HerbDraft?
    @State private var text = ""
    @State private var speech = SpeechInput()
    @State private var voice = SpeechOutput()
    @State private var target: Target?
    @FocusState private var typing: Bool

    struct Message: Identifiable {
        let id = UUID()
        let fromUser: Bool
        let text: String
        var cards: [HerbCard] = []
        var actions: [HerbAction] = []
    }

    /// A screen HERB asked to open.
    struct Target: Identifiable {
        enum Kind { case report(String), form(LogKind, [LogChange]), review, plan }
        let id = UUID()
        let kind: Kind
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty { examples }
                            ForEach(messages) { bubble($0).id($0.id) }
                            if let draft { draftCard(draft).id("draft") }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(draft != nil ? AnyHashable("draft") : AnyHashable(messages.last?.id), anchor: .bottom) }
                    }
                }
                inputBar
            }
            .navigationTitle("HERB").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { voice.stop(); speech.stop(); dismiss() } }
                if state != nil {
                    ToolbarItem(placement: .primaryAction) { Button("Start over") { send("cancel") } }
                }
            }
            .sheet(item: $target) { t in
                NavigationStack {
                    switch t.kind {
                    case .report(let key): ReportView(key: key)
                    case .form(let kind, let prefill): LogForm(kind: kind, prefill: prefill)
                    case .review: ReviewQueueView()
                    case .plan: PlanScreen()
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try saying").font(.headline)
            ForEach(["New prospect Tom Rodgers, 847-477-0619, follow up next week",
                     "I spent 45 dollars on lunch with Dana Ruiz",
                     "Two hours of door knocking, got two leads",
                     "What should I focus on this week?",
                     "Am I on track for my plan?",
                     "Which sources never close?"], id: \.self) { s in
                Button { send(s) } label: {
                    Text("“\(s)”").font(.subheadline).multilineTextAlignment(.leading)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bubble(_ m: Message) -> some View {
        VStack(alignment: m.fromUser ? .trailing : .leading, spacing: 6) {
            Text(m.text)
                .padding(12)
                .background(m.fromUser ? Color.brandBlue : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 16))
                .foregroundStyle(m.fromUser ? Color.white : Color.primary)
                .frame(maxWidth: 320, alignment: m.fromUser ? .trailing : .leading)
            ForEach(m.cards, id: \.self) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).font(.subheadline.bold())
                        if let s = c.subtitle { Text(s).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let v = c.value { Text(v).font(.subheadline).monospacedDigit() }
                }
                .padding(10).background(.background.secondary, in: .rect(cornerRadius: 10))
                .frame(maxWidth: 320)
            }
            if !m.actions.isEmpty && m.id == messages.last?.id {
                FlowRow(actions: m.actions) { act($0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: m.fromUser ? .trailing : .leading)
    }

    private func draftCard(_ d: HerbDraft) -> some View {
        Card(title: d.recordID == nil ? "New \(LogKind(rawValue: d.log.rawValue)?.singular.lowercased() ?? "entry") — not saved yet" : "Update — not saved yet") {
            ForEach(d.summary, id: \.label) { row in
                HStack(alignment: .top) {
                    Text(row.label).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(row.value.isEmpty ? "?" : row.value).font(.subheadline).foregroundStyle(row.asking ? Color.orange : .primary)
                }
            }
            HStack {
                Button("Save") { save(d) }.buttonStyle(.borderedProminent)
                Button("Edit") { edit(d) }.buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(speech.state == .listening ? "Listening…" : "Type or tap the mic", text: speech.state == .listening ? .constant(speech.transcript) : $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($typing)
                .onSubmit { send(text) }
            if !text.isEmpty && speech.state != .listening {
                Button { send(text) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .accessibilityLabel("Send")
            } else {
                Button { toggleMic() } label: {
                    Image(systemName: speech.state == .listening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 38)).foregroundStyle(speech.state == .listening ? Color.red : Color.brandBlue)
                        .symbolEffect(.pulse, isActive: speech.state == .listening)
                }
                .accessibilityLabel(speech.state == .listening ? "Stop and send" : "Talk to HERB")
            }
        }
        .padding()
        .background(.bar)
        .overlay(alignment: .top) {
            if speech.state == .denied {
                Text("Turn on Microphone and Speech Recognition for Logsperity in Settings to talk to HERB.")
                    .font(.caption).padding(8).background(.yellow.opacity(0.3), in: .rect(cornerRadius: 8)).offset(y: -44)
            }
        }
    }

    // MARK: Turns

    private func toggleMic() {
        if speech.state == .listening {
            let heard = speech.stop()
            send(heard)
        } else {
            voice.stop()
            typing = false
            Task { await speech.start() }
        }
    }

    private func send(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""
        messages.append(Message(fromUser: true, text: t))
        let reply = model.herb().respond(to: t, state: state)
        model.apply(reply)
        state = reply.state
        draft = reply.state == nil ? nil : reply.draft
        var shown = reply.display ?? reply.say
        if let saved = reply.saved, reply.changes.isEmpty == false, shown.isEmpty { shown = "Saved to \(saved.rawValue)." }
        messages.append(Message(fromUser: false, text: shown, cards: reply.cards, actions: reply.actions))
        if model.settings.herbSpeaks { voice.say(reply.say) }
        if reply.openForm, let d = reply.draft { edit(d) }
    }

    private func act(_ a: HerbAction) {
        switch a.kind {
        case .reply(let t): send(t)
        case .editDraft: if let draft { edit(draft) }
        case .say(let t):
            messages.append(Message(fromUser: false, text: t))
            if model.settings.herbSpeaks { voice.say(t) }
        case .open(let target): open(target)
        }
    }

    private func open(_ t: HerbTarget) {
        switch t {
        case .report(let key), .emailReport(let key): target = Target(kind: .report(key))
        case .receiptScanner: target = Target(kind: .form(.expenses, []))
        case .review: target = Target(kind: .review)
        case .businessPlan: target = Target(kind: .plan)
        case .today: dismiss()
        }
    }

    /// The Save button on the draft card (`Herb.confirm`); the conversation ends.
    private func save(_ d: HerbDraft) {
        do {
            let saved = try model.herb().confirm(d)
            model.apply(saved.changes)
            state = nil
            draft = nil
            messages.append(Message(fromUser: false, text: saved.say))
            if model.settings.herbSpeaks { voice.say(saved.say) }
        } catch {
            messages.append(Message(fromUser: false, text: "I couldn't save that: \(error)"))
        }
    }

    /// "Edit" opens the form with everything HERB heard filled in. Nothing is saved unless the form is saved.
    private func edit(_ d: HerbDraft) {
        guard let saved = try? model.herb().confirm(d), let kind = LogKind(rawValue: d.log.rawValue) else { return }
        state = nil
        draft = nil
        target = Target(kind: .form(kind, saved.changes))
    }
}

/// Quick-reply buttons that wrap onto new lines.
private struct FlowRow: View {
    let actions: [HerbAction]
    let tap: (HerbAction) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { buttons }
            VStack(alignment: .leading) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(actions, id: \.self) { a in
            Button(a.label) { tap(a) }.buttonStyle(.bordered).controlSize(.small)
        }
    }
}
