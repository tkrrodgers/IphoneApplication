import Foundation

// HERB's rule-based parser (design §17.2 rule 1): wake words, numbers, money, phone numbers, durations, dates,
// names, sources, category/activity keywords and lead strength. On the iPhone the on-device model fills the same
// fields; these rules are the tested fallback and the reference. Port of herb-sim/herb.py's text helpers.

/// (sub-pillar, category, activity): where a prospect or activity came from.
struct HerbTags: Hashable, Sendable {
    let sub: SubPillar
    let cat: String
    let act: String

    init(_ sub: SubPillar, _ cat: String, _ act: String) {
        self.sub = sub
        self.cat = cat
        self.act = act
    }
}

/// A money-like number in an utterance. `explicit` when it had a $ or a money unit.
struct HerbAmount: Hashable, Sendable {
    let value: Double
    let start: Int
    let end: Int
    let explicit: Bool
}

enum HerbParse {
    static let wake = Rx(#"^\s*(?:(?:hey\s+)?siri\s*,?\s*ask\s+herb\b|(?:ok(?:ay)?\s+)?(?:(?:hi|hey|hello|yo)\s*,?\s*)?herb\b)[\s,.!:;-]*"#, true)
    static let wordNums: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    static let monthNamesLower = monthNames.map { $0.lowercased() }
    static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let stopwords: Set<String> = ["the", "and", "of", "co", "inc", "llc", "com", "a", "at", "in", "on", "to", "for"]

    static func stripWake(_ text: String) -> String { wake.sub(text, "").trimmed }

    static let couple = Rx(#"\ba couple of\b|\ba couple\b"#, true)
    static let numberWords: Rx = {
        let keys = wordNums.keys.sorted { ($0.count, $1) > ($1.count, $0) }.joined(separator: "|")
        return Rx("\\b(?:\(keys))(?:[\\s-](?:\(keys)))?\\b", true)
    }()
    static let numberSplit = Rx(#"[\s-]+"#)

    /// "two hours" → "2 hours", "forty five minutes" → "45 minutes", "a couple of" → "2".
    static func wordsToDigits(_ text: String) -> String {
        numberWords.sub(couple.sub(text, "2")) { m in
            String(numberSplit.split(m[0]!.lowercased()).reduce(0) { $0 + (wordNums[$1] ?? 0) })
        }
    }

    static let phoneRx = Rx(#"(?:\+?1[\s.-]?)?\(?\b(\d{3})\)?[\s.-]?(\d{3})[\s.-]?(\d{4})\b"#)

    /// "(940) 555-0137" and where it was in the text.
    static func phone(_ text: String) -> (String, (Int, Int))? {
        guard let m = phoneRx.search(text) else { return nil }
        return ("(\(m[1]!)) \(m[2]!)-\(m[3]!)", (m.start, m.end))
    }

    static let amountRx = Rx(#"(?<![\w.])(\$\s?)?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(k\b|thousand\b|grand\b|million\b|mil\b|m\b|bucks\b|dollars?\b)?"#, true)
    static let nonMoneyAfter = Rx(#"^\s*(?:am|pm|a\.m\.|p\.m\.|o'?clock|days?|weeks?|months?|years?|miles?|mi\b|minutes?|mins?|hours?|hrs?|h\b|leads?|prospects?|people|percent|%|:\d|st\b|nd\b|rd\b|th\b|transactions?|deals?|homes?|units?)"#, true)
    static let nonMoneyBefore = Rx(#"(?:after|at|around|by|before|until|till|room|suite|number|#|jan\w*|feb\w*|mar\w*|apr\w*|may|jun\w*|jul\w*|aug\w*|sep\w*|oct\w*|nov\w*|dec\w*)\s*$"#, true)

    /// All money-like numbers, skipping times, days, miles, counts and dates.
    static func amounts(_ text: String) -> [HerbAmount] {
        var out: [HerbAmount] = []
        for m in amountRx.findAll(text) {
            let before = text.u16(to: m.start)
            if m[1] == nil && m[3] == nil {
                if nonMoneyAfter.match(text.u16(from: m.end)) != nil || nonMoneyBefore.test(before) { continue }
            } else if let u = m[3], m[1] == nil, nonMoneyAfter.match(u) != nil {
                continue
            }
            var v = Double(m[2]!.replacingOccurrences(of: ",", with: "")) ?? 0
            let unit = (m[3] ?? "").lowercased()
            if ["k", "thousand", "grand"].contains(unit) { v *= 1000 }
            else if ["million", "mil", "m"].contains(unit) { v *= 1_000_000 }
            out.append(HerbAmount(value: v, start: m.start, end: m.end, explicit: m[1] != nil || !unit.isEmpty))
        }
        return out
    }

    static let hourAndHalf = Rx(#"\ban hour and a half\b|\b1 and a half hours?\b|\bhour and a half\b"#)
    static let halfHour = Rx(#"\bhalf an hour\b|\ba half hour\b"#)
    static let oneHour = Rx(#"\b(?:an|one) hour\b"#)
    static let hoursRx = Rx(#"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\b(?:\s*and\s*(?:a\s*)?half)?(?:\s*(?:and\s*)?(\d+)\s*(?:minutes?|mins?))?"#)
    static let minutesRx = Rx(#"(\d+)\s*(?:minutes?|mins?)\b"#)

    /// Minutes in 15-minute steps (FR-23), or nil when no duration was said.
    static func durationMinutes(_ text: String) -> Int? {
        var t = wordsToDigits(text.lowercased())
        t = hourAndHalf.sub(t, "90 minutes")
        t = halfHour.sub(t, "30 minutes")
        t = oneHour.sub(t, "60 minutes")
        var total = 0.0
        if let m = hoursRx.search(t) {
            total = Double(m[1]!)! * 60 + (m[0]!.contains("half") ? 30 : 0) + (m[2].flatMap(Double.init) ?? 0)
        } else if let m = minutesRx.search(t) {
            total = Double(m[1]!)!
        }
        guard total != 0 else { return nil }
        return Int(max(15, pyRound(total / 15) * 15))
    }

    static let todayRx = Rx(#"\btoday\b|\btonight\b|\bthis (?:afternoon|evening)\b"#)
    static let inNRx = Rx(#"\bin (\d+|a|an|one|two|three|four|five|six|seven|ten) (day|week|month)s?\b"#)
    static let weekdayRx = weekdays.map { Rx("\\b\($0)\\b") }
    static let monthDayRx = Rx("\\b(" + monthNamesLower.map { String($0.prefix(3)) }.joined(separator: "|") + #")[a-z]*\.?\s+(\d{1,2})\b"#)

    /// A future date: today, tomorrow, next week (Monday), in N days/weeks/months, a weekday, "Nov 5".
    static func parseWhen(_ text: String, now: Day) -> Day? {
        let t = text.lowercased()
        if todayRx.test(t) { return now }
        if t.contains("tomorrow") { return now.adding(days: 1) }
        if t.contains("next week") { return now.adding(days: 7 - now.weekday) }
        if let m = inNRx.search(t) {
            let g = m[1]!
            let n = ["a": 1, "an": 1][g] ?? Int(wordsToDigits(g)) ?? 1
            return now.adding(days: n * ["day": 1, "week": 7, "month": 30][m[2]!]!)
        }
        for (i, rx) in weekdayRx.enumerated() where rx.test(t) {
            let delta = ((i - now.weekday) % 7 + 7) % 7
            return now.adding(days: delta == 0 ? 7 : delta)
        }
        if let m = monthDayRx.search(t) {
            let mo = monthNamesLower.map { String($0.prefix(3)) }.firstIndex(of: m[1]!)! + 1
            let day = min(Int(m[2]!)!, mo == 2 ? 28 : [4, 6, 9, 11].contains(mo) ? 30 : 31)
            let d = Day(now.year, mo, max(1, day))
            return d >= now ? d : Day(now.year + 1, mo, d.day)
        }
        return nil
    }

    static let timeRx = Rx(#"\b(?:after|at|around|by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#, true)

    /// "after 5" → "5:00 PM".
    static func parseTime(_ text: String) -> String? {
        guard let m = timeRx.search(text) else { return nil }
        let h = Int(m[1]!)!, mi = Int(m[2] ?? "0") ?? 0
        var ap = (m[3] ?? "").lowercased().replacingOccurrences(of: ".", with: "")
        if ap.isEmpty { ap = (1...7).contains(h) ? "pm" : "am" }
        return "\(h):\(String(format: "%02d", mi)) \(ap.uppercased())"
    }

    // MARK: Names

    static let nameToken = #"[A-Z][a-z'’\-]+"#
    static let person = "\(nameToken)(?:\\s+(?:&|and)\\s+\(nameToken))?(?:\\s+\(nameToken)){1,2}"
    static let nameRx = Rx("\\b(\(person))\\b")
    static let nameCue = Rx("(?:lead|prospect|buyer|borrower|client|named|called)[,:]?\\s+(?:is\\s+|named\\s+|called\\s+)?(\(person))")
    static let lowerNameCue = Rx(#"(?:new lead|new prospect|lead|prospect)[,:]?\s+([a-z]+)\s+([a-z]+)"#, true)
    static let notNames: Set<String> = [
        "Hi", "Hey", "Herb", "New", "I", "The", "Got", "Log", "Lunch", "Dinner", "Coffee", "Thursday", "Monday", "Tuesday",
        "Wednesday", "Friday", "Saturday", "Sunday", "Open", "House", "Zillow", "LeadBoost", "Save", "Add", "Record",
        "Prospect", "Lead", "Closed", "Spent", "Drove", "Start", "Email", "Send", "What", "Which", "Who", "How", "Am", "My",
        "Our", "Started", "Yes", "No", "January", "February", "March", "April", "May", "June", "July", "August",
        "September", "October", "November", "December",
    ]

    /// "Tom & Ana Becker" → ("Tom & Ana", "Becker").
    static func splitName(_ full: String) -> (String, String) {
        let parts = full.words
        if parts.count >= 3 && (parts[1] == "&" || parts[1] == "and") {
            return (parts.dropLast().joined(separator: " ").replacingOccurrences(of: " and ", with: " & "), parts.last!)
        }
        return (parts.dropLast().joined(separator: " "), parts.last ?? "")
    }

    /// Strips non-name words from both ends; nil unless two words are left.
    static func cleanPerson(_ c: String) -> String? {
        var words = c.words[...]
        while let w = words.first, notNames.contains(w) { words = words.dropFirst() }
        while let w = words.last, notNames.contains(w) { words = words.dropLast() }
        return words.count >= 2 ? words.joined(separator: " ") : nil
    }

    /// Best guess at a new person's full name in the utterance.
    static func findPersonName(_ text: String, exclude: [String] = []) -> String? {
        var cands: [String] = []
        if let m = nameCue.search(text) { cands.append(m[1]!) }
        cands += nameRx.findAll(text).compactMap { $0[1] }
        for c in cands {
            guard let c2 = cleanPerson(c) else { continue }
            let l = c2.lowercased()
            if exclude.contains(where: { !$0.isEmpty && (l.contains($0.lowercased()) || $0.lowercased().contains(l)) }) { continue }
            return c2
        }
        if let m = lowerNameCue.search(text), !["from", "for", "with", "to", "is", "named"].contains(m[1]!.lowercased()),
           !["from", "referred", "sent", "at", "who", "wants"].contains(m[2]!.lowercased()) {
            return "\(m[1]!.pyTitle) \(m[2]!.pyTitle)"
        }
        return nil
    }

    static let tokenRx = Rx("[a-z0-9]+")
    static func tokens(_ text: String?) -> [String] { tokenRx.findAll((text ?? "").lowercased()).map { $0[0]! } }

    // MARK: Keywords

    static let categoryKeywords: [(Rx, HerbTags)] = rxTable([
        (#"past client|former client|old client|closed with (?:me|us)"#, HerbTags(.clients, "cat.past_client", "act.past_client_interaction")),
        ("current client", HerbTags(.clients, "cat.current_client", "act.current_client_interaction")),
        (#"zillow|realtor\.com|leadboost|lead boost|web lead|online lead|paid lead|internet lead"#,
         HerbTags(.internet, "cat.website_paid", "act.website_ad_set_up_paid")),
        ("open house", HerbTags(.prospecting, "cat.open_house", "act.open_houses")),
        ("door ?knock", HerbTags(.prospecting, "cat.door_knocking", "act.door_knocking")),
        ("cold call", HerbTags(.prospecting, "cat.cold_calls", "act.cold_calling")),
        (#"seminar|workshop|class\b"#, HerbTags(.prospecting, "cat.seminar", "act.seminar")),
        (#"trade show|expo\b"#, HerbTags(.prospecting, "cat.trade_show", "act.trade_show")),
        ("chamber|mixer|networking event", HerbTags(.prospecting, "cat.network_open_group", "act.networking_open_group")),
        ("insurance", HerbTags(.professional, "cat.insurance_agent", "act.networking_closed_group")),
        (#"\bcpa\b|accountant"#, HerbTags(.professional, "cat.accountant", "act.relationship_building_professional")),
        ("attorney|lawyer", HerbTags(.professional, "cat.attorney", "act.relationship_building_professional")),
        ("builder|contractor", HerbTags(.professional, "cat.contractor", "act.relationship_building_professional")),
        ("financial planner|advisor", HerbTags(.professional, "cat.financial_planner", "act.relationship_building_professional")),
        (#"realtor|real estate agent|listing agent|buyer'?s agent|agent at"#,
         HerbTags(.professional, "cat.realtor", "act.relationship_building_professional")),
        (#"brother|sister|\bmom\b|\bdad\b|cousin|family|uncle|aunt|in-law"#,
         HerbTags(.personal, "cat.family", "act.relationship_building_personal")),
        ("friend|neighbor", HerbTags(.personal, "cat.friend", "act.relationship_building_personal")),
        ("church", HerbTags(.personal, "cat.church", "act.community_involvement_personal")),
        (#"website|my site|\bblog\b"#, HerbTags(.internet, "cat.website_personal", "act.website_set_up")),
        ("mailer|postcard|farm", HerbTags(.traditional, "cat.mailer_farming", "act.mail_campaigning.advertising")),
        (#"\bsign\b|yard sign"#, HerbTags(.traditional, "cat.sign", "act.sign_set_up")),
    ] as [(String, HerbTags)])

    static let activityKeywords: [(Rx, String)] = rxTable([
        ("door ?knock", "act.door_knocking"), ("open house", "act.open_houses"), ("cold call", "act.cold_calling"),
        ("seminar|workshop", "act.seminar"), (#"trade show|expo\b"#, "act.trade_show"),
        ("chamber|mixer|networking event|open networking", "act.networking_open_group"),
        ("bni|networking group|closed group|leads group|breakfast group", "act.networking_closed_group"),
        ("past client|former client", "act.past_client_interaction"),
        ("current client", "act.current_client_interaction"),
        (#"partner coaching|coaching (?:dana|ruth|kim|jared|realtor)"#, "act.partner_coaching"),
        ("database", "act.database_marketing"), ("email campaign", "act.email_campaigning"),
        ("facebook", "act.facebook_marketing"), ("newsletter", "act.newsletter_campaigning"),
        (#"\bblog\b"#, "act.blog_development"), ("video", "act.video_production"),
        ("zillow|leadboost|lead boost|paid leads|web leads", "act.website_ad_set_up_paid"),
        ("website", "act.website_set_up"), ("mailer|mail campaign|postcards", "act.mail_campaigning.advertising"),
        ("floor time", "act.floor_time"), ("office visit", "act.office_visits"),
        ("expired", "act.expired_listings_calling"), ("committee", "act.committee_involvement.relationships"),
        ("volunteer|community|church", "act.community_involvement_personal"),
        ("sociali[sz]|party|happy hour", "act.socializing"),
        ("realtor|agent|lunch with|coffee with|breakfast with|meeting with|met with", "act.relationship_building_professional"),
    ] as [(String, String)])

    static func inferFromKeywords(_ text: String) -> HerbTags? {
        let t = text.lowercased()
        return categoryKeywords.first { $0.0.test(t) }?.1
    }

    static func inferActivity(_ text: String) -> String? {
        let t = text.lowercased()
        return activityKeywords.first { $0.0.test(t) }?.1
    }

    static let redHot = Rx(#"red hot|urgent|asap|ready (?:now|today)|right away"#)
    static let noGo = Rx(#"no go|not interested"#)
    static let hot = Rx(#"\bhot\b|ready to (?:buy|go|move)|pre-?approved|serious|motivated|move-?up|wants to talk"#)
    static let cold = Rx(#"just looking|not sure|maybe|someday|next year|\bcold\b"#)

    /// A Strength raw value ("medium" when nothing says otherwise).
    static func strengthFrom(_ text: String) -> String {
        let t = text.lowercased()
        if redHot.test(t) { return "red_hot" }
        if noGo.test(t) { return "no_go" }
        if hot.test(t) { return "hot" }
        if cold.test(t) { return "cold" }
        return "medium"
    }

    /// (pillar, category, activity) names, "?" when unknown.
    static func tagNames(_ sub: String?, _ cat: String?, _ act: String?) -> (String, String, String) {
        (sub.flatMap { SubPillar(rawValue: $0)?.pillar.name } ?? "?",
         cat.flatMap { Taxonomy.categoryByID[$0]?.name } ?? "?",
         act.flatMap { Taxonomy.activityByID[$0]?.name } ?? "?")
    }

    static let incomeTypeWords: [(Rx, String)] = rxTable([
        ("referral fee", "referral_fees"), ("consult", "consulting_fees"), ("bonus|incentive", "bonuses"),
        ("profit shar", "profit_sharing"), ("wage|salary|paycheck", "base_wages"), ("allowance", "allowance"),
        (#"commission|comp\b"#, "commission"),
    ] as [(String, String)], ci: true)

    static let expenseKeywords: [(Rx, String, String)] = ([
        ("closing gift", "clients", "exp.clients.closing_gift"),
        ("gift", "clients", "exp.clients.thank_you_gifts"),
        (#"\bgas\b|fuel"#, "travel", "exp.travel.car_expenses"),
        ("parking|uber|lyft|toll|taxi", "travel", "exp.travel.transportation"),
        ("hotel|lodging|airbnb", "travel", "exp.travel.lodging"),
        (#"open house.*(?:flyer|print)|(?:flyer|print).*open house"#, "prospecting", "exp.prospecting.leave_behind_material"),
        (#"flyers?|printing|print\b"#, "general", "exp.general.printing"),
        ("postage|stamps", "general", "exp.general.postage"),
        (#"\bups\b|fedex|shipping"#, "general", "exp.general.shipping"),
        (#"office supplies|supplies|paper|ink|toner|office depot|staples\b|folders"#, "general", "exp.general.office_supplies"),
        (#"software|subscription|\bapp\b|crm"#, "technology", "exp.technology.software"),
        (#"zillow|leadboost|lead boost|leads\b"#, "ad_internet", "exp.ad_internet.website_ad"),
        ("mailers?|postcards?", "ad_traditional", "exp.ad_traditional.mailers"),
        ("dues|membership", "relationships", "exp.relationships.networking_dues"),
        (#"training|course|continuing ed|\bce\b|class"#, "self_improvement", "exp.self_improvement.training"),
        ("coaching", "self_improvement", "exp.self_improvement.coaching_fees"),
        (#"phone bill|cell phone|\bphone\b"#, "general", "exp.general.phone"),
        ("license|nmls", "general", "exp.general.license"),
    ] as [(String, String, String)]).map { (Rx($0.0, true), $0.1, $0.2) }

    static let meal = Rx(#"\blunch\b|\bdinner\b|\bbreakfast\b|\bcoffee\b|\bdrinks\b|\bmeal\b"#, true)

    // MARK: Intents

    static let questionStart = Rx(#"^(?:what|which|who|whom|how|am|are|is|where|when|do|does|did|can|could|should|would|will|tell me|show me|give me|list)\b"#, true)

    static func isQuestion(_ t: String) -> Bool { questionStart.match(t) != nil || t.hasSuffix("?") }

    static let queryIntents: [(HerbIntent, Rx)] = ([
        (.help, #"what can you do|\bhelp\b|how do i use"#),
        (.review, #"need from me|review queue|anything to review|what needs review|needs? my review"#),
        (.focus, #"\bfocus\b|what should i (?:do|work on)|make more money|priorit"#),
        (.followUps, #"follow[ -]?ups?|follow up|who (?:do|should) i (?:call|contact|text)|overdue|who needs me"#),
        (.report, #"\b(?:email|send|print)\b.*\breport\b|\breport\b"#),
        (.pace, #"on track|on pace|\bpace\b|behind|ahead of|my goal|reach my goal"#),
        (.index, #"\bindex\b|logsperity score|my score"#),
        (.sourcesNoClose, #"never close|don'?t close|do not close|not converting|no closings|never convert"#),
        (.conversion, #"convert|conversion|close rate|closing rate"#),
        (.efficiency, #"wast\w* (?:my )?time|efficien|hours per|time per"#),
        (.roi, #"\broi\b|return on|best return|most profitable|profitab"#),
        (.topSources, #"(?:which|top|best) (?:realtors?|agents?|agenc\w+|sources?|referr\w+|partners?)|who sends|made me the most|most money|most income"#),
        (.incomeSummary, #"how much (?:have i|did i) (?:made|make|earn)|income|earned|commission"#),
        (.expensesSummary, #"expenses?|spend(?:ing)?|spent|cost"#),
        (.mileageSummary, #"mileage|how many miles|miles (?:have i|did i)"#),
        (.plan, #"business plan|\bplan\b|\bgoals?\b"#),
    ] as [(HerbIntent, String)]).map { ($0.0, Rx($0.1)) }

    static let logIntents: [(HerbIntent, Rx)] = ([
        (.logTrip, #"start (?:a |my )?(?:business )?trip|end (?:the |my )?trip|stop (?:the |my )?trip|\bi'?m here\b|\barrived\b|\bdrove\b|\bdriving to\b|\bmiles to\b"#),
        (.logClosing, #"\bclosed\b|\bfunded\b|\bclosing\b|\bclosed on\b"#),
        (.logExpense, #"scan (?:a |my )?receipt|\breceipt\b|\blunch\b|\bdinner\b|\bbreakfast\b|\bcoffee\b|\bbought\b|\bpaid (?:for|\$)|\bexpense\b|\bspent\b|\bgas\b|\bparking\b|\bgift\b"#),
        (.logIncome, #"referral fee|consulting fee|\bbonus\b|profit sharing|got paid|received (?:a |my )?|\bincome\b|commission check|\bgot (?:a |my )?(?:\$|\d)"#),
        (.logProspect, #"new (?:lead|prospect)|leads? to record|record (?:a |some )?leads?|log (?:a )?(?:lead|prospect)|referred|sent (?:him|her|them|me|over)|\bprospect\b|\blead\b"#),
        (.logActivity, #"(?:\d|an?|one|two|three|four|five|half)\s*(?:hours?|hrs?|minutes?|mins?)\b"#),
    ] as [(HerbIntent, String)]).map { ($0.0, Rx($0.1)) }

    static let smalltalkRx = Rx.full(#"(?:hi|hello|hey|thanks?|thank you|good (?:morning|afternoon|evening))[.!]?"#)

    static func detectIntent(_ text: String) -> HerbIntent {
        let t = text.lowercased().trimmed
        guard !t.isEmpty else { return .unknown }
        let isQ = isQuestion(t)
        if smalltalkRx.match(t) != nil { return .smalltalk }
        let order = isQ ? queryIntents + logIntents : logIntents + queryIntents
        // "I spent two hours door knocking" is activity, not expense
        if !isQ, durationMinutes(t) != nil, !rxTest(#"\$|dollars|bucks"#, t, ci: false), !rxTest(#"\bclosed\b|\bfunded\b"#, t, ci: false),
           !rxTest(#"start (?:a |my )?trip|drove"#, t, ci: false) {
            return .logActivity
        }
        return order.first { $0.1.test(t) }?.0 ?? .unknown
    }
}

// MARK: Lookups in the book

extension LogBook {
    /// Fuzzy-match a known source (person, company, venue) mentioned in the text.
    func matchSource(_ text: String, exclude: [String] = []) -> SourceRecord? {
        let ex = Set(exclude.map { $0.lowercased() })
        let toks = Set(HerbParse.tokens(text)).subtracting(ex)
        var counts: [RecordID: Int] = [:]
        for p in prospects { if let s = p.attribution.sourceID { counts[s, default: 0] += 1 } }
        var best: SourceRecord?, bestScore = 0.0
        for s in sources {
            let stoks = HerbParse.tokens(s.name).filter { !HerbParse.stopwords.contains($0) && $0.count > 2 }
            guard !stoks.isEmpty else { continue }
            let hits = stoks.filter { t in toks.contains(t) || (t.count > 4 && toks.contains { similarity($0, t) >= 0.88 }) }.count
            guard hits > 0 else { continue }
            let ratio = Double(hits) / Double(stoks.count)
            let score = ratio + (hits == stoks.count ? 0.25 : 0) + Double(min(counts[s.id] ?? 0, 20)) / 1000
            if s.kind == "venue" && hits < stoks.count { continue }
            if score > bestScore && ratio >= 0.5 { (best, bestScore) = (s, score) }
        }
        return best
    }

    func source(_ id: RecordID?) -> SourceRecord? { id.flatMap { id in sources.first { $0.id == id } } }

    var closedProspectIDs: Set<RecordID> { Set(closings.compactMap(\.prospectID)) }

    /// Most common tags for prospects from this source; Clients when the source is a past client (rule R2).
    func sourceProfile(_ sourceID: RecordID) -> HerbTags? {
        if let src = source(sourceID) {
            let parts = src.name.words
            if parts.count >= 2 {
                let first = parts.dropLast().joined(separator: " ").lowercased(), last = parts.last!.lowercased()
                let closed = closedProspectIDs
                if prospects.contains(where: { $0.firstNames.lowercased() == first && $0.lastName.lowercased() == last && closed.contains($0.id) }) {
                    return HerbTags(.clients, "cat.past_client", "act.past_client_interaction")
                }
            }
        }
        var counts: [String: (HerbTags, Int)] = [:]
        for p in prospects where p.attribution.sourceID == sourceID {
            guard let sub = p.attribution.subPillar, let cat = p.attribution.categoryID, let act = p.attribution.activityID else { continue }
            let key = "\(sub.rawValue)|\(cat)|\(act)"
            counts[key] = (HerbTags(sub, cat, act), (counts[key]?.1 ?? 0) + 1)
        }
        return counts.sorted { ($0.value.1, $1.key) > ($1.value.1, $0.key) }.first?.value.0
    }

    /// The source of the most recent activity of this kind ("Open house – 2201 Bonnie Brae").
    func latestSource(forActivity act: String) -> String? {
        var best: ActivityRecord?
        for a in activities where a.attribution.activityID == act && a.attribution.sourceID != nil {
            if best == nil || a.date > best!.date { best = a }
        }
        return best.flatMap { sourceName($0.attribution.sourceID) }
    }

    /// Prospects named in the text, best match first (last name 2 points, each first name 1).
    func prospectCandidates(_ text: String, firstNameOK: Bool = false) -> [(score: Double, prospect: ProspectRecord)] {
        let toks = Set(HerbParse.tokens(text))
        let closed = closedProspectIDs
        let byDate = prospects.enumerated().sorted { ($0.element.date, $1.offset) > ($1.element.date, $0.offset) }.map(\.element)
        var out: [(score: Double, prospect: ProspectRecord)] = []
        for p in byDate {
            let last = p.lastName.lowercased()
            let score = (!last.isEmpty && toks.contains(last) ? 2 : 0)
                + HerbParse.tokens(p.firstNames).filter { toks.contains($0) && $0 != "and" }.count
            if score >= 2 || (firstNameOK && score >= 1) {
                out.append((Double(score) - (closed.contains(p.id) ? 0.5 : 0), p))
            }
        }
        // stable sort, best first
        return out.enumerated().sorted { ($0.element.score, $1.offset) > ($1.element.score, $0.offset) }.map(\.element)
    }

    /// The user's own average income ÷ loan amount, year to date (1.35% when there are no closings yet).
    func closingYield(now: Day) -> Double {
        guard let led = try? Ledger(self, periodKey: "ytd", now: now) else { return 0.0135 }
        return ratio(led.closingIncome, led.volume).flatMap { $0 == 0 ? nil : $0 } ?? 0.0135
    }
}
