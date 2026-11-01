import AVFoundation
import Foundation
import LogsperityCore
import Observation
import Speech

/// Speech recognition for HERB, on the device when the phone supports it. iOS doesn't allow an always-on custom wake
/// word (design §23), so the user taps the mic once; each turn then ends on its own when the user pauses
/// (`HerbEndpointer`), says "send", or taps the mic again.
@MainActor @Observable
final class SpeechInput {
    enum State: Equatable { case idle, listening, denied, unavailable }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var endpointer: HerbEndpointer?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    /// Called once per turn: the finished text, or nil when nothing was said (or voice isn't available).
    @ObservationIgnored private var onFinish: ((String?) -> Void)?

    func authorize() async -> Bool {
        let speech = await Self.requestSpeechAuthorization()
        #if os(iOS)
        let mic = await AVAudioApplication.requestRecordPermission()
        #else
        let mic = true
        #endif
        if !(speech && mic) { state = .denied }
        return speech && mic
    }

    /// Listens for one turn. It ends after `pause` seconds of silence following speech, when the user says "send",
    /// or after `noSpeechTimeout` seconds with nothing said.
    func start(pause: Double, noSpeechTimeout: Double, onFinish: @escaping (String?) -> Void) async {
        guard state != .listening else { return }
        self.onFinish = onFinish
        #if DEBUG
        if Self.fakeTurns != nil { startFake(pause: pause, noSpeechTimeout: noSpeechTimeout); return }
        #endif
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; finish(nil); return }
        guard await authorize() else { finish(nil); return }
        transcript = ""
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            req.addsPunctuation = true
            request = req
            Self.feed(engine.inputNode, into: req)
            engine.prepare()
            try engine.start()
            beginTurn(pause: pause, noSpeechTimeout: noSpeechTimeout)
            task = Self.recognize(req, with: recognizer) { [weak self] text, done, failed in
                Task { @MainActor in
                    guard let self, self.state == .listening else { return }  // not listening: the turn already ended
                    if let text { self.heard(text) }
                    guard done else { return }
                    if failed && self.transcript.isEmpty {
                        // Recognition failed before hearing anything (e.g. Dictation is off): say so instead of going quiet.
                        self.stopAudio()
                        self.state = .unavailable
                        self.finish(nil)
                    } else {
                        self.endTurn(self.transcript)
                    }
                }
            }
        } catch {
            stopAudio()
            state = .unavailable
            finish(nil)
        }
    }

    private func beginTurn(pause: Double, noSpeechTimeout: Double) {
        transcript = ""
        endpointer = HerbEndpointer(pause: pause, noSpeechTimeout: noSpeechTimeout, now: Self.now)
        state = .listening
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.state == .listening, let e = self.endpointer else { return }
                switch e.decide(at: Self.now) {
                case .keepListening: continue
                case .finish(let text): self.endTurn(text)
                case .giveUp: self.endTurn(nil)
                }
            }
        }
    }

    private func heard(_ text: String) {
        transcript = text
        endpointer?.heard(text, at: Self.now)
    }

    /// Ends the turn and reports it.
    private func endTurn(_ text: String?) {
        request?.endAudio()
        stopAudio()
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(t?.isEmpty == false ? t : nil)
    }

    private func finish(_ text: String?) {
        let callback = onFinish
        onFinish = nil
        callback?(text)
    }

    private static var now: Double { Date.timeIntervalSinceReferenceDate }

    /// The user tapped the mic: stops listening without reporting the turn, and returns what was heard so far.
    @discardableResult
    func stop() -> String {
        onFinish = nil
        request?.endAudio()
        stopAudio()
        return transcript
    }

    // Apple calls these back on its own threads. They're nonisolated so Swift doesn't treat the callbacks as
    // main-thread code: under Swift 6 that check crashes the app the moment the callback arrives (it did when
    // testers tapped Allow on the speech permission prompt).

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    nonisolated private static func feed(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(_ request: SFSpeechAudioBufferRecognitionRequest, with recognizer: SFSpeechRecognizer,
                                              update: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false), error != nil)
        }
    }

    private func stopAudio() {
        watcher?.cancel()
        watcher = nil
        endpointer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        if state == .listening { state = .idle }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

#if DEBUG
extension SpeechInput {
    /// Simulator testing (the simulator can't recognize speech): launch with `-HerbFakeMic "first turn|second turn"`
    /// and each time HERB listens, the next turn is "spoken" a word at a time and then the user goes quiet.
    /// A turn of "-" says nothing. Not compiled into TestFlight builds.
    static var fakeTurns: [String]? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-HerbFakeMic"), i + 1 < args.count else { return nil }
        return args[i + 1].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }()

    fileprivate func startFake(pause: Double, noSpeechTimeout: Double) {
        beginTurn(pause: pause, noSpeechTimeout: noSpeechTimeout)
        guard var turns = Self.fakeTurns, !turns.isEmpty else { return }
        let turn = turns.removeFirst()
        Self.fakeTurns = turns
        guard turn != "-" else { return }
        Task { [weak self] in
            var said: [Substring] = []
            for word in turn.split(separator: " ") {
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, self.state == .listening else { return }
                said.append(word)
                self.heard(said.joined(separator: " "))
            }
        }
    }
}
#endif

/// HERB's voice. Replies are short, written to be heard in a car.
@MainActor
final class SpeechOutput {
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        #endif
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(u)
    }

    /// Speaks and returns when HERB has finished (or was interrupted with `stop()`), so HERB can listen again.
    func speak(_ text: String) async {
        say(text)
        for _ in 0..<20 where !synth.isSpeaking { try? await Task.sleep(for: .milliseconds(50)) }
        while synth.isSpeaking { try? await Task.sleep(for: .milliseconds(100)) }
    }

    var isSpeaking: Bool { synth.isSpeaking }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
