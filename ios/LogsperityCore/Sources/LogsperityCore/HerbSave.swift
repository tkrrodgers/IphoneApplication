import Foundation

// Turning a confirmed draft into records (the simulator's log writer: server.py `prepare`, `save_log`,
// `save_closing`, `update_log`). Sources named in speech are matched by `SourceRecord.normalize` or added;
// closings follow R5 (one per prospect) and create their income row (FR-16). The session's book is updated so
// the rest of the turn ("a new entry waits its turn") sees what was saved.

extension HerbSession {
    mutating func save(log: HerbLog, data d: HerbFields, id: RecordID?) throws {
        var out: [LogChange] = []
        var added: [SourceRecord] = []
        let known = book.sources
        func sourceID(_ v: HerbValue?) -> RecordID? {
            guard let name = v?.string?.trimmed, !name.isEmpty else { return nil }
            let norm = SourceRecord.normalize(name)
            if let s = (known + added).first(where: { SourceRecord.normalize($0.name) == norm }) { return s.id }
            let s = SourceRecord(name: name, kind: "person")
            added.append(s)
            out.append(.addSource(s))
            return s.id
        }
        func day(_ k: String) -> Day? { d.day(k) }
        func attribution(_ a: inout Attribution, _ k: String, _ v: HerbValue) {
            switch k {
            case "pillar": a.pillar = v.string.flatMap(Pillar.init(rawValue:))
            case "subPillar": a.subPillar = v.string.flatMap(SubPillar.init(rawValue:))
            case "categoryId": a.categoryID = v.string
            case "activityId": a.activityID = v.string
            case "sourceId": a.sourceID = v.string
            case "source": if d["sourceId"] == nil { a.sourceID = sourceID(v) }
            default: break
            }
        }
        func common(_ k: String, _ v: HerbValue, capture: inout Capture, reviewed: inout Bool, notes: inout String?) {
            switch k {
            case "capture": capture = v.string.flatMap(Capture.init(rawValue:)) ?? capture
            case "reviewed": reviewed = v.truthy
            case "notes": notes = v.string
            default: break
            }
        }
        func prospect(_ p: inout ProspectRecord, _ fields: HerbFields) {
            for (k, v) in fields {
                switch k {
                case "date": p.date = v.string.flatMap(Day.init(iso:)) ?? p.date
                case "firstNames": p.firstNames = v.string ?? ""
                case "lastName": p.lastName = v.string ?? ""
                case "phone1": p.phone1 = v.string
                case "phone1Type": p.phone1Type = v.string
                case "phone2": p.phone2 = v.string
                case "phone2Type": p.phone2Type = v.string
                case "email1": p.email1 = v.string
                case "email2": p.email2 = v.string
                case "address": p.address = v.string
                case "city": p.city = v.string
                case "state": p.state = v.string
                case "zip": p.zip = v.string
                case "strength": p.strength = v.string.flatMap(Strength.init(rawValue:))
                case "planOfAction": p.planOfAction = v.string
                case "followUp": p.followUp = v.string.flatMap(Day.init(iso:))
                default:
                    attribution(&p.attribution, k, v)
                    common(k, v, capture: &p.capture, reviewed: &p.reviewed, notes: &p.notes)
                }
            }
        }
        func existing<T: Identifiable>(_ list: [T]) -> T? where T.ID == RecordID { id.flatMap { id in list.first { $0.id == id } } }
        let date = day("date") ?? now

        switch log {
        case .prospects:
            var p = existing(book.prospects) ?? ProspectRecord(date: date)
            prospect(&p, d)
            if id == nil {
                guard !p.firstNames.isEmpty || !p.lastName.isEmpty else { throw LogRuleError.missing("The prospect's name") }
                p.attribution = p.attribution.normalized()
            }
            if let id { p.id = id }
            out.append(.upsertProspect(p))

        case .closings:
            var p: ProspectRecord, changedProspect = false
            if let pid = d.str("prospectId") {
                guard let found = book.prospects.first(where: { $0.id == pid }) else { throw LogRuleError.missing("The prospect") }
                p = found
            } else {
                guard d.has("lastName") || d.has("firstNames") else { throw LogRuleError.missing("The client's name") }
                p = ProspectRecord(date: date)
                prospect(&p, d.filter { ["firstNames", "lastName", "phone1", "phone1Type", "email1", "pillar", "subPillar",
                                         "categoryId", "activityId", "source", "sourceId", "capture"].contains($0.key) })
                p.strength = .hot
                if p.attribution.categoryID == nil {
                    p.attribution.categoryID = "cat.prospective_client"
                    p.attribution.activityID = "act.prospective_client_interaction"
                }
                p.attribution = p.attribution.normalized()
                changedProspect = true
            }
            try LogRules.checkOneClosing(prospect: p, closings: book.closings)
            var c = existing(book.closings) ?? ClosingRecord(date: date)
            c.date = date
            c.prospectID = p.id
            var a = Attribution()
            for (k, v) in d { attribution(&a, k, v) }
            c.attribution = Attribution(pillar: a.pillar ?? p.attribution.pillar, subPillar: a.subPillar ?? p.attribution.subPillar,
                                        categoryID: a.categoryID ?? p.attribution.categoryID,
                                        activityID: a.activityID ?? p.attribution.activityID,
                                        sourceID: a.sourceID ?? p.attribution.sourceID)
            c.transactionSize = d.num("transactionSize") ?? 0
            c.income = d.num("income") ?? 0
            c.referralRequest = d.str("referralRequest").flatMap(ReferralRequest.init(rawValue:)) ?? .no
            for (k, v) in d { common(k, v, capture: &c.capture, reviewed: &c.reviewed, notes: &c.notes) }
            if !p.reviewed { p.reviewed = true; changedProspect = true }
            if changedProspect { out.append(.upsertProspect(p)) }
            out.append(.upsertClosing(c))
            if d["addToIncome"]?.truthy ?? true {
                for var i in LogRules.incomeRows(for: c, lastName: p.lastName, addToIncome: true) {
                    i.type = .commission
                    i.capture = c.capture
                    out.append(.upsertIncome(i))
                }
            }

        case .income:
            var i = existing(book.income) ?? IncomeRecord(date: date)
            for (k, v) in d {
                switch k {
                case "date": i.date = v.string.flatMap(Day.init(iso:)) ?? i.date
                case "mode": i.mode = v.string.flatMap(IncomeMode.init(rawValue:)) ?? i.mode
                case "type": i.type = v.string.flatMap(IncomeType.init(rawValue:))
                case "amount": i.amount = v.number ?? 0
                case "payer": i.payer = v.string
                case "expect1099": i.expect1099 = v.truthy
                case "lastName": i.lastName = v.string
                case "transactionSize": i.transactionSize = v.number
                case "transactionCount": i.transactionCount = v.number.map { Int($0) }
                case "closingId": i.closingID = v.string
                default:
                    attribution(&i.attribution, k, v)
                    common(k, v, capture: &i.capture, reviewed: &i.reviewed, notes: &i.notes)
                }
            }
            if id == nil { i.attribution = i.attribution.normalized() }
            out.append(.upsertIncome(i))

        case .expenses:
            var e = existing(book.expenses) ?? ExpenseRecord(date: date)
            for (k, v) in d {
                switch k {
                case "date": e.date = v.string.flatMap(Day.init(iso:)) ?? e.date
                case "vendor": e.vendor = v.string ?? ""
                case "amount": e.amount = v.number ?? 0
                case "categoryId":
                    e.categoryID = v.string ?? ""
                    if let cat = Taxonomy.expenseCategoryByID[e.categoryID] { e.group = cat.group }
                case "relationshipSubPillar": e.relationshipSubPillar = v.string.flatMap(SubPillar.init(rawValue:))
                case "source": if d["sourceId"] == nil { e.sourceID = sourceID(v) }
                case "sourceId": e.sourceID = v.string
                case "withWhom": e.withWhom = v.string
                case "purpose": e.purpose = v.string
                case "hasReceipt": e.hasReceipt = v.truthy
                case "checkNumber": e.checkNumber = v.string
                case "cardLast4": e.cardLast4 = v.string
                default: common(k, v, capture: &e.capture, reviewed: &e.reviewed, notes: &e.notes)
                }
            }
            out.append(.upsertExpense(e))

        case .trips:
            var t = existing(book.trips) ?? TripRecord(date: date)
            for (k, v) in d {
                switch k {
                case "date": t.date = v.string.flatMap(Day.init(iso:)) ?? t.date
                case "gpsMiles": t.gpsMiles = v.number
                case "odometerStart": t.odometerStart = v.number
                case "odometerEnd": t.odometerEnd = v.number
                case "destination": t.destination = v.string ?? ""
                case "reason": t.reason = v.string ?? ""
                case "activityId": t.activityID = v.string
                case "isBusiness": t.isBusiness = v.truthy
                case "source": if d["sourceId"] == nil { t.sourceID = sourceID(v) }
                case "sourceId": t.sourceID = v.string
                default: common(k, v, capture: &t.capture, reviewed: &t.reviewed, notes: &t.notes)
                }
            }
            if id == nil && t.odometerEnd != nil && t.odometerStart == nil {  // R6
                t.odometerStart = LogRules.defaultOdometerStart(for: t.date, trips: book.trips)
            }
            out.append(.upsertTrip(t))

        case .activities:
            var a = existing(book.activities) ?? ActivityRecord(date: date)
            for (k, v) in d {
                switch k {
                case "date": a.date = v.string.flatMap(Day.init(iso:)) ?? a.date
                case "minutes":
                    let m = Int(pyRound((v.number ?? 0) / 15) * 15)
                    guard m > 0 else { throw LogRuleError.missing("At least 15 minutes") }
                    a.minutes = m
                default:
                    attribution(&a.attribution, k, v)
                    common(k, v, capture: &a.capture, reviewed: &a.reviewed, notes: &a.notes)
                }
            }
            if let act = a.attribution.activityID.flatMap({ Taxonomy.activityByID[$0] }) {
                a.attribution.pillar = a.attribution.pillar ?? act.pillar
                a.attribution.subPillar = a.attribution.subPillar ?? act.subPillar
            }
            out.append(.upsertActivity(a))
        }
        commit(out)
    }
}
