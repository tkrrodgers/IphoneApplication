import Foundation

// HERB's answers to questions (design §16–§17.1): focus, follow-ups, pace, conversion, sources that never close,
// efficiency, ROI, the Logsperity Index, top sources, summaries, reports, the plan, the Review queue, and the
// entry point for anything to log. Every number comes from the Ledger, Coach or PlanTracking. Port of herb.py.

extension HerbSession {
    static let logFrames: [HerbIntent: String] = [.logProspect: "prospects", .logClosing: "closings",
                                                   .logIncome: "income", .logActivity: "activities"]

    var coach: Coach { Coach(book, now: now) }
    var ytd: Ledger? { try? Ledger(book, periodKey: "ytd", now: now) }
    var firstName: String { settings.ownerFirstName?.words.first ?? "there" }

    /// A fresh request (no follow-up pending).
    mutating func route(_ t: String) -> HerbReply {
        if t.isEmpty { return HerbReply(.smalltalk, "Hi \(firstName). What can I do for you?", followUp: true) }
        if let p = matchUpdate(t) { return startUpdate(p, t) }
        let intent = HerbParse.detectIntent(t)
        if let log = Self.logFrames[intent] { return start(log, t) }
        switch intent {
        case .logExpense: return logExpense(t)
        case .logTrip: return logTrip(t)
        case .focus: return focusReply()
        case .followUps: return followUpsReply()
        case .pace: return paceReply()
        case .conversion: return conversionReply()
        case .sourcesNoClose: return sourcesNoCloseReply()
        case .efficiency: return efficiencyReply()
        case .roi: return roiReply()
        case .index: return indexReply()
        case .topSources: return topSourcesReply(t)
        case .incomeSummary: return incomeSummaryReply()
        case .expensesSummary: return expensesSummaryReply()
        case .mileageSummary: return mileageSummaryReply()
        case .review: return reviewReply()
        case .report: return reportReply(t)
        case .plan: return planReply()
        case .help: return helpReply()
        case .smalltalk: return smalltalkReply(t)
        default: return unknownReply()
        }
    }

    /// Python's "never crash the voice loop".
    func snag(_ intent: HerbIntent, _ why: String) -> HerbReply {
        HerbReply(intent, "Sorry, I hit a snag working that out. Try saying it another way.", display: "Error: \(why)")
    }

    // MARK: Logging special cases (extraction and questions for every log live in HerbDialog.swift)

    mutating func logExpense(_ t: String) -> HerbReply {
        if rxTest(#"scan (?:a |my )?receipt|take a picture|photo of (?:a |my |the )?receipt"#, t) {
            return HerbReply(.logExpense, "Opening the receipt scanner. Hold the receipt flat and I'll read it.",
                             actions: [HerbAction("Scan receipt", .open(.receiptScanner))])
        }
        return start("expenses", t)
    }

    /// Trips: the app runs the GPS tracker (`HerbTripCommand`) and passes the trip in progress back as `activeTrip`.
    mutating func logTrip(_ t: String) -> HerbReply {
        let tl = t.lowercased()
        if rxTest(#"start (?:a |my )?(?:business )?trip|driving to"#, tl, ci: false) {
            let dest = rxSearch(#"\bto\s+(.+?)(?:[.,!?]|$)"#, t, ci: false)?[1]?.trimmed
            var out = HerbReply(.logTrip, "Trip started. I'm tracking the miles with GPS. Say \"end trip\" when you get there.",
                                cards: [HerbCard(title: "Trip in progress", subtitle: dest ?? "Destination not set", chip: "GPS")])
            out.trip = .start(destination: dest)
            return out
        }
        if rxTest(#"end (?:the |my )?trip|stop (?:the |my )?trip|i'?m here|arrived"#, tl, ci: false) {
            guard let trip = activeTrip else {
                return HerbReply(.logTrip, "There's no trip running. Say \"start a trip\" when you leave.")
            }
            let spoken = rxSearch(#"(\d+(?:\.\d+)?)\s*(?:miles?|mi)\b"#, HerbParse.wordsToDigits(tl), ci: false)?[1].flatMap(Double.init)
            let estimate = (min(45, max(2.4, Double(max(1, trip.minutes ?? 4)) * 0.6)) * 10).rounded() / 10
            var data: HerbFields = ["gpsMiles": .number(spoken ?? trip.gpsMiles ?? estimate), "capture": "gps"]
            var known = ["miles"]
            if let d = trip.destination, !d.isEmpty {
                data["destination"] = .string(d)
                known.append("destination")
            }
            var out = start("trips", t, data: data, known: known)
            out.trip = .end
            return out
        }
        return start("trips", t)
    }

    // MARK: Questions

    func focusReply() -> HerbReply {
        let f = coach.focus()
        var cards = f.items.map { HerbCard(title: $0.title, subtitle: $0.why, value: $0.value, chip: "focus") }
        if let d = f.drop { cards.append(HerbCard(title: "Drop: " + d.title, subtitle: d.why, chip: "drop")) }
        return HerbReply(.focus, f.say, cards: cards,
                         actions: [HerbAction("Add to my calendar", .say("Done — I blocked time for these on your calendar."))])
    }

    func followUpsReply() -> HerbReply {
        let items = coach.followUps()
        guard !items.isEmpty else { return HerbReply(.followUps, "You're all caught up — no follow-ups due today.") }
        let urgent = items.filter { $0.chip == .late || $0.chip == .new }
        var say = "\(items.count) today."
        if !urgent.isEmpty {
            say += " \(urgent.count) \(urgent.count == 1 ? "is" : "are") urgent: "
                + urgent.prefix(2).map { "\($0.name) — \($0.reason.rstrip("."))" }.joined(separator: " and ") + "."
        }
        if let t = items.first(where: { $0.chip == .today }) { say += " Also \(t.name): \(t.reason.rstrip("."))." }
        if !urgent.isEmpty {
            say += " Want me to draft texts to \(urgent.prefix(2).map { $0.name.words.first ?? $0.name }.joined(separator: " and "))?"
        }
        return HerbReply(.followUps, say,
                         cards: items.prefix(6).map { HerbCard(title: $0.name, subtitle: $0.reason, chip: $0.chip.rawValue) },
                         actions: [HerbAction("Draft texts", .say("Drafts are ready in Messages — tap send when you're parked.")),
                                   HerbAction("Open Today", .open(.today))])
    }

    func paceReply() -> HerbReply {
        let tr = PlanTracking(book, year: now.year, now: now)
        guard let inc = tr.item("income"), let pro = tr.item("profit") else { return snag(.pace, "no plan") }
        var say = "Income is \(Format.pct(inc.pacePct)) of pace: \(Format.money(inc.actual)) against \(Format.money(inc.projected)) projected by today. Profit is at \(Format.pct(pro.pacePct)) of pace."
        let fc = tr.forecast.value, goal = inc.goal
        say += " I forecast about \(Format.moneyK(fc)) for the year against your \(Format.moneyK(goal)) goal."
        if fc < goal {
            let n = (goal - fc) / (ytd?.avgClosingIncome ?? 5000)
            say += " Closing the gap takes about \(Format.num(n, decimals: 1)) more closings."
        }
        return HerbReply(.pace, say, cards: tr.items.map {
            HerbCard(title: $0.label, subtitle: "\($0.displayActual) of \($0.displayProjected) projected · goal \($0.displayGoal)",
                     value: Format.pct($0.pacePct), chip: ($0.pacePct ?? 0) >= 1 ? "win" : "late")
        })
    }

    func conversionReply() -> HerbReply {
        guard let led = ytd else { return snag(.conversion, "no ledger") }
        let rows = led.breakdown(.pillar).filter { $0.prospects > 0 }.enumerated()
            .sorted { (-($0.element.conversion ?? 0), $0.offset) < (-($1.element.conversion ?? 0), $1.offset) }.map(\.element)
        guard let best = rows.first, let worst = rows.last else { return snag(.conversion, "no prospects") }
        var say = "Overall you convert \(Format.pct(led.conversion)) — \(led.closingCount) closings from \(led.prospectCount) prospects. \(best.name) converts best at \(Format.pct(best.conversion)), \(best.closings) of \(best.prospects). \(worst.name) is lowest at \(Format.pct(worst.conversion))."
        let cats = led.breakdown(.category).filter { $0.prospects >= 4 }
        if let c = cats.enumerated().max(by: { (($0.element.conversion ?? 0), $1.offset) < (($1.element.conversion ?? 0), $0.offset) })?.element {
            say += " Your best category is \(c.name) at \(Format.pct(c.conversion))."
        }
        return HerbReply(.conversion, say, cards: rows.map {
            HerbCard(title: $0.name, subtitle: "\($0.closings) of \($0.prospects)", value: Format.pct($0.conversion))
        })
    }

    func sourcesNoCloseReply() -> HerbReply {
        guard let led = ytd else { return snag(.sourcesNoClose, "no ledger") }
        let rows = Coach.noCloseSources(led)
        guard !rows.isEmpty else {
            return HerbReply(.sourcesNoClose, "Every source with three or more prospects has closed at least once.")
        }
        let top = rows.prefix(3)
        var say = "These sources send prospects that never close: " + top.map { "\($0.name), \($0.prospects) prospects" }.joined(separator: "; ") + "."
        if let s = top.first(where: { $0.expenses != 0 }) {
            say += " You've spent \(Format.money(s.expenses)) on \(s.name) this year."
        }
        return HerbReply(.sourcesNoClose, say, cards: rows.prefix(6).map {
            HerbCard(title: $0.name, subtitle: "\($0.prospects) prospects, 0 closings" + ($0.expenses != 0 ? " · \(Format.money($0.expenses)) spent" : ""),
                     chip: "concern")
        })
    }

    func efficiencyReply() -> HerbReply {
        guard let led = ytd else { return snag(.efficiency, "no ledger") }
        let rows = led.breakdown(.pillar).filter { $0.closings > 0 && $0.hours > 0 }
            .sorted { $0.hoursPerClosing! < $1.hoursPerClosing! }
        guard let best = rows.first, let worst = rows.last else { return snag(.efficiency, "no closings with hours") }
        var say = "\(worst.name) takes \(Format.num(worst.hoursPerClosing, decimals: 1)) hours per closing; \(best.name) takes \(Format.num(best.hoursPerClosing, decimals: 1))."
        let acts = led.breakdown(.activity).filter { $0.hours >= 10 }
        if let w = acts.enumerated().min(by: { (($0.element.incomePerHour ?? 0), $0.offset) < (($1.element.incomePerHour ?? 0), $1.offset) })?.element {
            say += " Your weakest use of time is \(w.name): \(Format.num(w.hours)) hours for \(Format.money(w.income))."
        }
        return HerbReply(.efficiency, say, cards: rows.map {
            HerbCard(title: $0.name, subtitle: "\(Format.num($0.hoursPerProspect, decimals: 1)) h per prospect",
                     value: "\(Format.num($0.hoursPerClosing, decimals: 1)) h/closing")
        })
    }

    func roiReply() -> HerbReply {
        guard let led = ytd else { return snag(.roi, "no ledger") }
        let rows = led.pillarROI().filter { !["overhead", "total"].contains($0.key) && $0.roiWithTime != nil }
            .sorted { $0.roiWithTime! > $1.roiWithTime! }
        guard let best = rows.first, let worst = rows.last else { return snag(.roi, "no ROI rows") }
        let say = "Counting your time and money, \(best.name) returns \(Format.money(best.roiWithTime! + 1, cents: true)) per dollar invested, and \(worst.name) returns \(Format.money(worst.roiWithTime! + 1, cents: true)). Your overall net ROI is \(Format.pct(led.netROI))."
        return HerbReply(.roi, say, cards: rows.map {
            HerbCard(title: $0.name, subtitle: "Profit \(Format.money($0.profitWithTime))", value: "\(Format.num($0.roiWithTime, decimals: 2))×")
        })
    }

    func indexReply() -> HerbReply {
        guard let led = ytd else { return snag(.index, "no ledger") }
        let w = Coach.indexSummary(led)
        guard let weakest = w.drivers.enumerated().min(by: { (($0.element.ratio ?? 0), $0.offset) < (($1.element.ratio ?? 0), $1.offset) })?.element else {
            return snag(.index, "no drivers")
        }
        let say = "Your Logsperity Index is \(w.display) — \(w.label.lowercased()). 100 is a healthy business. The biggest lever is \(weakest.label.lowercased()): \(weakest.display) against a benchmark of \(weakest.benchmarkDisplay)."
        return HerbReply(.index, say, cards: w.drivers.map {
            HerbCard(title: $0.label, subtitle: "Benchmark \($0.benchmarkDisplay)", value: $0.display)
        })
    }

    func topSourcesReply(_ t: String) -> HerbReply {
        guard let led = ytd else { return snag(.topSources, "no ledger") }
        let all = led.breakdown(.source)
        var rows = all
        if rxTest("realtor|agent", t) {
            let realtorSources = Set(book.prospects.filter { $0.attribution.categoryID == "cat.realtor" }.compactMap(\.attribution.sourceID))
            rows = rows.filter { $0.key.map(realtorSources.contains) ?? false }
        }
        let top = rows.filter { $0.income != 0 && !Coach.isUnknownSource($0) }.enumerated()
            .sorted { (-$0.element.income, $0.offset) < (-$1.element.income, $1.offset) }.prefix(3).map(\.element)
        guard !top.isEmpty else { return HerbReply(.topSources, "No income has been credited to a source yet this year.") }
        var say = "By income earned: " + top.map { "\($0.name) \(Format.money($0.income)) from \($0.closings) closings" }.joined(separator: "; ") + "."
        if let vol = all.filter({ !Coach.isUnknownSource($0) }).enumerated()
            .max(by: { ($0.element.prospects, $1.offset) < ($1.element.prospects, $0.offset) })?.element,
           !top.contains(where: { $0.key == vol.key }) {
            say += " \(vol.name) sent the most prospects — \(vol.prospects) — but only \(vol.closings) closed."
        }
        return HerbReply(.topSources, say, cards: top.map {
            HerbCard(title: $0.name, subtitle: "\($0.closings) of \($0.prospects) closed", value: Format.money($0.income))
        })
    }

    func incomeSummaryReply() -> HerbReply {
        guard let led = ytd else { return snag(.incomeSummary, "no ledger") }
        let goal = led.plan.grossIncomeGoal
        return HerbReply(.incomeSummary, "You've earned \(Format.money(led.incomeTotal)) this year: \(Format.money(led.closingIncome)) from \(led.closingCount) closings and \(Format.money(led.nonTransactionIncome)) of other income. That's \(Format.pct(ratio(led.incomeTotal, goal))) of your \(Format.moneyK(goal)) goal.")
    }

    func expensesSummaryReply() -> HerbReply {
        guard let led = ytd else { return snag(.expensesSummary, "no ledger") }
        var order: [ExpenseGroup] = [], by: [ExpenseGroup: Double] = [:]
        for e in led.expenses {
            if by[e.group] == nil { order.append(e.group) }
            by[e.group, default: 0] += e.amount
        }
        let top = order.enumerated().sorted { (-by[$0.element]!, $0.offset) < (-by[$1.element]!, $1.offset) }.prefix(2).map(\.element)
        let missing = led.expenses.filter { $0.amount >= 75 && !$0.hasReceipt }
        var say = "Expenses this year are \(Format.money(led.expensesTotal)), including \(Format.money(led.mileageDeduction)) of mileage. The biggest groups are "
            + top.map { "\($0.name) at \(Format.money(by[$0]))" }.joined(separator: " and ") + "."
        if !missing.isEmpty { say += " \(missing.count) expenses over 75 dollars are missing receipts." }
        return HerbReply(.expensesSummary, say)
    }

    func mileageSummaryReply() -> HerbReply {
        guard let led = ytd else { return snag(.mileageSummary, "no ledger") }
        return HerbReply(.mileageSummary, "\(Format.num(led.businessMiles)) business miles this year, worth \(Format.money(led.mileageDeduction)) at the IRS rates — 72.5 cents through June and 76 cents from July.")
    }

    static let reportWords: [(Rx, String)] = rxTable([
        ("profit and loss|p ?& ?l|p and l", "pnl"), ("conversion", "conversion"), ("mileage|miles", "mileage"),
        ("expense", "expenses"), ("income", "income"), ("prospect", "prospects"), ("closing", "closings"),
        ("business plan|plan", "business_plan"), ("index", "index"), ("activit", "activity"),
        ("annual|year[- ]end|complete", "annual_complete"), ("roi|return", "profit_roi"),
        ("year to date|ytd", "ytd"), ("coaching", "coaching_advice"),
    ] as [(String, String)])

    /// "Email me the March report" → open it, and offer Mail (the user presses send).
    func reportReply(_ t: String) -> HerbReply {
        let tl = t.lowercased()
        var key: String?, title: String?
        for (i, m) in HerbParse.monthNamesLower.enumerated() where rxTest("\\b\(m)\\b", tl, ci: false) {
            (key, title) = (String(format: "month_%02d", i + 1), "\(monthNames[i]) report")
            break
        }
        if key == nil && tl.contains("last month") {
            let lm = now.startOfMonth.adding(days: -1).month
            (key, title) = (String(format: "month_%02d", lm), "\(monthNames[lm - 1]) report")
        }
        if key == nil && tl.contains("this month") {
            (key, title) = (String(format: "month_%02d", now.month), "\(monthNames[now.month - 1]) report")
        }
        if key == nil { key = Self.reportWords.first { $0.0.test(tl) }?.1 }
        let k = key ?? "ytd"
        let name = title ?? Reports.titles[k] ?? "report"
        let emailing = rxTest(#"\bemail|send\b"#, tl, ci: false)
        var actions = [HerbAction("Open report", .open(.report(k)))]
        if emailing { actions.append(HerbAction("Email it", .open(.emailReport(k)))) }
        return HerbReply(.report, "Here's your \(name)." + (emailing ? " Tap Email it and I'll open Mail with the report — you press send." : ""),
                         actions: actions)
    }

    func planReply() -> HerbReply {
        let i = book.plan(for: now.year), o = i.outputs
        var say = "Your \(now.year) plan: \(Format.money(i.grossIncomeGoal)) gross and \(Format.money(i.netProfitGoal)) net. That takes \(Format.num(o.annualTransactions, decimals: 1)) transactions, about \(Format.moneyK(o.annualVolume)) of volume, and works out to \(Format.money(o.hourlyGross)) an hour."
        if let led = ytd {
            let ext = PlanExtended(inputs: i, ledger: led)
            if let need = ext.prospectsNeeded, need != 0 {
                say += " At your \(Format.pct(ext.conversion)) conversion you need about \(Format.num(need)) prospects — \(Format.num(ext.prospectsPerWeek, decimals: 1)) a week."
            }
        }
        return HerbReply(.plan, say, actions: [HerbAction("Open Business Plan", .open(.businessPlan))])
    }

    func reviewReply() -> HerbReply {
        let items = coach.reviewItems()
        guard let first = items.first else {
            return HerbReply(.review, "Nothing needs you right now — everything I logged has been reviewed.")
        }
        return HerbReply(.review, "\(items.count) quick questions. First: \(first.question)",
                         cards: items.prefix(6).map { HerbCard(title: $0.title, subtitle: $0.question, chip: $0.capture.rawValue) },
                         actions: [HerbAction("Open review", .open(.review))])
    }

    func helpReply() -> HerbReply {
        HerbReply(.help, "I can log things for you — new prospects, closings, income, expenses, trips and activity time — just say them, and I'll ask about anything you leave out. I can update a contact too, like \"I called Priya Shah, follow up in two weeks.\" And I can answer questions like: what should I focus on this week, am I on track, which sources never close, or where am I wasting time.")
    }

    func smalltalkReply(_ t: String) -> HerbReply {
        if rxTest("thank", t) { return HerbReply(.smalltalk, "Anytime.") }
        let greeting = hour.map { "Good \($0 < 12 ? "morning" : $0 < 17 ? "afternoon" : "evening")" } ?? "Hello"
        return HerbReply(.smalltalk, "\(greeting), \(firstName). Ask me what to focus on this week, or tell me about a new lead.",
                         followUp: true)
    }

    func unknownReply() -> HerbReply {
        HerbReply(.unknown, "I'm not sure how to help with that yet. Try \"What should I focus on this week?\" or \"New lead, Kevin Morales, Ruth Alvarez sent him.\"",
                  followUp: true)
    }
}
