import Foundation

// HERB's follow-up questions, part 1 (design §17.2): answer classification, names and places, and the
// per-log extractors that fill a draft from whatever the user said, in any order. Port of dialog.py.

enum HerbDialog {
    // MARK: Answer classification

    static let yes = Rx(#"^(?:yes|yeah|yea|yep|yup|sure|ok(?:ay)?|please|absolutely|definitely|of course|go ahead|sounds good|correct|right|that'?s right|do it|let'?s do it|uh[- ]?huh|both|all of (?:them|it)|why not|y)\b"#, true)
    static let no = Rx(#"^(?:no|nope|nah|not now|not really|not yet|skip(?: it| that)?|pass|none|negative|no thanks|(?:i )?don'?t (?:have|know)(?: (?:it|that|one))?|leave it(?: blank)?|(?:i'?m )?not sure|unknown|nothing|n)\b"#, true)
    static let save = Rx(#"^(?:save|yes|yeah|yep|yup|sure|ok(?:ay)?|correct|right|perfect|great|good|looks (?:good|right|great)|sounds good|that'?s (?:it|all|right|correct|everything|good)|all good|done|confirm|go ahead|do it|y)\b"#, true)
    static let cancel = Rx(#"^(?:cancel|never ?mind|forget (?:it|that|about it)|scratch that|discard(?: it)?|delete (?:it|that)|don'?t save|stop|start over)\b"#, true)
    static let edit = Rx(#"^(?:edit|open (?:the |it in the )?form|let me (?:fix|edit|type|change it myself)|i'?ll type)"#, true)
    static let unknown = Rx(#"\b(?:don'?t know|do not know|no idea|not sure|unknown|can'?t remember|don'?t remember|no clue|not certain|forgot|nobody|no one|called me|called in)\b"#, true)
    static let unknownSource = "Unknown"
    static let later = Rx(#"^(?:later|finish (?:it |this )?later|(?:save|hold|park) (?:it |this )?for later|remind me later|i'?m driving|can'?t talk|i'?ll finish (?:it )?later)\b"#, true)
    static let repeatRx = Rx(#"^(?:what\??|sorry\??|pardon(?: me)?\??|say (?:that|it) again|repeat(?: that)?|come again|huh\??)$"#, true)
    static let done = Rx(#"^(?:no|nope|nah|that'?s (?:it|all|everything)|(?:i'?m |all )?done|no more|finished|not now)\b"#, true)
    static let filler = Rx(#"^(?:(?:um+|uh+|er+|so|well|oh|okay so|ok so|alright|and)[,\s]+)+"#, true)
    static let newEntry = Rx(#"^(?:new (?:lead|prospect|client|contact)|another (?:lead|prospect)|(?:log|record|add) (?:a |an |another )?(?:new )?(?:lead|prospect|expense|trip|activity|income|closing))\b"#, true)
    static let batch = Rx(#"leads? to (?:record|add|log|enter)|(?:record|add|log|enter) (?:some |a few |my )?(?:new )?leads|(?:some|a few|several|a couple of) (?:new )?leads|^new (?:leads|prospects)$"#, true)
    static let only = Rx(#"\b(?:only|just)\b"#, true)
    static let negWord = Rx(#"\b(?:no|skip|without|don'?t (?:need|want|have)|not the)\b"#, true)

    static func clean(_ text: String) -> String {
        filler.sub(HerbParse.stripWake(text).trimmed, "").trimmed.rstrip(".!").trimmed
    }

    /// "sam" → "Sam", "ZILLOW" → "Zillow", "McKay" stays.
    static func cap(_ w: String) -> String {
        w.pyIsLower || (w.pyIsUpper && w.count > 3) ? w.pyCapitalize : w
    }

    /// "Monday, Nov 2" for this coming week, "tomorrow", "Nov 13"; plus a time when one was said.
    static func dayText(_ iso: String?, now: Day, time: String? = nil) -> String {
        guard let iso, let d = Day(iso: iso) else { return "no follow-up" }
        var s = Format.relativeDay(d, now: now)
        let delta = now.days(to: d)
        if 1 < delta && delta < 7 { s += ", \(Format.shortDate(d))" }
        return s + (time.map { " \($0)" } ?? "")
    }

    // MARK: Names and places

    static let nameStop: Set<String> = [
        "from", "referred", "sent", "phone", "cell", "mobile", "at", "who", "wants", "she", "he", "they", "is", "was",
        "lives", "follow", "call", "email", "number", "address", "with", "via", "through", "by", "on", "in", "for",
        "please", "thanks", "she's", "he's", "they're",
    ]
    static let leadInRx = Rx(#"^(?:it'?s|its|it is|this is|that'?s|the name is|name is|(?:his|her|their) name is|name'?s|(?:his|her|their|the) (?:last|first) name is|(?:last|first) name is|it was|i think|(?:he|she|they) (?:is|are|was|were)|from|by|at|the|an?|my|our)\s+"#, true)
    static let solo = Rx(#"\b(?:just me|by myself|myself|alone|nobody|no one|solo|on my own)\b"#, true)
    static let nameWord = Rx(#"[A-Za-z][A-Za-z'’.-]*|&"#)

    static func leadIn(_ t: String) -> String {
        var prev: String?, t = t
        while prev != t {
            prev = t
            t = leadInRx.sub(t.strip(" ,"), "")
        }
        return t
    }

    /// A short free answer read as a name: "sam lee" → "Sam Lee".
    static func bareName(_ t: String, maxWords: Int = 3) -> String? {
        if no.match(t) != nil || yes.match(t) != nil || done.match(t) != nil { return nil }
        var words: [String] = []
        let head = leadIn(t).components(separatedBy: ",")[0]
        for m in nameWord.findAll(head) {
            let w = m[0]!
            if nameStop.contains(w.lowercased()) { break }
            words.append(w)
            if words.count >= maxWords { break }
        }
        return words.isEmpty ? nil : words.map(cap).joined(separator: " ")
    }

    static let lastNameRx = Rx(#"\blast name(?:\s+is|'s|\s+should be)?\s+([A-Za-z'’-]+)"#, true)
    static let firstNameRx = Rx(#"\bfirst name(?:\s+is|'s|\s+should be)?\s+([A-Za-z'’-]+)"#, true)
    static let spellRx = Rx(#"\bspell(?:ed|s)?(?: it)?\s+((?:[A-Za-z][\s.,-]+){2,}[A-Za-z])\b"#, true)
    static let letterRx = Rx("[A-Za-z]")

    static func nameFrom(_ t: String, focus: String?) -> HerbFields {
        var out: HerbFields = [:]
        if let m = lastNameRx.search(t) { out["lastName"] = .string(cap(m[1]!)) }
        if let m = firstNameRx.search(t) { out["firstNames"] = .string(cap(m[1]!)) }
        if let m = spellRx.search(t) {
            let letters = letterRx.findAll(m[1]!).map { $0[0]! }.joined()
            out[focus == "name" && out.isEmpty ? "firstNames" : "lastName"] = .string(letters.pyCapitalize)
        }
        if !out.isEmpty { return out }
        if focus == "lastName" { return bareName(t, maxWords: 1).map { ["lastName": .string($0)] } ?? [:] }
        if focus == "name" {
            guard let n = bareName(t) else { return [:] }
            if n.words.count == 1 { return ["firstNames": .string(n)] }
            let (f, l) = HerbParse.splitName(n)
            return ["firstNames": .string(f), "lastName": .string(l)]
        }
        if let full = HerbParse.findPersonName(t) {
            let (f, l) = HerbParse.splitName(full)
            return ["firstNames": .string(f), "lastName": .string(l)]
        }
        return [:]
    }

    static let states: [String: String] = {
        let names = "alabama alaska arizona arkansas california colorado connecticut delaware florida georgia hawaii idaho illinois indiana iowa kansas kentucky louisiana maine maryland massachusetts michigan minnesota mississippi missouri montana nebraska nevada new_hampshire new_jersey new_mexico new_york north_carolina north_dakota ohio oklahoma oregon pennsylvania rhode_island south_carolina south_dakota tennessee texas utah vermont virginia washington west_virginia wisconsin wyoming district_of_columbia".words
        let abbrs = "AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC".words
        return Dictionary(uniqueKeysWithValues: zip(names.map { $0.replacingOccurrences(of: "_", with: " ") }, abbrs))
    }()
    static let stateAbbrs = Set(states.values)
    static let street = "(?:lane|ln|street|st|drive|dr|road|rd|avenue|ave|court|ct|circle|cir|boulevard|blvd|way|place|pl|trail|trl|parkway|pkwy|highway|hwy|loop|terrace|ter|cove|cv|crossing|xing|square|sq|plaza)"
    static let addrRx = Rx("\\b(\\d{1,6}[A-Za-z]?\\s+(?:[A-Za-z0-9'’.-]+\\s+){0,4}\(street)\\b\\.?(?:\\s*,?\\s*(?:apt|apartment|unit|suite|ste|#)\\.?\\s*[\\w-]+)?)", true)
    static let addrLoose = Rx(#"\b(\d{1,6}[A-Za-z]?(?:\s+[A-Za-z0-9'’.#-]+){1,5}?)\s*(?=,|\s+in\s|$)"#, true)
    static let placeToken = Rx(#"\s*([A-Za-z][A-Za-z'’.-]*|\d+|[,;])"#)
    static let zipRx = Rx.full(#"\d{5}"#)
    static let cityStop: Set<String> = Set([
        "follow", "followup", "call", "phone", "cell", "mobile", "email", "wants", "referred", "sent", "next", "from", "he",
        "she", "they", "his", "her", "their", "and", "the", "to", "a", "an", "for", "is", "was", "on", "at", "by", "met",
        "lead", "prospect", "buyer", "looking", "tomorrow", "today", "tonight", "please", "with", "about", "who", "that",
        "loan", "purchase", "refinance", "refi", "hot", "cold", "warm", "zip", "it's", "he's", "she's", "they're",
    ] + HerbParse.weekdays)

    /// (abbreviation, tokens used) when a state name starts at token k.
    static func stateAt(_ toks: [(String, Int)], _ k: Int) -> (String, Int)? {
        guard k < toks.count else { return nil }
        let w = toks[k].0
        if stateAbbrs.contains(w) && w.pyIsUpper { return (w, 1) }
        if k + 1 < toks.count, let s = states["\(w) \(toks[k + 1].0)".lowercased()] { return (s, 2) }
        if let s = states[w.lowercased()] { return (s, 1) }
        return nil
    }

    struct Address {
        var address: String
        var city: String?
        var state: String?
        var zip: String?
        var span: (Int, Int)
    }

    /// "216 Shadow Creek Lane, Hickory Creek, Texas 76065" in any of its spoken forms.
    static func parseAddress(_ text: String, focus: Bool, homeState: String?) -> Address? {
        guard let m = addrRx.search(text) ?? (focus ? addrLoose.search(text) : nil) else { return nil }
        let streetText = rxSub(#"\s+"#, m[1]!, " ").strip(" ,").words.map { $0.pyIsAlpha ? cap($0) : $0 }.joined(separator: " ")
        var toks: [(String, Int)] = [], i = m.end
        while toks.count < 12, let mt = placeToken.match(text, from: i), mt.end > i {
            toks.append((mt[1]!, mt.end))
            i = mt.end
        }
        var (k, sep, end) = (0, false, m.end)
        while k < toks.count && [",", ";", "in"].contains(toks[k].0) { (sep, k) = (true, k + 1) }
        var cityWords: [String] = [], j = k
        while j < toks.count && cityWords.count < 3 {
            let w = toks[j].0
            guard let c0 = w.first, c0.isLetter, !cityStop.contains(w.lowercased()), stateAt(toks, j) == nil else { break }
            if !(c0.isUppercase || focus) { break }
            cityWords.append(w)
            j += 1
        }
        var city: String?, state: String?, zip: String?
        var jj = j < toks.count && toks[j].0 == "," ? j + 1 : j
        if !cityWords.isEmpty, case let s = stateAt(toks, jj), sep || s != nil {
            city = cityWords.map(cap).joined(separator: " ")
            end = toks[j - 1].1
            if let s { (state, end, jj) = (s.0, toks[jj + s.1 - 1].1, jj + s.1) }
        } else if cityWords.isEmpty, let s = stateAt(toks, k), sep {
            (state, end, jj) = (s.0, toks[k + s.1 - 1].1, k + s.1)
        }
        if state != nil || city != nil {
            let jz = jj < toks.count && toks[jj].0 == "," ? jj + 1 : jj
            if jz < toks.count, zipRx.match(toks[jz].0) != nil { (zip, end) = (toks[jz].0, toks[jz].1) }
        }
        if city != nil && state == nil { state = homeState }
        return Address(address: streetText, city: city, state: state, zip: zip, span: (m.start, end))
    }

    static func addrText(_ d: HerbFields) -> String {
        let tail = [d.text("state"), d.text("zip")].compactMap { $0 }.joined(separator: " ")
        return [d.text("address"), d.text("city"), tail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static let emailRx = Rx(#"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#)
    static let emailFull = Rx.full(#"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#)
    static let spokenEmail = Rx(#"\b([\w.+-]+(?:\s+(?:dot|underscore|dash)\s+[\w+-]+)*)\s+at\s+([\w-]+(?:\s+dot\s+[\w-]+)+)\b"#, true)

    static func spoken(_ s: String) -> String {
        rxSub(#"\s+(?:dash|hyphen)\s+"#, rxSub(#"\s+underscore\s+"#, rxSub(#"\s+dot\s+"#, s, "."), "_"), "-")
    }

    static func findEmail(_ t: String, focus: Bool) -> (String, (Int, Int))? {
        if let m = emailRx.search(t) { return (m[0]!.lowercased(), (m.start, m.end)) }
        if let m = spokenEmail.search(t) {
            let cand = "\(spoken(m[1]!))@\(spoken(m[2]!))".lowercased()
            if emailFull.match(cand) != nil { return (cand, (m.start, m.end)) }
        }
        if focus && rxTest(#"\sat\s"#, t) {
            let s = rxSub(#"^(?:the )?e-?mail(?: address)?(?: is)?\s+"#, leadIn(t.trimmed), "")
            let parts = Rx(#"\s+at\s+"#, true).split(spoken(s), maxSplit: 1)
            if parts.count == 2 {
                let cand = (parts[0].replacingOccurrences(of: " ", with: "") + "@" + (parts[1].words.first ?? "")).lowercased().strip(".,")
                if emailFull.match(cand) != nil { return (cand, (0, t.u16count)) }
            }
        }
        return nil
    }

    static func cut(_ t: String, _ span: (Int, Int)) -> String { t.u16(to: span.0) + " " + t.u16(from: span.1) }

    static let phoneKind = Rx(#"\b(cell|mobile|work|office|home)\b"#, true)

    /// Phone, email and address in any order; returns (fields, slots, the text with those removed).
    static func contact(_ t: String, focus: String?, homeState: String?) -> (HerbFields, Set<String>, String) {
        var data: HerbFields = [:], got = Set<String>(), t = t
        if let (ph, span) = HerbParse.phone(t) {
            let kind = phoneKind.search(t)?[1]?.lowercased()
            data["phone1"] = .string(ph)
            data["phone1Type"] = .string(kind.map { ["cell": "Mobile", "mobile": "Mobile", "work": "Work", "office": "Work", "home": "Home"][$0]! } ?? "Mobile")
            got.insert("phone")
            t = cut(t, span)
        }
        if let (em, span) = findEmail(t, focus: focus == "email") {
            data["email1"] = .string(em)
            got.insert("email")
            t = cut(t, span)
        }
        if let a = parseAddress(t, focus: focus == "address", homeState: homeState) {
            data["address"] = .string(a.address)
            if let c = a.city, !c.isEmpty { data["city"] = .string(c) }
            if let s = a.state, !s.isEmpty { data["state"] = .string(s) }
            if let z = a.zip { data["zip"] = .string(z) }
            got.insert("address")
            t = cut(t, a.span)
        }
        return (data, got, t)
    }

    static func numberAnswer(_ t: String) -> Double? {
        let t2 = HerbParse.wordsToDigits(t).replacingOccurrences(of: ",", with: "")
        if let a = HerbParse.amounts(t2).first { return a.value }
        return rxSearch(#"(\d+(?:\.\d+)?)"#, t2)?[1].flatMap(Double.init)
    }

    static let pastWeekday = Rx("\\b(?:last|on|this past)\\s+(" + HerbParse.weekdays.joined(separator: "|") + ")\\b")

    static func pastDate(_ t: String, now: Day) -> Day? {
        let tl = t.lowercased()
        if rxTest(#"\byesterday\b"#, tl, ci: false) { return now.adding(days: -1) }
        if let m = pastWeekday.search(tl) {
            let back = ((now.weekday - HerbParse.weekdays.firstIndex(of: m[1]!)!) % 7 + 7) % 7
            return now.adding(days: -(back == 0 ? 7 : back))
        }
        if let n = rxSearch(#"\b(\d+) days ago\b"#, HerbParse.wordsToDigits(tl), ci: false)?[1].flatMap(Int.init) {
            return now.adding(days: -n)
        }
        return nil
    }

    // MARK: Frames

    static let required = "required", recommended = "recommended", thorough = "thorough"
    static func levels(_ style: HerbQuestionStyle) -> Set<String> {
        switch style {
        case .quick: [required]
        case .balanced: [required, recommended]
        case .thorough: [required, recommended, thorough]
        }
    }
    static let offerA = ["address": "an address", "phone": "a phone number", "email": "an email address"]
    static let offerThe = ["address": "the address", "phone": "the phone number", "email": "the email address"]
    static let short = ["address": "Address", "phone": "Phone", "email": "Email"]
    static let slotPat = ["address": "address|street|lives", "phone": "phone|number|cell|mobile", "email": "e-?mail"]
    static let slotWords = slotPat.mapValues { Rx($0, true) }
    static let slotNeg = slotPat.mapValues {
        Rx("\\b(?:no|skip|without|not the|don'?t (?:need|want|have) (?:the|an?))\\s+(?:the\\s+|an?\\s+)?(?:\($0))", true)
    }
    static let learnable = ["address": "addresses", "phone": "phone numbers", "email": "email addresses",
                            "vendor": "the store name", "withWhom": "who a meal was with", "payer": "who paid",
                            "destination": "trip destinations", "purpose": "the business purpose",
                            "strength": "lead strength", "loan": "loan details"]
    static let intent: [String: HerbIntent] = ["prospects": .logProspect, "update": .updateProspect, "expenses": .logExpense,
                                               "activities": .logActivity, "income": .logIncome, "trips": .logTrip,
                                               "closings": .logClosing]
    static let peopleActs = ["relationship_building", "partner_coaching", "past_client", "current_client",
                             "prospective_client", "personal_visit", "socializing"]

    struct Slot: Sendable {
        let key: String
        let level: String
        let kind: String
        let group: String?
        let when: (@Sendable (HerbDialogState) -> Bool)?

        init(_ key: String, _ level: String, _ kind: String = "value", group: String? = nil,
             when: (@Sendable (HerbDialogState) -> Bool)? = nil) {
            self.key = key
            self.level = level
            self.kind = kind
            self.group = group
            self.when = when
        }

        func applies(_ st: HerbDialogState) -> Bool { when?(st) ?? true }
    }

    static let frames: [String: [Slot]] = [
        "prospects": [
            Slot("name", required),
            Slot("lastName", required, when: { $0.data.has("firstNames") && !$0.data.has("lastName") }),
            Slot("dup", required, "choice", when: { $0.meta.has("dupId") }),
            Slot("address", recommended, group: "contact"), Slot("phone", recommended, group: "contact"),
            Slot("email", thorough, group: "contact"),
            Slot("source", required),  // D3: always asked; "I don't know" records Unknown and flags it for review
            Slot("relation", recommended, "choice", when: { $0.meta.has("sourceNew") && $0.known.contains("source") }),
            Slot("followUp", recommended, "default"),
            Slot("strength", thorough, "choice"),
            Slot("loan", thorough),
        ],
        "update": [Slot("followUp", recommended, "default", when: { $0.meta.has("touched") })],
        "expenses": [Slot("amount", required), Slot("category", required, "choice"),
                     Slot("withWhom", recommended, when: { $0.meta.has("mealish") }),
                     Slot("vendor", recommended),
                     Slot("purpose", thorough, when: { $0.meta.has("meal") && $0.data.has("withWhom") })],
        "activities": [Slot("activity", required, "choice"), Slot("minutes", required),
                       Slot("withWhom", recommended, when: { st in
                           let a = st.data.str("activityId") ?? ""
                           return peopleActs.contains { a.contains($0) }
                       })],
        "income": [Slot("amount", required), Slot("type", required, "choice"), Slot("payer", recommended)],
        "trips": [Slot("miles", required), Slot("destination", recommended), Slot("reason", required, "choice")],
        "closings": [Slot("client", required), Slot("pick", required, "choice", when: { $0.meta.has("candidates") }),
                     Slot("size", required), Slot("income", required, "default")],
    ]

    static func isRequired(_ frame: String, _ key: String?) -> Bool {
        frames[frame]?.contains { $0.key == key && $0.level == required } ?? false
    }

    // MARK: Extraction tables

    static let sourceCue = Rx(#"referr|\bsent (?:him|her|them|me|over|by)\b|\bfrom\b|\bsource\b|came from|comes from|\bmet (?:him|her|them|at)\b|\bthrough\b|\bvia\b|open house|zillow|lead ?boost|website|online|facebook|instagram|door ?knock|cold call|seminar|past client|realtor|my (?:brother|sister|mom|dad|friend|neighbor|cousin)"#, true)
    static let followCue = Rx(#"follow[- ]?up|\bfollow\b|call (?:him|her|them|back)|check (?:back|in)|touch base|reach out|remind me|wants to (?:talk|meet|chat)|talk (?:on|again)|call on|meet on|make it|change it to|move it to|push it to|instead"#, true)
    static let strengthCue = Rx(#"red hot|\bhot\b|\bwarm\b|\bcold\b|no go|not interested|\bmedium\b"#, true)
    static let extraCategory: [(Rx, HerbTags)] = [
        (Rx("facebook|instagram|social media|tiktok|linkedin", true), HerbTags(.internet, "cat.website_free", "act.website_ad_set_up_free")),
        (Rx("google|online|internet|web lead", true), HerbTags(.internet, "cat.website_paid", "act.website_ad_set_up_paid")),
        (Rx("walk[- ]?in|came into the office|office visit", true), HerbTags(.prospecting, "cat.office_visits", "act.office_visits")),
    ]
    static let relation: [(Rx, HerbTags)] = [
        (Rx(#"family|brother|sister|\bmom\b|\bdad\b|cousin|uncle|aunt|in-law|\bson\b|daughter|wife|husband|relative"#, true),
         HerbTags(.personal, "cat.family", "act.relationship_building_personal")),
        (Rx("friend|neighbor|buddy", true), HerbTags(.personal, "cat.friend", "act.relationship_building_personal")),
        (Rx(#"\bagent\b|real estate|broker"#, true), HerbTags(.professional, "cat.realtor", "act.relationship_building_professional")),
        (Rx(#"lender|loan officer|banker|\bbank\b"#, true), HerbTags(.professional, "cat.banker", "act.relationship_building_professional")),
        (Rx("professional|business|colleague|co-?worker|vendor|partner", true),
         HerbTags(.professional, "cat.consultant", "act.relationship_building_professional")),
        (Rx("client|customer", true), HerbTags(.clients, "cat.past_client", "act.past_client_interaction")),
        (Rx("other|else|stranger|nobody|just met|don'?t know", true),
         HerbTags(.clients, "cat.prospective_client", "act.prospective_client_interaction")),
    ]
    static let tagFromActivity = ["act.open_houses", "act.seminar", "act.networking_open_group", "act.door_knocking"]

    static func keywordTags(_ t: String) -> HerbTags? {
        HerbParse.inferFromKeywords(t) ?? extraCategory.first { $0.0.test(t) }?.1
    }

    static func relationFrom(_ t: String) -> HerbTags? {
        HerbParse.inferFromKeywords(t) ?? relation.first { $0.0.test(t) }?.1
    }

    static func tagUpdate(_ tags: HerbTags) -> HerbFields {
        ["pillar": .string(tags.sub.pillar.rawValue), "subPillar": .string(tags.sub.rawValue),
         "categoryId": .string(tags.cat), "activityId": .string(tags.act)]
    }

    static let touch = Rx(#"\b(called|talked to|talked with|spoke (?:to|with)|texted|emailed|met with|left (?:a )?(?:message|voicemail|vm)(?: for| with)?|heard (?:back )?from)\b"#, true)
    static let touchVerb = [("call", "Called"), ("talk", "Talked"), ("spoke", "Talked"), ("text", "Texted"), ("email", "Emailed"),
                            ("met", "Met"), ("left", "Left a message"), ("heard", "Heard back")]

    static let expenseAnswers: [(Rx, String, String)] = ([
        (#"\bfood\b|restaurant|\beat\b"#, "relationships", "exp.relationships.meal"),
        (#"\bcar\b|oil change|tires?"#, "travel", "exp.travel.car_expenses"),
        (#"(?:online|facebook|google|web|internet).*(?:ad|marketing)|(?:ad|marketing).*(?:online|facebook|google|web)"#,
         "ad_internet", "exp.ad_internet.website_ad"),
        (#"marketing|advertis|\bads?\b|promo"#, "ad_traditional", "exp.ad_traditional.promotion_set_up"),
        ("education|seminar ticket|conference", "self_improvement", "exp.self_improvement.education"),
        ("donat", "general", "exp.general.donation"),
        ("photo", "general", "exp.general.photography"),
    ] as [(String, String, String)]).map { (Rx($0.0, true), $0.1, $0.2) }
    static let mealishCats = ["meal", "entertainment", "thank_you_gifts", "closing_gift"]
    static let vendorCue = Rx(#"\b(?:at|from)\s+[A-Z]|\bvendor\b|\bstore\b|\brestaurant\b|\bplace was\b"#, true)
    static let withCue = Rx(#"\bwith\b|\bfor (?:my |a )?(?:client|realtor|partner)"#, true)
    static let vendorRx = Rx(#"\b(?:at|from)\s+((?:[A-Z][\w'&\.]*|&)(?:\s+(?:[A-Z][\w'&\.]*|&|and|of))*)"#)
    static let purposeRx = Rx(#"(?:to discuss|discussed|talked about|talking about|went over|to talk about|about)\s+(.+)$"#, true)

    static let extraActivity: [(Rx, String)] = rxTable([
        ("meeting|met with|lunch|coffee|breakfast", "act.relationship_building_professional"),
        (#"phone calls?|calling|calls\b"#, "act.cold_calling"), ("social media", "act.facebook_marketing"),
        (#"follow[- ]?ups?|prospect"#, "act.prospective_client_interaction"),
        ("network", "act.networking_open_group"),
    ] as [(String, String)], ci: true)

    static func activityFrom(_ t: String) -> String? {
        HerbParse.inferActivity(t) ?? extraActivity.first { $0.0.test(t) }?.1
    }

    static let tripReasons: [(Rx, String)] = rxTable([
        ("closing", "Closing"), ("title", "Title Company"), ("open house", "Open Houses"),
        ("door ?knock", "Door Knocking"), ("seminar", "Seminar"), ("network|chamber|mixer", "Networking-Open Group"),
        ("realtor|agent|partner", "Relationship Building-Professional"),
        ("past client", "Past Client Interaction"), ("prospect|new client|lead", "Prospective Client Interaction"),
        ("client|meeting|appointment", "Current Client Interaction"), (#"\boffice\b"#, "Office"),
    ] as [(String, String)], ci: true)

    static func reasonFrom(_ t: String) -> String? {
        if let r = tripReasons.first(where: { $0.0.test(t) }) { return r.1 }
        guard let a = HerbParse.inferActivity(t), let name = Taxonomy.activityByID[a]?.name,
              Taxonomy.mileageReasons.contains(name) else { return nil }
        return name
    }

    static let missingLabel = [
        "name": "the name", "lastName": "the last name", "address": "the address", "phone": "the phone number",
        "email": "the email", "source": "the source", "relation": "who the source is", "followUp": "a follow-up date",
        "strength": "lead strength", "loan": "the loan", "amount": "the amount", "category": "the category",
        "withWhom": "who it was with", "vendor": "the vendor", "purpose": "the business purpose",
        "activity": "the activity", "minutes": "the time", "type": "the income type", "payer": "the payer",
        "miles": "the miles", "destination": "the destination", "reason": "the business purpose",
        "size": "the loan amount", "income": "what you earned", "client": "the client", "dup": "duplicate check",
    ]

    static let retryHint = [
        "phone": "I didn't catch a phone number — say it like 847 477 0619, or say skip.",
        "email": "I didn't catch an email — say it like tom at gmail dot com, or say skip.",
        "address": "I didn't catch an address — say the street number and name, like 216 Shadow Creek Lane.",
        "amount": "I didn't catch an amount — say it like 45 dollars.",
        "minutes": "How long — for example 30 minutes or 2 hours?",
        "miles": "How many miles — for example 14?",
        "size": "What was the loan amount — for example 520 thousand?",
        "income": "How much did you earn — for example 6,500?",
    ]
}

// MARK: Extractors

typealias HerbUpdate = (upd: HerbFields, got: Set<String>)

extension HerbSession {
    func sourceFrom(_ t: String, cur: HerbFields, focus: String?, first: Bool) -> HerbUpdate {
        typealias D = HerbDialog
        guard focus == "source" || first || D.sourceCue.test(t) else { return ([:], []) }
        if focus == "source" && (D.no.match(t) != nil || D.done.match(t) != nil || D.unknown.test(t)) {
            return ([:], [])  // the caller records it as Unknown
        }
        let exclude = HerbParse.tokens("\(cur.str("firstNames") ?? "") \(cur.str("lastName") ?? "")")
        var src = book.matchSource(t, exclude: exclude)
        if src?.name == D.unknownSource { src = nil }  // "unknown caller" is not the Unknown source
        var tags = src.flatMap { book.sourceProfile($0.id) }
        if let kw = D.keywordTags(t), tags == nil || (["cat.open_house", "cat.website_paid", "cat.door_knocking", "cat.seminar"].contains(kw.cat) && src == nil) {
            tags = kw
        }
        var name = src?.name
        if let tags, name == nil {
            if D.tagFromActivity.contains(tags.act) { name = book.latestSource(forActivity: tags.act) }
            else if rxTest("zillow", t) { name = "Zillow" }
            else if rxTest("lead ?boost", t) { name = "LeadBoost" }
        }
        if src == nil {
            let m = Rx("(?:referred by|referral from|sent (?:over )?by|came from|from|through|via)\\s+(\(HerbParse.person))").search(t)
                ?? Rx("\\b(\(HerbParse.person))\\s+(?:sent|referred)\\b").search(t)
            var new = m.flatMap { HerbParse.cleanPerson($0[1]!) }
            if let n = new, !Set(HerbParse.tokens(n)).isDisjoint(with: exclude) { new = nil }
            if new == nil && focus == "source" && tags == nil { new = D.bareName(t) }
            if let new { name = new }
        }
        if name == nil && tags == nil { return ([:], []) }
        var upd: HerbFields = name != nil || !cur.has("source") ? ["source": HerbValue(name)] : [:]
        var got: Set<String> = ["source"]
        upd["_sourceUnknown"] = false
        if let tags {
            upd.merge(D.tagUpdate(tags)) { $1 }
            upd["_sourceNew"] = false
            got.insert("relation")
        } else {
            upd["_sourceNew"] = true
        }
        return (upd, got)
    }

    func followFrom(_ t: String, loose: Bool) -> HerbUpdate {
        if rxTest(#"\bno follow[- ]?up\b|don'?t (?:need to )?follow|no need to follow"#, t) {
            return (["followUp": .null, "_followTime": .null], ["followUp"])
        }
        var seg: String
        if let m = HerbDialog.followCue.search(t) { seg = t.u16(from: m.start) }
        else if loose { seg = rxSub(#"\b(?:today|tonight|this (?:afternoon|evening|morning))\b"#, t, "") }
        else { return ([:], []) }
        seg = rxSub(#"\b(\w+day)['’]s\b"#, seg, "", ci: false)
        guard let d = HerbParse.parseWhen(seg, now: now) else { return ([:], []) }
        var upd: HerbFields = ["followUp": .string(d.iso)]
        if let tm = HerbParse.parseTime(seg) { upd["_followTime"] = .string(tm) }
        return (upd, ["followUp"])
    }

    func strengthFrom(_ t: String, focus: String?, first: Bool) -> HerbUpdate {
        guard focus == "strength" || HerbDialog.strengthCue.test(t) || (first && HerbParse.strengthFrom(t) != "medium") else { return ([:], []) }
        let warm = rxTest(#"\bwarm\b|\bmedium\b"#, t)
        let s = warm || rxTest("lukewarm", t) ? "medium" : HerbParse.strengthFrom(t)
        if focus == "strength" || s != "medium" || warm { return (["strength": .string(s)], ["strength"]) }
        return ([:], [])
    }

    func loanFrom(_ t: String, focus: String?, first: Bool) -> HerbUpdate {
        guard focus == "loan" || first || rxTest(#"loan|purchase|refi|\$|thousand|\bk\b"#, t) else { return ([:], []) }
        var upd: HerbFields = [:]
        if let v = HerbParse.amounts(t).map(\.value).max() {
            let approx = 100 <= v && v < 5000 ? v * 1000 : v
            if approx >= 20000 { upd["_loanAmount"] = .number(approx) }
        }
        if rxTest("refi|refinanc", t) { upd["_loanPurpose"] = "refinance" }
        else if rxTest(#"purchase|\bbuy"#, t) || upd["_loanAmount"] != nil { upd["_loanPurpose"] = "purchase" }
        return upd.isEmpty ? ([:], []) : (upd, ["loan"])
    }

    func notesFrom(_ t: String) -> HerbFields {
        var upd: HerbFields = [:]
        if let m = rxSearch(#"\b(?:add (?:a )?note|note)\b(?:\s+(?:to|for|on)\s+(?:him|her|them|it))?[:,]?\s+(?:that\s+)?(.+)$"#, t) {
            upd["_addNote"] = .string(m[1]!.trimmed.rstrip(".") + ".")
        }
        if let m = rxSearch(#"(move-?up buyer|first-?time (?:home )?buyer|investor|downsiz\w+|relocat\w+|va loan|fha)"#, t) {
            upd["_tag"] = .string(m[1]!)
        }
        return upd
    }

    func exProspect(_ st: HerbDialogState, _ t: String, focus: String?) -> HerbUpdate {
        let first = st.turns == 0
        var (upd, got, rest) = HerbDialog.contact(t, focus: focus, homeState: settings.homeState)
        if focus == "name" || focus == "lastName" || !st.known.contains("name") || rxTest(#"\b(?:first|last) name\b|\bspell"#, rest) {
            let n = HerbDialog.nameFrom(rest, focus: focus)
            if !n.isEmpty {
                upd.merge(n) { $1 }
                got.insert("name")
                if n.has("lastName") || (n.has("firstNames") && st.data.has("lastName")) { got.insert("lastName") }
            }
        }
        let cur = st.data.merging(upd) { $1 }
        for part in [sourceFrom(rest, cur: cur, focus: focus, first: first), followFrom(rest, loose: first || focus == "followUp"),
                     strengthFrom(rest, focus: focus, first: first), loanFrom(rest, focus: focus, first: first)] {
            upd.merge(part.upd) { $1 }
            got.formUnion(part.got)
        }
        if focus == "relation", let tags = HerbDialog.relationFrom(rest) {
            upd.merge(HerbDialog.tagUpdate(tags)) { $1 }
            upd["_sourceNew"] = false
            got.insert("relation")
        }
        if focus == "dup" {
            if rxTest(#"\bsame\b|\byes\b|that'?s (?:him|her|them)|existing|update|merge"#, rest) {
                upd["_dupAnswer"] = "same"
                got.insert("dup")
            } else if rxTest(#"\bnew\b|different|\bno\b|another|not the same"#, rest) {
                upd["_dupAnswer"] = "new"
                got.insert("dup")
            }
        }
        upd.merge(notesFrom(rest)) { $1 }
        return (upd, got)
    }

    func exUpdate(_ st: HerbDialogState, _ t: String, focus: String?) -> HerbUpdate {
        var (upd, got, rest) = HerbDialog.contact(t, focus: focus, homeState: settings.homeState)
        for part in [followFrom(rest, loose: focus == "followUp" || rxTest(#"\b(?:move|change|push|reschedule)\b"#, rest)),
                     strengthFrom(rest, focus: focus, first: false)] {
            upd.merge(part.upd) { $1 }
            got.formUnion(part.got)
        }
        upd.merge(notesFrom(rest)) { $1 }
        return (upd, got)
    }

    func classifyExpense(_ t: String, vendor: String?) -> (String, String)? {
        if HerbParse.meal.test(t) { return ("relationships", "exp.relationships.meal") }
        if let k = HerbParse.expenseKeywords.first(where: { $0.0.test(t) }) { return (k.1, k.2) }
        if let k = HerbDialog.expenseAnswers.first(where: { $0.0.test(t) }) { return (k.1, k.2) }
        if let vendor {
            var best: ExpenseRecord?
            for e in book.expenses where e.vendor.lowercased() == vendor.lowercased() {
                if best == nil || e.date > best!.date { best = e }
            }
            if let best { return (best.group.rawValue, best.categoryID) }
        }
        return nil
    }

    /// Distinct vendors, longest first (so "Office Depot" wins over "Office").
    var knownVendors: [String] {
        var seen = Set<String>(), out: [String] = []
        for e in book.expenses where !e.vendor.isEmpty && seen.insert(e.vendor).inserted { out.append(e.vendor) }
        return out.enumerated().sorted { ($0.element.count, $1.offset) > ($1.element.count, $0.offset) }.map(\.element)
    }

    func exExpense(_ st: HerbDialogState, _ t: String, focus: String?) -> HerbUpdate {
        typealias D = HerbDialog
        let first = st.turns == 0
        var upd: HerbFields = [:], got = Set<String>()
        if focus == "amount" || !st.known.contains("amount") || rxTest(#"\$|dollars?|bucks|make it|it was|total|amount"#, t) {
            let a = HerbParse.amounts(t)
            let explicit = a.filter(\.explicit)
            let pick = !explicit.isEmpty ? explicit : (focus == "amount" || !st.known.contains("amount") ? a : [])
            if let v = pick.first?.value ?? (focus == "amount" ? D.numberAnswer(t) : nil), v != 0 {
                upd["amount"] = .number(v)
                got.insert("amount")
            }
        }
        let short = t.words.count <= 3 && focus != "vendor" && focus != "purpose"
        let person = first || focus == "withWhom" || D.withCue.test(t) || short ? book.matchSource(t) : nil
        if let person, person.kind == "person" {
            upd.merge(["withWhom": .string(person.name), "source": .string(person.name), "_solo": false,
                       "_personId": .string(person.id)]) { $1 }
            got.insert("withWhom")
        } else if focus == "withWhom" {
            if D.solo.test(t) {
                upd.merge(["withWhom": .null, "source": .null, "_solo": true]) { $1 }
                got.insert("withWhom")
            } else if let n = D.bareName(t) {
                upd.merge(["withWhom": .string(n), "source": .string(n), "_solo": false]) { $1 }
                got.insert("withWhom")
            }
        }
        var vendor: String?
        if focus == "vendor" || !st.known.contains("vendor") || D.vendorCue.test(t) {
            let w = (upd.str("withWhom") ?? st.data.str("withWhom") ?? "").lowercased()
            if let m = D.vendorRx.search(t), !w.contains(m[1]!.lowercased()) { vendor = m[1]!.trimmed }
            if vendor == nil {
                let tl = t.lowercased()
                vendor = knownVendors.first { tl.contains($0.lowercased()) }
            }
            if vendor == nil && focus == "vendor" {
                vendor = D.bareName(rxSub(#"^(?:it was |we went )?(?:at|to)\s+"#, t, ""), maxWords: 4)
            }
            if let vendor {
                upd["vendor"] = .string(vendor)
                got.insert("vendor")
            }
        }
        if focus == "category" || !st.known.contains("category") || rxTest(#"\b(?:category|it was for|it'?s for|actually)\b"#, t),
           let c = classifyExpense(t, vendor: vendor ?? st.data.str("vendor")) {
            upd["groupId"] = .string(c.0)
            upd["categoryId"] = .string(c.1)
            got.insert("category")
            let mw = HerbParse.meal.search(t)?[0]?.lowercased()
            upd["_meal"] = HerbValue(mw ?? (c.1.hasSuffix(".meal") ? "meal" : nil))
        }
        let m = D.purposeRx.search(t)
        if focus == "purpose" && D.no.match(t) == nil && D.done.match(t) == nil {
            upd["purpose"] = .string((m?[1] ?? D.leadIn(t)).trimmed.rstrip("."))
            got.insert("purpose")
        } else if let m, upd.has("_meal") || st.meta.has("meal"), !rxTest(#"^[\d$]"#, m[1]!, ci: false) {
            upd["purpose"] = .string(m[1]!.trimmed.rstrip("."))
            got.insert("purpose")
        }
        if let pd = D.pastDate(t, now: now) { upd["date"] = .string(pd.iso) }
        return (upd, got)
    }

    func exActivity(_ st: HerbDialogState, _ t: String, focus: String?) -> HerbUpdate {
        typealias D = HerbDialog
        let first = st.turns == 0
        var upd: HerbFields = [:], got = Set<String>()
        let src = first || focus == "withWhom" || D.withCue.test(t) ? book.matchSource(t) : nil
        if focus == "activity" || !st.known.contains("activity") {
            var a = D.activityFrom(t)
            if a == nil, let src { a = book.sourceProfile(src.id)?.act }
            if let a, let meta = Taxonomy.activityByID[a] {
                upd.merge(["activityId": .string(a), "pillar": .string(meta.pillar.rawValue),
                           "subPillar": .string(meta.subPillar.rawValue)]) { $1 }
                got.insert("activity")
            }
        }
        var mins = HerbParse.durationMinutes(t)
        if mins == nil && focus == "minutes", let n = D.numberAnswer(t), n != 0 {
            mins = Int(max(15, pyRound((n <= 12 ? n * 60 : n) / 15) * 15))
        }
        if let mins {
            upd["minutes"] = .number(Double(mins))
            got.insert("minutes")
        }
        if let src, src.kind == "person" {
            upd["source"] = .string(src.name)
            got.insert("withWhom")
        } else if focus == "withWhom", let n = D.bareName(t) {
            upd["source"] = .string(n)
            got.insert("withWhom")
        }
        if let n = rxSearch(#"(\d+)\s+(?:new\s+)?(?:leads?|prospects?)"#, HerbParse.wordsToDigits(t.lowercased()), ci: false)?[1].flatMap(Int.init) {
            upd["_leads"] = .number(Double(n))
        }
        if let pd = D.pastDate(t, now: now) { upd["date"] = .string(pd.iso) }
        return (upd, got)
    }

    func exIncome(_ st: HerbDialogState, _ t: String, focus: String?) -> HerbUpdate {
        var upd: HerbFields = [:], got = Set<String>()
        if focus == "amount" || !st.known.contains("amount") || rxTest(#"\$|dollars?|bucks|make it"#, t) {
            let v = HerbParse.amounts(t).map(\.value).max() ?? (focus == "amount" ? HerbDialog.numberAnswer(t) : nil)
            if let v, v != 0 {
                upd["amount"] = .number(v)
                got.insert("amount")
            }
        }
        if let typ = HerbParse.incomeTypeWords.first(where: { $0.0.test(t) })?.1 {
            upd["type"] = .string(typ)
            got.insert("type")
        }
        let m = rxSearch(#"\bfrom\s+(.+?)(?:\s+for\b|[.,!?]|$)"#, t)
        if var payer = m?[1]?.trimmed ?? (focus == "payer" ? HerbDialog.bareName(t, maxWords: 4) : nil), !payer.isEmpty {
            payer = rxSub(#"^the\s+"#, payer, "")
            upd["payer"] = .string(payer.words.map { $0.pyIsUpper ? $0 : $0.upperFirst }.joined(separator: " "))
            got.insert("payer")
        }
        if let pd = HerbDialog.pastDate(t, now: now) { upd["date"] = .string(pd.iso) }
        return (upd, got)
    }

    func exTrip(_ st: HerbDialogState, _ t: String, focus: String?) -> HerbUpdate {
        typealias D = HerbDialog
        let first = st.turns == 0
        var upd: HerbFields = [:], got = Set<String>()
        let spoken = rxSearch(#"(\d+(?:\.\d+)?)\s*(?:miles?|mi)\b"#, HerbParse.wordsToDigits(t.lowercased()), ci: false)?[1].flatMap(Double.init)
        if let v = spoken ?? (focus == "miles" ? D.numberAnswer(t) : nil), v != 0 {
            upd["gpsMiles"] = .number(v)
            got.insert("miles")
        }
        var dest: String?
        if first || focus == "destination" || rxTest(#"\b(?:drove|went|destination|headed)\b"#, t) {
            dest = rxSearch(#"\b(?:to|at)\s+(?:the\s+)?(.+?)(?:\s+(?:and|for|about|it was|today|\d)|[.,!?]|$)"#, t, ci: false)?[1]?.trimmed
            if dest?.isEmpty ?? true, focus == "destination", D.no.match(t) == nil {
                dest = D.leadIn(rxSub(#"^(?:i )?(?:drove|went) (?:to )?"#, t, "")).trimmed
            }
            if let d = dest, !d.isEmpty {
                upd["destination"] = .string(d.words.map { $0.pyIsLower && !["of", "and", "the", "at"].contains($0) ? $0.pyCapitalize : $0 }
                    .joined(separator: " "))
                got.insert("destination")
            } else { dest = nil }
        }
        if let reason = D.reasonFrom(t) ?? dest.flatMap(D.reasonFrom), focus == "reason" || !st.known.contains("reason") {
            upd["reason"] = .string(reason)
            upd["activityId"] = HerbValue(Taxonomy.activities.first { $0.name == reason }?.id)
            got.insert("reason")
        }
        if let pd = D.pastDate(t, now: now) { upd["date"] = .string(pd.iso) }
        return (upd, got)
    }

    func exClosing(_ st: HerbDialogState, _ t: String, focus: String?) -> HerbUpdate {
        typealias D = HerbDialog
        var upd: HerbFields = [:], got = Set<String>()
        if focus == "client" || focus == "pick" || !st.known.contains("client") {
            var cands = book.prospectCandidates(t, firstNameOK: focus == "client" || focus == "pick")
            let ids = st.meta["candidates"]?.list?.compactMap { $0.object?["id"]?.string } ?? []
            if focus == "pick" && !ids.isEmpty {
                if let m = rxSearch(#"\b(first|second|third|1st|2nd|3rd|one|two|three)\b"#, t) {
                    let i = ["first": 0, "1st": 0, "one": 0, "second": 1, "2nd": 1, "two": 1, "third": 2, "3rd": 2, "three": 2][m[1]!.lowercased()]!
                    cands = i < ids.count ? book.prospects.filter { $0.id == ids[i] }.map { (9, $0) } : []
                } else {
                    cands = cands.filter { ids.contains($0.prospect.id) }
                }
            }
            let top = cands.filter { $0.score == cands.first?.score }
            if top.count > 1 && focus != "pick" && Set(top.map(\.prospect.id)).count > 1 {
                upd["_candidates"] = .list(top.prefix(3).map {
                    .object(["id": .string($0.prospect.id), "name": .string($0.prospect.fullName), "date": .string($0.prospect.date.iso)])
                })
                got.insert("client")
            } else if let p = top.first?.prospect {
                upd.merge(["prospectId": .string(p.id), "_name": .string(p.fullName), "_candidates": .null,
                           "_repeat": .bool(book.closedProspectIDs.contains(p.id))]) { $1 }
                got.formUnion(["client", "pick"])
            } else if focus == "client" || !st.known.contains("client") {
                if let n = HerbParse.findPersonName(t) ?? (focus == "client" ? D.bareName(t) : nil), n.words.count >= 2 {
                    let (f, l) = HerbParse.splitName(n)
                    upd.merge(["firstNames": .string(f), "lastName": .string(l), "_name": .string(n)]) { $1 }
                    got.insert("client")
                }
            }
        }
        var income: Double?, size: Double?
        if let m = rxSearch(#"(?:made|earned|comp(?:ensation)? (?:of|was)?|commission (?:of|was)?|income (?:of|was)?|i get|paid me)\s*\$?\s*([\d,\.]+\s*(?:k|thousand|grand)?)"#, t) {
            let g = m[1]!
            income = HerbParse.amounts(g + (rxTest("k|thousand|grand", g) ? "" : " dollars")).first?.value
        }
        for a in HerbParse.amounts(t).sorted(by: { $0.value > $1.value }) {
            if let income, abs(a.value - income) < 0.5 { continue }
            let val = 100 <= a.value && a.value < 5000 && !a.explicit ? a.value * 1000 : a.value
            if val >= 50000 && size == nil { size = val }
        }
        if focus == "size" && size == nil, let n = D.numberAnswer(t), n != 0 { size = n < 5000 ? n * 1000 : n }
        if focus == "income" && income == nil && size == nil, let n = D.numberAnswer(t), n != 0 { income = n < 100 ? n * 1000 : n }
        if let size, size != 0 {
            upd["transactionSize"] = .number(size)
            got.insert("size")
        }
        if let income, income != 0 {
            upd["income"] = .number(income)
            got.insert("income")
        }
        return (upd, got)
    }

    func extract(_ st: HerbDialogState, _ t: String, focus: String? = nil) -> HerbUpdate {
        switch st.frame {
        case "prospects": exProspect(st, t, focus: focus)
        case "update": exUpdate(st, t, focus: focus)
        case "expenses": exExpense(st, t, focus: focus)
        case "activities": exActivity(st, t, focus: focus)
        case "income": exIncome(st, t, focus: focus)
        case "trips": exTrip(st, t, focus: focus)
        default: exClosing(st, t, focus: focus)
        }
    }
}
