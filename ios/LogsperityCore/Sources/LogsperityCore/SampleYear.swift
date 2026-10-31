import Foundation

/// A deterministic synthetic year for "Load a sample year" and the tests (Swift port of herb-sim/seed.py).
///
/// Pilot user: Marcus Reed, independent mortgage broker, Denton TX. All people and companies are fictional.
/// The data is shaped so HERB's coaching rules have something real to say: past clients and professional
/// relationships convert best; paid web leads bring volume but rarely close; door knocking never closes;
/// open houses eat hours; LeadBoost is a zombie subscription; Jared Cole has drifted.
/// Dates are relative to `now`: last year's Q4 plus this year from Jan 2 to yesterday.
public struct SampleYear {
    public static let ownerName = "Marcus Reed"
    public static let company = "Reed Home Lending"
    public static let profession = "Lender"

    /// SplitMix64: small, fast and the same on every device.
    struct RNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func random() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(next() % UInt64(hi - lo + 1)) }
        mutating func uniform(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * random() }
        mutating func choice<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
        mutating func weighted<T>(_ a: [T], _ w: [Double]) -> T {
            var x = random() * w.reduce(0, +)
            for (i, v) in w.enumerated() { x -= v; if x < 0 { return a[i] } }
            return a.last!
        }
        mutating func gauss(_ mu: Double, _ sigma: Double) -> Double {
            let u1 = max(random(), 1e-12), u2 = random()
            return mu + sigma * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        mutating func shuffle<T>(_ a: inout [T]) {
            guard a.count > 1 else { return }
            for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(0, i)) }
        }
    }

    static let first = ["Aaron", "Abby", "Alan", "Amelia", "Ben", "Bianca", "Caleb", "Carmen", "Chris", "Dana", "Derek",
                        "Elena", "Ethan", "Faith", "Gabe", "Grace", "Hector", "Hannah", "Ian", "Isabel", "Jacob", "Jasmine",
                        "Kyle", "Kara", "Liam", "Lucia", "Mason", "Maya", "Nate", "Nina", "Owen", "Olivia", "Paul", "Paige",
                        "Raj", "Rosa", "Sam", "Sofia", "Trey", "Tessa", "Victor", "Wendy", "Xavier", "Yara", "Zach", "Zoe"]
    static let last = ["Adams", "Baker", "Bennett", "Brooks", "Castillo", "Chen", "Coleman", "Diaz", "Edwards", "Fischer",
                       "Flores", "Garcia", "Gupta", "Hayes", "Hughes", "Jensen", "Kim", "Lawson", "Lopez", "Mendez", "Mitchell",
                       "Nguyen", "Novak", "Owens", "Patel", "Perry", "Quinn", "Ramos", "Reyes", "Rivera", "Russell", "Sanders",
                       "Shaw", "Silva", "Stewart", "Sullivan", "Torres", "Turner", "Vargas", "Walsh", "Warren", "Watts", "Young"]
    static let pastClients = ["Greg Wallace", "Helen Ng", "Marco Bianchi", "Linda Foster", "Darnell Price", "Kate Murphy",
                              "Omar Haddad", "Janet Kwan", "Luis Medina", "Rachel Stone", "Peter Holm", "Tasha Greene",
                              "Victor Alvarado", "Wes Tanaka", "Erin Doyle"]
    static let restaurants = ["Cedar Grill", "Juniper Cafe", "Oak Street Bistro", "Sundance Coffee", "Square Burger Co."]
    static let lenders = ["Summit Wholesale Lending", "Bluebonnet Mortgage Wholesale", "Lone Star Wholesale"]
    static let destinations: [(String, String?)] = [
        ("Lakeside Realty", "act.relationship_building_professional"), ("North Star Realty", "act.relationship_building_professional"),
        ("Cedar & Main Realty", "act.relationship_building_professional"), ("Prairie Oak Realty", "act.relationship_building_professional"),
        ("Denton County Title", nil), ("Client home – Hickory St", "act.past_client_interaction"),
        ("Client home – Bell Ave", "act.current_client_interaction"), ("Okafor Insurance", "act.relationship_building_professional"),
        ("Hale & Co. CPAs", "act.relationship_building_professional"), ("Denton Chamber of Commerce", "act.networking_open_group"),
        ("Bank branch – University Dr", nil), ("Coffee meeting – Sundance Coffee", nil),
    ]
    struct Stream {
        let key: String, count: Int, closes: Int, sub: SubPillar, cat: String, act: String, sources: [String]?, kind: String
    }
    static let streams: [Stream] = [
        Stream(key: "past_client", count: 18, closes: 7, sub: .clients, cat: "cat.past_client", act: "act.past_client_interaction", sources: pastClients, kind: "person"),
        Stream(key: "current_client", count: 4, closes: 1, sub: .clients, cat: "cat.current_client", act: "act.current_client_interaction", sources: ["Linda Foster", "Omar Haddad"], kind: "person"),
        Stream(key: "dana", count: 14, closes: 5, sub: .professional, cat: "cat.realtor", act: "act.relationship_building_professional", sources: ["Dana Ruiz"], kind: "person"),
        Stream(key: "jared", count: 10, closes: 3, sub: .professional, cat: "cat.realtor", act: "act.relationship_building_professional", sources: ["Jared Cole"], kind: "person"),
        Stream(key: "ruth", count: 12, closes: 3, sub: .professional, cat: "cat.realtor", act: "act.relationship_building_professional", sources: ["Ruth Alvarez"], kind: "person"),
        Stream(key: "kim", count: 13, closes: 1, sub: .professional, cat: "cat.realtor", act: "act.relationship_building_professional", sources: ["Kim Tran"], kind: "person"),
        Stream(key: "brenda", count: 5, closes: 2, sub: .professional, cat: "cat.insurance_agent", act: "act.networking_closed_group", sources: ["Brenda Okafor"], kind: "person"),
        Stream(key: "tom", count: 4, closes: 1, sub: .professional, cat: "cat.accountant", act: "act.relationship_building_professional", sources: ["Tom Hale"], kind: "person"),
        Stream(key: "family", count: 6, closes: 2, sub: .personal, cat: "cat.family", act: "act.relationship_building_personal", sources: ["Mike Reed", "Sarah Lin", "Dave Ortiz"], kind: "person"),
        Stream(key: "church", count: 3, closes: 0, sub: .personal, cat: "cat.church", act: "act.community_involvement_personal", sources: ["Grace Community Church"], kind: "company"),
        Stream(key: "zillow", count: 22, closes: 1, sub: .internet, cat: "cat.website_paid", act: "act.website_ad_set_up_paid", sources: ["Zillow"], kind: "online"),
        Stream(key: "leadboost", count: 12, closes: 0, sub: .internet, cat: "cat.website_paid", act: "act.website_ad_set_up_paid", sources: ["LeadBoost"], kind: "online"),
        Stream(key: "website", count: 6, closes: 1, sub: .internet, cat: "cat.website_personal", act: "act.website_set_up", sources: ["reedhomelending.com"], kind: "online"),
        Stream(key: "mailer", count: 5, closes: 1, sub: .traditional, cat: "cat.mailer_farming", act: "act.mail_campaigning.advertising", sources: ["Hickory Creek farm mailer"], kind: "company"),
        Stream(key: "open_house", count: 16, closes: 1, sub: .prospecting, cat: "cat.open_house", act: "act.open_houses", sources: nil, kind: "venue"),
        Stream(key: "door", count: 5, closes: 0, sub: .prospecting, cat: "cat.door_knocking", act: "act.door_knocking", sources: ["Savannah neighborhood"], kind: "venue"),
        Stream(key: "seminar", count: 8, closes: 2, sub: .prospecting, cat: "cat.seminar", act: "act.seminar", sources: ["First-Time Buyer Seminar"], kind: "venue"),
        Stream(key: "chamber", count: 5, closes: 1, sub: .prospecting, cat: "cat.network_open_group", act: "act.networking_open_group", sources: ["Denton Chamber mixer"], kind: "company"),
    ]
    static let openHouseAddresses = ["2201 Bonnie Brae", "418 Pecan Ln", "1702 Emerson Ct", "93 Hilltop Dr", "3310 Teasley Ln",
                                     "750 Mockingbird Ln", "1215 Egan St", "88 Lakeview Blvd", "605 Fulton St", "2904 Wind River Ln",
                                     "141 Oak Hollow", "3721 Sandpiper Dr", "910 Locust St", "2650 Mesa Ct", "47 Live Oak Ct",
                                     "1980 Cedar Bend", "5122 Cypress Way", "77 Elm Park"]

    let now: Day
    let yesterday: Day
    var r = RNG(state: 42)
    var usedNames = Set<String>()
    var sourceIDs: [String: RecordID] = [:]
    var odometer = 41_250.0
    var vacationMondays: Set<Day> = []
    public private(set) var book = LogBook()

    /// Builds the sample year ending yesterday.
    public static func build(now: Day) -> LogBook {
        var s = SampleYear(now: now)
        s.run()
        return s.book
    }

    init(now: Day) {
        self.now = now
        yesterday = now.adding(days: -1)
        vacationMondays = Set([Day(now.year, 3, 16), Day(now.year, 7, 6), Day(now.year, 8, 24)].map(Self.monday))
    }

    static func monday(_ d: Day) -> Day { d.adding(days: -d.weekday) }
    static func days(_ a: Day, _ b: Day) -> [Day] { a > b ? [] : (0...a.days(to: b)).map { a.adding(days: $0) } }
    func isVacation(_ d: Day) -> Bool { vacationMondays.contains(Self.monday(d)) }
    func businessDays(_ a: Day, _ b: Day) -> [Day] { Self.days(a, b).filter { $0.weekday < 5 && !isVacation($0) } }

    mutating func source(_ name: String, _ kind: String = "person") -> RecordID {
        if let id = sourceIDs[name] { return id }
        let s = SourceRecord(name: name, kind: kind)
        book.sources.append(s)
        sourceIDs[name] = s.id
        return s.id
    }

    mutating func person() -> (String, String) {
        while true {
            let f = r.choice(Self.first), l = r.choice(Self.last)
            if usedNames.insert("\(f) \(l)").inserted { return (f, l) }
        }
    }

    // MARK: Prospects and closings

    mutating func streamDates(_ key: String, _ n: Int, _ a: Day, _ b: Day) -> [Day] {
        var days = businessDays(a, b)
        if key == "jared" { days = days.filter { $0 <= now.adding(days: -42) } }  // Jared Cole drifts
        if key == "open_house" {
            let sats = Self.days(a, b).filter { $0.weekday == 5 && !isVacation($0) }
            guard !sats.isEmpty else { return [] }
            let step = max(1, sats.count / n)
            return (0..<n).map { sats[min(sats.count - 1, $0 * step + 1)] }
        }
        guard !days.isEmpty else { return [] }
        return (0..<n).map { _ in r.choice(days) }.sorted()
    }

    mutating func buildProspects(_ a: Day, _ b: Day, scale: Double = 1) {
        var made: [(key: String, closes: Int, ids: [(RecordID, Day)])] = []
        for st in Self.streams {
            let n = max(1, Int((Double(st.count) * scale).rounded()))
            let k = Int((Double(st.closes) * scale).rounded())
            var ids: [(RecordID, Day)] = []
            for (i, d) in streamDates(st.key, n, a, b).enumerated() {
                let (f, l) = person()
                let sname = st.key == "open_house" ? "Open house – \(Self.openHouseAddresses[i % Self.openHouseAddresses.count])"
                    : r.choice(st.sources!)
                let sid = source(sname, st.kind)
                var p = newProspect(d, f, l, st.sub, st.cat, st.act, sid)
                p.strength = r.weighted(Strength.allCases, [5, 20, 40, 25, 10])
                book.prospects.append(p)
                ids.append((p.id, d))
            }
            made.append((st.key, k, ids))
        }
        // the earliest eligible prospects of each stream close 30–75 days later
        for (key, k, ids) in made {
            var eligible = ids.filter { $0.1 <= yesterday.adding(days: -35) }
            r.shuffle(&eligible)
            var done = 0
            for (pid, d) in eligible where done < k {
                let cd = d.adding(days: r.int(30, 75))
                if cd > yesterday || (key == "jared" && cd > now.adding(days: -42)) { continue }  // Jared has gone quiet
                addClosing(pid, cd, key)
                done += 1
            }
        }
    }

    mutating func newProspect(_ d: Day, _ first: String, _ last: String, _ sub: SubPillar, _ cat: String, _ act: String,
                              _ sourceID: RecordID) -> ProspectRecord {
        var p = ProspectRecord(date: d)
        p.firstNames = first
        p.lastName = last
        p.phone1 = String(format: "(940) 555-%04d", r.int(100, 9999))
        p.phone1Type = "Mobile"
        p.email1 = "\(first.lowercased().replacingOccurrences(of: " ", with: "")).\(last.lowercased())@example.com"
        p.zip = "76201"; p.city = "Denton"; p.state = "TX"
        p.attribution = Attribution(pillar: sub.pillar, subPillar: sub, categoryID: cat, activityID: act, sourceID: sourceID)
        p.planOfAction = r.choice(["Call", "Email", "Add to Database", "Call", "Visit"])
        p.followUp = d >= now.adding(days: -30) ? now.adding(days: r.int(2, 20)) : d.adding(days: r.choice(Array(Taxonomy.followUpDays.prefix(6))))
        return p
    }

    mutating func addClosing(_ pid: RecordID, _ d: Day, _ key: String) {
        let pi = book.prospects.firstIndex { $0.id == pid }!
        let p = book.prospects[pi]
        let base = 380_000.0 + (p.attribution.subPillar == .professional ? 40_000 : 0) + (key == "seminar" ? 25_000 : 0)
        let size = (min(650_000, max(210_000, r.gauss(base, 70_000))) / 1000).rounded() * 1000
        let income = (size * r.uniform(0.0112, 0.0145)).rounded()
        book.prospects[pi].strength = .hot
        var c = LogRules.closing(from: p, date: d, transactionSize: size, income: income)
        c.referralRequest = d.days(to: now) < 20 ? .ask14 : r.choice([.yes, .yes, .ask14, .ask30, .no])
        c.postClosingFollowUp = d.adding(days: 180)
        book.closings.append(c)
        var inc = LogRules.incomeRows(for: c, lastName: p.lastName, addToIncome: true)[0]
        inc.type = .commission
        inc.payer = r.choice(Self.lenders)
        book.income.append(inc)
        var gift = ExpenseRecord(date: d)
        gift.vendor = "Denton Gift Co."
        gift.amount = (r.uniform(75, 150) * 100).rounded() / 100
        gift.group = .clients
        gift.categoryID = "exp.clients.closing_gift"
        gift.sourceID = p.attribution.sourceID
        gift.cardLast4 = "4417"
        gift.purpose = "Closing gift – \(p.fullName)"
        gift.hasReceipt = true
        book.expenses.append(gift)
    }

    mutating func storyProspects() {
        let n = now
        func add(_ daysAgo: Int, _ f: String, _ l: String, _ sub: SubPillar, _ cat: String, _ act: String, _ src: String,
                 _ kind: String, _ strength: Strength, followUp: Int, plan: String, notes: String, voice: Bool = false) {
            var p = newProspect(n.adding(days: -daysAgo), f, l, sub, cat, act, source(src, kind))
            p.strength = strength
            p.followUp = n.adding(days: followUp)
            p.planOfAction = plan
            p.notes = notes
            if voice { p.capture = .voice; p.reviewed = false }
            book.prospects.append(p)
        }
        let rbp = "act.relationship_building_professional"
        add(20, "Priya", "Shah", .professional, "cat.realtor", rbp, "Dana Ruiz", "person", .redHot, followUp: -2, plan: "Call",
            notes: "Pre-approval expires \(Format.shortDate(n.adding(days: 3))). Last contact \(Format.shortDate(n.adding(days: -11))) (text).")
        add(6, "Lena", "Ortiz", .prospecting, "cat.open_house", "act.open_houses", "Open house – 2201 Bonnie Brae", "venue", .hot,
            followUp: -5, plan: "Call", notes: "Met at Saturday's open house — not called yet.")
        add(12, "Tom & Ana", "Becker", .clients, "cat.past_client", "act.past_client_interaction", "Greg Wallace", "person", .redHot,
            followUp: 0, plan: "Call", notes: "Rate-lock decision call at 2:00 PM.")
        add(3, "Kevin", "Morales", .professional, "cat.realtor", rbp, "Ruth Alvarez", "person", .hot, followUp: 0, plan: "Call",
            notes: "Move-up buyer, about $520,000. Wants to talk after 5.")
        add(9, "Marisol", "Vega", .clients, "cat.past_client", "act.past_client_interaction", "Helen Ng", "person", .hot,
            followUp: -1, plan: "Email", notes: "Refinance question — sent docs list.")
        add(15, "Derrick", "Hall", .internet, "cat.website_paid", "act.website_ad_set_up_paid", "Zillow", "online", .medium,
            followUp: 1, plan: "Call", notes: "Zillow lead; slow to respond.")
        add(1, "Alicia", "Gomez", .professional, "cat.realtor", rbp, "Kim Tran", "person", .medium, followUp: 4, plan: "Call",
            notes: "Said by voice: met at Prairie Oak office; buying in spring.", voice: true)
    }

    // MARK: Activity, trips, expenses, income

    mutating func activity(_ d: Day, _ act: String, _ minutes: Int, _ src: String?, kind: String = "person",
                           capture: Capture = .manual, reviewed: Bool = true, notes: String? = nil) {
        let meta = Taxonomy.activityByID[act]!
        var a = ActivityRecord(date: d)
        a.attribution = Attribution(pillar: meta.pillar, subPillar: meta.subPillar, activityID: act,
                                    sourceID: src.map { source($0, kind) })
        a.minutes = minutes
        a.capture = capture
        a.reviewed = reviewed
        a.notes = notes
        book.activities.append(a)
    }

    mutating func buildActivities(_ a: Day, _ b: Day, jaredCutoff: Day) {
        let realtors = ["Dana Ruiz", "Ruth Alvarez", "Kim Tran", "Jared Cole"]
        for d in Self.days(a, b) where !isVacation(d) {
            let wd = d.weekday
            let oddWeek = (d.ordinal / 7) % 2 == 1
            var acts: [(String, Int, String?)] = []
            if wd == 1 { acts.append(("act.past_client_interaction", r.choice([60, 75, 90]), r.choice(Self.pastClients))) }
            if wd == 3 { acts.append(("act.past_client_interaction", 30, r.choice(Self.pastClients))) }
            if wd == 0 && d.day <= 7 { acts.append(("act.database_marketing", 60, nil)) }
            if wd == 1 || wd == 3 {
                acts.append(("act.relationship_building_professional", r.choice([45, 60, 75]),
                             r.choice(realtors.filter { $0 != "Jared Cole" || d < jaredCutoff })))
            }
            if wd == 2 { acts.append(("act.networking_closed_group", 60, d.day <= 7 ? "Brenda Okafor" : nil)) }
            if wd == 4 && !oddWeek { acts.append(("act.partner_coaching", 45, r.choice(["Dana Ruiz", "Ruth Alvarez"]))) }
            if wd == 4 && oddWeek { acts.append(("act.socializing", 45, nil)) }
            if wd == 0 { acts.append(("act.website_ad_set_up_paid", 30, r.choice(["Zillow", "LeadBoost"]))) }
            if wd == 0 && (8...14).contains(d.day) { acts.append(("act.website_set_up", 60, "reedhomelending.com")) }
            if [2, 5, 8, 11].contains(d.month) && d.day == 3 && wd < 5 {
                acts.append(("act.mail_campaigning.advertising", 90, "Hickory Creek farm mailer"))
            }
            if d.day == 15 && wd < 5 { acts.append(("act.relationship_building_professional", 45, "Tom Hale")) }
            if wd == 4 && [5, 6, 7, 19, 20, 21].contains(d.day) && [3, 4, 9, 10].contains(d.month) {
                acts.append(("act.cold_calling", 30, nil))
            }
            for (act, minutes, src) in acts {
                let online = ["Zillow", "LeadBoost", "reedhomelending.com"].contains(src ?? "")
                activity(d, act, minutes, src, kind: online ? "online" : "person", capture: d.month >= 9 ? .calendar : .manual)
            }
        }
    }

    /// Open houses, door knocking, seminars, chamber mixers: time-heavy prospecting.
    mutating func buildEvents(_ a: Day, _ b: Day) {
        let all = Self.days(a, b)
        let sats = all.filter { $0.weekday == 5 && !isVacation($0) }
        let odd = stride(from: 1, to: sats.count, by: 2).map { sats[$0] }
        let ohDays = sats.count > 30 ? Array(odd.prefix(20)) : odd
        for (i, d) in ohDays.enumerated() {
            let addr = Self.openHouseAddresses[i % Self.openHouseAddresses.count]
            event(d, "act.open_houses", 210, "Open house – \(addr)", "venue")
            trip(d, "Open Houses", addr, r.uniform(6, 18), "act.open_houses")
            expense(d, "FedEx Office", 38.50, .prospecting, "exp.prospecting.leave_behind_material", purpose: "Open house flyers")
        }
        let thursdays = all.filter { $0.weekday == 3 && !isVacation($0) }
        for d in stride(from: 3, to: thursdays.count, by: 9).map({ thursdays[$0] }).prefix(5) {
            event(d, "act.door_knocking", 120, "Savannah neighborhood", "venue")
            trip(d, "Door Knocking", "Savannah neighborhood", r.uniform(8, 14), "act.door_knocking")
        }
        let tuesdays = all.filter { $0.weekday == 1 && !isVacation($0) }
        for d in stride(from: 5, to: tuesdays.count, by: 10).map({ tuesdays[$0] }).prefix(4) {
            event(d, "act.seminar", 150, "First-Time Buyer Seminar", "venue")
            event(d.adding(days: -1), "act.seminar", 60, "First-Time Buyer Seminar", "venue")
            expense(d, "Denton Public Library", 160, .prospecting, "exp.prospecting.seminar_production", purpose: "Seminar room and handouts")
        }
        let wednesdays = all.filter { $0.weekday == 2 && !isVacation($0) }
        for d in stride(from: 2, to: wednesdays.count, by: 8).map({ wednesdays[$0] }).prefix(5) {
            event(d, "act.networking_open_group", 90, "Denton Chamber mixer", "company")
        }
    }

    mutating func event(_ d: Day, _ act: String, _ minutes: Int, _ src: String, _ kind: String) {
        if d > yesterday { return }
        activity(d, act, minutes, src, kind: kind)
    }

    mutating func trip(_ d: Day, _ reason: String, _ dest: String, _ miles: Double, _ act: String? = nil, business: Bool = true,
                       capture: Capture? = nil, reviewed: Bool = true) {
        if d > yesterday && reviewed { return }
        let miles = (miles * 10).rounded() / 10
        let gps = d >= Day(now.year, 9, 1)
        let start = odometer
        odometer += miles
        var t = TripRecord(date: d)
        t.reason = reason
        t.destination = dest
        if gps { t.gpsMiles = miles } else {
            t.odometerStart = (start * 10).rounded() / 10
            t.odometerEnd = (odometer * 10).rounded() / 10
        }
        t.isBusiness = business
        t.activityID = act
        t.capture = capture ?? (gps ? .gps : .manual)
        t.reviewed = reviewed
        book.trips.append(t)
    }

    mutating func buildTrips(_ a: Day, _ b: Day) {
        for d in businessDays(a, b) {
            for _ in 0..<r.choice([1, 2, 2, 2, 3, 3]) {
                let (dest, act) = r.choice(Self.destinations)
                let reason = act.flatMap { Taxonomy.activityByID[$0]?.name } ?? r.choice(["Closing", "Title Company", "Office"])
                let business = r.random() > 0.07
                trip(d, business ? reason : "Personal errand", dest, r.uniform(7, 42), act, business: business)
            }
        }
    }

    mutating func expense(_ d: Day, _ vendor: String, _ amount: Double, _ group: ExpenseGroup, _ cat: String,
                          source src: String? = nil, purpose: String? = nil, withWhom: String? = nil, receipt: Bool = true,
                          capture: Capture = .manual, reviewed: Bool = true) {
        if d > yesterday && reviewed { return }
        var e = ExpenseRecord(date: d)
        e.vendor = vendor
        e.amount = (amount * 100).rounded() / 100
        e.group = group
        e.relationshipSubPillar = group == .relationships ? .professional : nil
        e.categoryID = cat
        e.sourceID = src.map { source($0) }
        e.cardLast4 = "4417"
        e.purpose = purpose
        e.withWhom = withWhom
        e.hasReceipt = receipt
        e.capture = capture
        e.reviewed = reviewed
        book.expenses.append(e)
    }

    mutating func buildExpenses(_ a: Day, _ b: Day) {
        let firstNew = book.expenses.count
        var m = a.startOfMonth
        while m <= b {
            func on(_ day: Int) -> Day { Day(m.year, m.month, min(day, 28)) }
            expense(on(3), "LeadBoost", 95, .adInternet, "exp.ad_internet.website_ad", source: "LeadBoost",
                    purpose: "Monthly lead subscription", capture: m.month >= 6 ? .bank : .manual)
            expense(on(10), "Zillow Premier Agent", 250, .adInternet, "exp.ad_internet.website_ad", source: "Zillow", purpose: "Zillow lead program")
            expense(on(5), "HostPilot", 24, .adInternet, "exp.ad_internet.web_hosting", purpose: "Website hosting")
            expense(on(18), "Verizon", 92, .general, "exp.general.phone", purpose: "Mobile phone (business share)")
            expense(on(1), "LoanPilot CRM", 59, .technology, "exp.technology.software", purpose: "CRM")
            expense(on(7), "Prosperity Simplified", 149, .selfImprovement, "exp.self_improvement.coaching_fees", purpose: "Business coaching")
            for _ in 0..<3 {
                let day = r.int(2, 27)
                let realtor = r.choice(["Dana Ruiz", "Ruth Alvarez", "Kim Tran"] + (on(day) < now.adding(days: -42) ? ["Jared Cole"] : []))
                expense(on(day), r.choice(Self.restaurants), r.uniform(24, 96), .relationships, "exp.relationships.meal",
                        source: realtor, purpose: "Referral pipeline review", withWhom: realtor)
            }
            if m.month % 3 == 1 {
                expense(on(r.int(5, 25)), "Office Depot", r.uniform(55, 140), .general, "exp.general.office_supplies", purpose: "Office supplies")
            }
            if [2, 5, 8, 11].contains(m.month) {
                expense(on(2), "PrintHub Direct", 420, .adTraditional, "exp.ad_traditional.mailers", source: "Hickory Creek farm mailer",
                        purpose: "Farm mailer – 600 homes")
            }
            m = m.month == 12 ? Day(m.year + 1, 1, 1) : Day(m.year, m.month + 1, 1)
        }
        if a.year == now.year {
            let y = now.year
            let fixed: [(Day, String, Double, ExpenseGroup, String, String?, String)] = [
                (Day(y, 1, 12), "NMLS", 330, .general, "exp.general.license", nil, "License renewal"),
                (Day(y, 1, 20), "Denton Chamber of Commerce", 425, .relationships, "exp.relationships.networking_dues", "Denton Chamber mixer", "Annual dues"),
                (Day(y, 2, 3), "Shield E&O", 940, .general, "exp.general.insurance", nil, "E&O insurance"),
                (Day(y, 3, 20), "Hale & Co. CPAs", 650, .general, "exp.general.tax_preparation", "Tom Hale", "\(y - 1) tax return"),
                (Day(y, 4, 14), "MortgageEd Online", 249, .selfImprovement, "exp.self_improvement.training", nil, "NMLS continuing education"),
                (Day(y, 6, 13), "Lakeview Pavilion", 1250, .clients, "exp.clients.client_appreciation_party", nil, "Client appreciation party"),
                (Day(y, 9, 9), "Canva", 119.99, .technology, "exp.technology.software", nil, "Design software (annual)"),
            ]
            for f in fixed { expense(f.0, f.1, f.2, f.3, f.4, source: f.5, purpose: f.6) }
        }
        // some $75+ expenses missing receipts (substantiation alerts)
        var big = (firstNew..<book.expenses.count).filter {
            book.expenses[$0].amount >= 75 && !["LeadBoost", "Zillow Premier Agent"].contains(book.expenses[$0].vendor)
        }
        r.shuffle(&big)
        for i in big.prefix(5) { book.expenses[i].hasReceipt = false }
    }

    mutating func buildIncome() {
        let y = now.year
        let rows: [(Day, IncomeMode, IncomeType, Double, Int?, String, String)] = [
            (Day(y, 3, 18), .type, .consultingFees, 1500, nil, "Denton Builders Assoc.", "Builder financing workshop"),
            (Day(y, 7, 15), .type, .bonuses, 2000, nil, "Summit Wholesale Lending", "Volume bonus Q2"),
            (Day(y, 8, 21), .type, .consultingFees, 1500, nil, "Denton Builders Assoc.", "Builder financing workshop"),
            (Day(y, 9, 30), .batch, .commission, 3100, 2, "Bluebonnet Mortgage Wholesale", "Two small refinances paid together"),
        ]
        for row in rows where row.0 <= yesterday {
            var i = IncomeRecord(date: row.0)
            i.mode = row.1; i.type = row.2; i.amount = row.3; i.transactionCount = row.4; i.payer = row.5; i.notes = row.6
            book.income.append(i)
        }
    }

    /// About eight auto-captured items from the last two days, waiting for the one-minute review.
    mutating func buildReviewItems() {
        let y = now.adding(days: -1), y2 = now.adding(days: -2)
        trip(y, "Relationship Building-Professional", "Lakeside Realty", 12.4, "act.relationship_building_professional", capture: .gps, reviewed: false)
        trip(y, "Relationship Building-Professional", "Cedar Grill", 3.1, nil, capture: .gps, reviewed: false)
        trip(y2, "Open Houses", "2201 Bonnie Brae", 6.1, "act.open_houses", capture: .gps, reviewed: false)
        expense(y, "Cedar Grill", 86.40, .relationships, "exp.relationships.meal", source: "Dana Ruiz", purpose: "Q4 referral pipeline review",
                withWhom: "Dana Ruiz", receipt: false, capture: .bank, reviewed: false)
        expense(y2, "Office Depot", 43.17, .general, "exp.general.office_supplies", purpose: "Printer paper, folders", capture: .receipt, reviewed: false)
        activity(y, "act.relationship_building_professional", 75, "Dana Ruiz", capture: .calendar, reviewed: false, notes: "Calendar: Lunch – Dana Ruiz")
        activity(y2, "act.networking_open_group", 90, "Denton Chamber mixer", capture: .calendar, reviewed: false, notes: "Calendar: Chamber mixer")
    }

    mutating func run() {
        let y = now.year
        let jaredCutoff = now.adding(days: -41)
        // last year's Q4 (for "same period last year" and past-client sources)
        let h0 = Day(y - 1, 10, 1), h1 = Day(y - 1, 12, 31)
        buildProspects(h0, h1, scale: 0.2)
        buildActivities(h0, h1, jaredCutoff: jaredCutoff)
        buildTrips(h0, h1)
        buildExpenses(h0, h1)
        // this year to yesterday
        let a = Day(y, 1, 2), b = yesterday
        buildProspects(a, b)
        storyProspects()
        buildActivities(a, b, jaredCutoff: jaredCutoff)
        buildEvents(a, b)
        buildTrips(a, b)
        buildExpenses(a, b)
        buildIncome()
        buildReviewItems()
        book.plans[y] = PlanInputs(grossIncomeGoal: 180_000, netProfitGoal: 150_000, avgCommission: 5_500,
                                   avgTransactionSize: 380_000, hoursPerWeek: 45, vacationWeeks: 3)
        book.plans[y - 1] = PlanInputs(grossIncomeGoal: 160_000, netProfitGoal: 132_000, avgCommission: 5_200,
                                       avgTransactionSize: 360_000, hoursPerWeek: 45, vacationWeeks: 3)
    }
}
