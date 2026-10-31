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
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
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
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()
            state = .listening
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let done = error != nil || (result?.isFinal ?? false)
                Task { @MainActor in
                    if let text { self?.transcript = text }
                    if done { self?.stopAudio() }
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
