import LogsperityCore
import SwiftUI

/// Ask HERB (S19): talk or type. HERB fills in drafts, asks one question at a time (design §17.2), saves only on
/// "yes", and answers questions about your numbers. Hands-free: tap the mic once and talk; HERB answers when you
/// pause, speaks its reply, and listens again until the conversation is done (`HerbConversation`).
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
    /// In a hands-free conversation: HERB listens again after each reply.
    @State private var conversing = false
    @State private var herbTalking = false
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
                ToolbarItem(placement: .cancellationAction) { Button("Done") { endConversation(); voice.stop(); dismiss() } }
                if state != nil {
                    ToolbarItem(placement: .primaryAction) { Button("Start over") { send("cancel") } }
                }
            }
            .onChange(of: typing) { _, now in if now { endConversation() } }  // typing instead of talking
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
        VStack(spacing: 6) {
            if let hint = statusHint {
                Text(hint).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            inputRow
        }
        .padding()
        .background(.bar)
        .overlay(alignment: .top) {
            if speech.state == .denied || speech.state == .unavailable {
                Text(speech.state == .denied
                     ? "Turn on Microphone and Speech Recognition for Logsperity in Settings to talk to HERB."
                     : "Voice isn't available right now. Check that Dictation is on in Settings → General → Keyboard. You can still type to HERB.")
                    .font(.caption).padding(8).background(.yellow.opacity(0.3), in: .rect(cornerRadius: 8)).offset(y: -44)
            }
        }
    }

    private var statusHint: String? {
        if speech.state == .listening { return "Listening — HERB answers when you pause. Tap to stop." }
        if herbTalking { return "HERB is talking — tap to interrupt." }
        return nil
    }

    private var inputRow: some View {
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
                Button { micTapped() } label: {
                    Image(systemName: speech.state == .listening ? "stop.circle.fill" : herbTalking ? "speaker.wave.2.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 38)).foregroundStyle(speech.state == .listening ? Color.red : Color.brandBlue)
                        .symbolEffect(.pulse, isActive: speech.state == .listening || herbTalking)
                }
                .accessibilityLabel(speech.state == .listening ? "Stop listening" : herbTalking ? "Interrupt HERB" : "Talk to HERB")
            }
        }
    }

    // MARK: Turns

    /// Mic button: start a conversation, interrupt HERB while it's talking, or stop listening.
    private func micTapped() {
        if herbTalking {
            conversing = true
            voice.stop()  // `speakThenListen` carries on and listens
            return
        }
        if speech.state == .listening {
            conversing = false
            let heard = speech.stop()
            if !heard.isEmpty { send(heard) }
            return
        }
        typing = false
        conversing = true
        listen(timeout: HerbConversation.firstTimeout)
    }

    private func listen(timeout: Double) {
        Task {
            await speech.start(pause: model.settings.pause.seconds, noSpeechTimeout: timeout) { heard in
                handleHeard(heard)
            }
        }
    }

    /// One spoken turn finished: nil means the user said nothing, so the conversation ends quietly.
    private func handleHeard(_ heard: String?) {
        guard conversing else { return }
        guard let heard else { conversing = false; return }
        if HerbConversation.isGoodbye(heard) {
            conversing = false
            messages.append(Message(fromUser: true, text: heard))
            messages.append(Message(fromUser: false, text: "Okay. Tap the mic when you need me."))
            if model.settings.herbSpeaks { voice.say("Okay.") }
            return
        }
        send(heard)
    }

    /// HERB speaks its reply, then listens for the user's next turn if the conversation goes on.
    private func speakThenListen(_ say: String, next: Double?) async {
        if model.settings.herbSpeaks && !say.isEmpty {
            herbTalking = true
            await voice.speak(say)
            herbTalking = false
        }
        guard conversing, model.settings.herbHandsFree, target == nil, let next else { conversing = false; return }
        try? await Task.sleep(for: .milliseconds(300))  // let the speaker go quiet so HERB doesn't hear itself
        guard conversing, speech.state != .listening else { return }
        listen(timeout: next)
    }

    private func endConversation() {
        conversing = false
        if speech.state == .listening { speech.stop() }
    }

    private func send(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if speech.state == .listening { speech.stop() }  // a tapped reply or example replaces what's being said
        text = ""
        messages.append(Message(fromUser: true, text: t))
        let reply = model.herb().respond(to: t, state: state)
        model.apply(reply)
        state = reply.state
        draft = reply.state == nil ? nil : reply.draft
        var shown = reply.display ?? reply.say
        if let saved = reply.saved, reply.changes.isEmpty == false, shown.isEmpty { shown = "Saved to \(saved.rawValue)." }
        messages.append(Message(fromUser: false, text: shown, cards: reply.cards, actions: reply.actions))
        if reply.openForm, let d = reply.draft { edit(d) }
        let next = HerbConversation.listenAgain(after: reply)
        Task { await speakThenListen(reply.say, next: next) }
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
        endConversation()
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
            if speech.state == .listening { speech.stop() }
            Task { await speakThenListen(saved.say, next: HerbConversation.followUpTimeout) }
        } catch {
            messages.append(Message(fromUser: false, text: "I couldn't save that: \(error)"))
        }
    }

    /// "Edit" opens the form with everything HERB heard filled in. Nothing is saved unless the form is saved.
    private func edit(_ d: HerbDraft) {
        guard let saved = try? model.herb().confirm(d), let kind = LogKind(rawValue: d.log.rawValue) else { return }
        endConversation()
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
