import Foundation

// Hands-free conversation with HERB (design §23). iOS doesn't let an app listen for its own wake word, so the user
// taps the mic once and then just talks: HERB answers when the user pauses, speaks its reply, and listens again
// until the conversation is over. These rules are pure so they can be tested without a microphone.

/// How long a pause ends what the user is saying. Voice assistants typically wait about a second; HERB defaults to a
/// little longer because people pause while reading out phone numbers and addresses.
public enum HerbPause: String, CaseIterable, Codable, Sendable {
    case short, normal, long

    public var seconds: Double {
        switch self {
        case .short: 1.0
        case .normal: 1.5
        case .long: 2.5
        }
    }

    public var label: String {
        switch self {
        case .short: "Short — 1 second"
        case .normal: "Normal — 1.5 seconds"
        case .long: "Long — 2.5 seconds"
        }
    }
}

/// Decides when the user has finished speaking, from the partial transcripts the speech recognizer reports.
/// Times are seconds on any steady clock.
public struct HerbEndpointer: Sendable {
    public enum Decision: Equatable, Sendable {
        case keepListening
        /// The user finished; send this text.
        case finish(String)
        /// Nothing was said before the no-speech timeout.
        case giveUp
    }

    /// Silence after speech that ends the turn.
    public let pause: Double
    /// How long to wait for the user to start talking.
    public let noSpeechTimeout: Double
    private let started: Double
    private var lastChange: Double?
    public private(set) var text = ""

    /// Saying one of these at the end sends right away, without waiting for the pause.
    public static let sendWords = ["send", "send it", "over"]

    public init(pause: Double, noSpeechTimeout: Double, now: Double) {
        self.pause = pause
        self.noSpeechTimeout = noSpeechTimeout
        started = now
    }

    /// Records the recognizer's latest transcript of the whole utterance.
    public mutating func heard(_ transcript: String, at now: Double) {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != text else { return }
        text = t
        lastChange = now
    }

    public func decide(at now: Double) -> Decision {
        if let body = Self.strippingSendWord(text) { return body.isEmpty ? .giveUp : .finish(body) }
        if let lastChange, !text.isEmpty {
            return now - lastChange >= pause ? .finish(text) : .keepListening
        }
        return now - started >= noSpeechTimeout ? .giveUp : .keepListening
    }

    /// "New prospect Tom Rodgers, send" → "New prospect Tom Rodgers"; nil when the text doesn't end with a send word.
    public static func strippingSendWord(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0 == " " })
        let plain = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        for phrase in sendWords {
            let p = phrase.split(separator: " ").map(String.init)
            guard plain.count >= p.count, Array(plain.suffix(p.count)) == p else { continue }
            return words.dropLast(p.count).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-—"))
        }
        return nil
    }
}

/// When a hands-free conversation continues.
public enum HerbConversation {
    /// How long HERB waits for an answer to its own question.
    public static let answerTimeout = 12.0
    /// How long HERB stays open for a follow-up after it has finished something.
    public static let followUpTimeout = 6.0
    /// How long HERB waits after the user first taps the mic.
    public static let firstTimeout = 8.0

    /// Whole utterances that end the conversation ("stop", "that's all", "thanks").
    public static func isGoodbye(_ text: String) -> Bool {
        // Lowercase, keep apostrophes, drop other punctuation, and ignore "Hey Herb" / "Herb" around the words.
        let cleaned = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        var words = String(cleaned).split(separator: " ").map(String.init)
        if words.count > 1, ["hey", "hi", "ok", "okay"].contains(words[0]), words[1] == "herb" { words.removeFirst(2) }
        if words.last == "herb" { words.removeLast() }
        return goodbyes.contains(words.joined(separator: " "))
    }

    static let goodbyes: Set<String> = [
        "stop", "stop listening", "that's all", "that is all", "that's it", "no that's all", "no that's it",
        "i'm done", "im done", "i am done", "goodbye", "bye", "thanks", "thank you", "no thanks", "nothing else",
        "that'll be all", "we're done", "all done",
    ]

    /// Seconds to listen for the user's next turn after HERB replies, or nil when the conversation is over.
    public static func listenAgain(after reply: HerbReply) -> Double? {
        if reply.openForm { return nil }                    // a form opened: the user is working on screen now
        if reply.state != nil { return answerTimeout }      // HERB asked something and is waiting for the answer
        return followUpTimeout                              // done; stay open briefly for "anything else"
    }
}
