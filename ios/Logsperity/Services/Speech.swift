import AVFoundation
import Foundation
import Observation
import Speech

/// Push-to-talk speech recognition, on the device when the phone supports it (design §23: the real app
/// recognizes speech on the device; iOS doesn't allow an always-on custom wake word).
@MainActor @Observable
final class SpeechInput {
    enum State: Equatable { case idle, listening, denied, unavailable }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

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

    func start() async {
        guard state != .listening else { return }
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        guard await authorize() else { return }
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
            state = .listening
            task = Self.recognize(req, with: recognizer) { [weak self] text, done, failed in
                Task { @MainActor in
                    guard let self else { return }
                    let wasListening = self.state == .listening  // false once the user tapped stop
                    if let text { self.transcript = text }
                    if done { self.stopAudio() }
                    // Recognition failed before hearing anything (e.g. Dictation is off): say so instead of going quiet.
                    if failed && wasListening && self.transcript.isEmpty { self.state = .unavailable }
                }
            }
        } catch {
            stopAudio()
            state = .unavailable
        }
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stop() -> String {
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

    func stop() { synth.stopSpeaking(at: .immediate) }
}
