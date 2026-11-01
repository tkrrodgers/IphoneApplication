import Testing
@testable import LogsperityCore

// Hands-free conversation rules: when the user has finished speaking, and whether HERB listens again.

@Test func pauseEndsTheTurn() {
    var e = HerbEndpointer(pause: 1.5, noSpeechTimeout: 8, now: 0)
    e.heard("New prospect", at: 1.0)
    e.heard("New prospect Tom Rodgers", at: 1.6)
    #expect(e.decide(at: 2.5) == .keepListening)  // a short breath isn't the end
    #expect(e.decide(at: 3.1) == .finish("New prospect Tom Rodgers"))
}

@Test func pausesBetweenDigitsDontCutTheUserOff() {
    var e = HerbEndpointer(pause: HerbPause.normal.seconds, noSpeechTimeout: 8, now: 0)
    e.heard("Tom Rodgers 847", at: 1.0)
    e.heard("Tom Rodgers 847 477", at: 2.2)  // 1.2 s pause while reading the number
    #expect(e.decide(at: 3.4) == .keepListening)
    e.heard("Tom Rodgers 847 477 0619", at: 3.4)
    #expect(e.decide(at: 4.95) == .finish("Tom Rodgers 847 477 0619"))
}

@Test func theSameTranscriptAgainIsNotNewSpeech() {
    var e = HerbEndpointer(pause: 1.0, noSpeechTimeout: 8, now: 0)
    e.heard("yes", at: 1.0)
    e.heard("yes ", at: 1.8)  // the recognizer repeats itself while the user is silent
    #expect(e.decide(at: 2.05) == .finish("yes"))
}

@Test func silenceGivesUp() {
    let e = HerbEndpointer(pause: 1.5, noSpeechTimeout: 6, now: 10)
    #expect(e.decide(at: 15) == .keepListening)
    #expect(e.decide(at: 16) == .giveUp)
}

@Test func sayingSendSendsRightAway() {
    var e = HerbEndpointer(pause: 2.5, noSpeechTimeout: 8, now: 0)
    e.heard("Lunch with Dana, 45 dollars, send", at: 1)
    #expect(e.decide(at: 1.1) == .finish("Lunch with Dana, 45 dollars"))
    #expect(HerbEndpointer.strippingSendWord("Two hours of door knocking. Over.") == "Two hours of door knocking")
    #expect(HerbEndpointer.strippingSendWord("Send it") == "")
    #expect(HerbEndpointer.strippingSendWord("Send me the March report") == nil)  // only at the end
}

@Test func goodbyesEndTheConversation() {
    for t in ["Stop", "that's all", "That’s it, Herb.", "Thanks Herb", "hey Herb, I'm done", "No thanks"] {
        #expect(HerbConversation.isGoodbye(t), "\(t)")
    }
    for t in ["No", "Yes", "stop the trip", "thanks for lunch, 45 dollars", "Tom Rodgers"] {
        #expect(!HerbConversation.isGoodbye(t), "\(t)")
    }
}

/// The pilot testers' flow: name and phone, pause, HERB offers the address, "yes", HERB asks for it, and so on.
@Test func herbKeepsListeningWhileItHasAQuestion() {
    var c = Convo()
    var r = c.say("New prospect Tom Rodgers, 847 477 0619")
    #expect(r.say.hasSuffix("Do you want to add an address?"))
    #expect(HerbConversation.listenAgain(after: r) == HerbConversation.answerTimeout)
    r = c.say("Yes")
    #expect(r.say == "What's the address?")
    #expect(HerbConversation.listenAgain(after: r) == HerbConversation.answerTimeout)
    r = c.say("216 Shadow Creek Lane in Hickory Creek")
    #expect(r.say.hasSuffix("Who referred Tom, or where did the lead come from?"))
    r = c.say("Ruth Alvarez sent him")
    #expect(r.say.contains("When should you follow up with Tom"))
    r = c.say("Monday")
    #expect(r.say.hasSuffix("Save it?"))
    #expect(HerbConversation.listenAgain(after: r) == HerbConversation.answerTimeout)
    r = c.say("yes")
    #expect(r.state == nil)
    #expect(HerbConversation.listenAgain(after: r) == HerbConversation.followUpTimeout)  // open for "anything else"
}
