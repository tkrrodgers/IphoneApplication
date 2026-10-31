import Foundation

// HERB's follow-up questions, part 2 (design §17.2): the dialog policy. Every log has a frame of slots; HERB fills
// what it can from what was said, then asks for what is still missing, one short question per turn —
// required (always), recommended (Balanced and Thorough), thorough (Thorough only). Contact fields are offered
// together; anything can be corrected at any point; nothing is saved until the user says so. Port of dialog.py.

private typealias D = HerbDialog

extension HerbSession {
    // MARK: Learning (§17.2 "HERB learns what the user doesn't want to be asked")

    /// After three skips in a row HERB stops offering that field (not in Thorough mode). Giving it resets the count.
    mutating func learn(_ keys: [String], filled: Bool = false) -> String? {
        let keys = keys.filter { D.learnable[$0] != nil }
        guard !keys.isEmpty else { return nil }
        var msg: String?
        for k in keys {
            if filled {
                if let n = settings.skipCounts[k], n != 0 { settings.skipCounts[k] = 0 }
                continue
            }
            let n = (settings.skipCounts[k] ?? 0) + 1
            settings.skipCounts[k] = n
            if n >= 3 && !settings.neverAsk.contains(k) && settings.questionStyle != .thorough {
                settings.neverAsk.append(k)
                msg = "I notice you usually skip \(D.learnable[k]!), so I'll stop asking. You can turn it back on in HERB Autopilot."
            }
        }
        return msg
    }

    mutating func decline(_ st: inout HerbDialogState, _ keys: [String]) -> String? {
        for k in keys {
            if !st.skipped.contains(k) { st.skipped.append(k) }
            st.queue.removeAll { $0 == k }
        }
        return learn(keys)
    }

    func who(_ st: HerbDialogState, full: Bool = false) -> String {
        let d = st.data, m = st.meta
        if st.frame == "update" || st.frame == "closings" {
            let n = m.text("name") ?? [d.text("firstNames"), d.text("lastName")].compactMap { $0 }.joined(separator: " ")
            let r = !n.isEmpty && !full && st.frame == "update" ? n.words[0] : n
            return r.isEmpty ? "the client" : r
        }
        if full {
            let n = [d.text("firstNames"), d.text("lastName")].compactMap { $0 }.joined(separator: " ")
            return n.isEmpty ? "the prospect" : n
        }
        return d.text("firstNames") ?? d.text("lastName") ?? "the prospect"
    }

    // MARK: Applying what was heard

    mutating func apply(_ st: inout HerbDialogState, _ upd: HerbFields, _ got: Set<String>) {
        for (k, v) in upd {
            if k == "_addNote" {
                st.meta["notes"] = .list((st.meta["notes"]?.list ?? []) + [v])
            } else if k == "_tag" {
                var tags = st.meta["tags"]?.list ?? []
                if let s = v.string, !tags.contains(where: { $0.string?.lowercased() == s.lowercased() }) { tags.append(v) }
                st.meta["tags"] = .list(tags)
            } else if k.hasPrefix("_") {
                st.meta[String(k.dropFirst())] = v
            } else {
                st.data[k] = v
            }
        }
        for g in got.sorted() {
            if !st.known.contains(g) { st.known.append(g) }
            st.skipped.removeAll { $0 == g }
            st.queue.removeAll { $0 == g }
        }
        _ = learn(got.sorted(), filled: true)
        settle(&st)
    }

    /// Derived state after each change: duplicates, meal categories, closing estimates.
    func settle(_ st: inout HerbDialogState) {
        if st.frame == "prospects" {
            if let last = st.data.text("lastName"), !st.meta.has("dupChecked") {
                st.meta["dupChecked"] = true
                let first = (st.data.str("firstNames") ?? "").lowercased()
                let dup = book.prospects.enumerated().filter { $0.element.firstNames.lowercased() == first && $0.element.lastName.lowercased() == last.lowercased() }
                    .max { ($0.element.date, $1.offset) < ($1.element.date, $0.offset) }?.element
                if let dup {
                    st.meta["dupId"] = .string(dup.id)
                    st.meta["dupDate"] = .string(dup.date.iso)
                }
            }
            if st.meta.str("dupAnswer") == "new" { st.meta["dupId"] = .null }
            else if st.meta.str("dupAnswer") == "same" && st.meta.has("dupId") { toUpdate(&st) }
        }
        if st.frame == "expenses", let cat = st.data.text("categoryId") {
            st.meta["mealish"] = .bool(D.mealishCats.contains { cat.hasSuffix($0) })
            if cat.hasSuffix(".meal") {
                var (g, c) = ("relationships", "exp.relationships.meal")
                if st.meta.has("solo") { (g, c) = ("travel", "exp.travel.meal") }
                else if let pid = st.meta.text("personId"), book.sourceProfile(pid)?.sub == .clients { (g, c) = ("clients", "exp.clients.meal") }
                st.data["groupId"] = .string(g)
                st.data["categoryId"] = .string(c)
            }
        }
        if st.frame == "closings", let size = st.data.num("transactionSize"), size != 0 {
            st.meta["estimate"] = .number(pyRound(size * book.closingYield(now: now)))
        }
    }

    /// "Same person" on a duplicate: fold the new details into the existing prospect instead.
    func toUpdate(_ st: inout HerbDialogState) {
        guard let pid = st.meta.str("dupId"), let p = book.prospects.first(where: { $0.id == pid }) else { return }
        var patch: HerbFields = [:]
        for k in ["phone1", "phone1Type", "email1", "address", "city", "state", "zip", "followUp", "strength"] where st.data.has(k) {
            patch[k] = st.data[k]
        }
        var notes = st.meta["notes"]?.list ?? []
        if let amt = st.meta.num("loanAmount"), amt != 0 {
            notes.append(.string("About \(Format.money(amt)) \(st.meta.text("loanPurpose") ?? "purchase")."))
        }
        let meta: HerbFields = ["name": .string(p.fullName), "existingNotes": HerbValue(p.notes), "notes": .list(notes),
                                "followTime": st.meta["followTime"] ?? .null, "strengthWas": HerbValue(p.strength?.rawValue)]
        st.frame = "update"
        st.id = p.id
        st.data = patch
        st.meta = meta
        st.queue = []
        st.offered = []
        st.known = ["phone", "email", "address", "followUp", "strength"].filter(st.known.contains)
    }

    // MARK: Defaults and final records

    /// §17.2 rule 5: hot → next business day, medium → 3 days, cold → 2 weeks, rolled past weekends; no-go → none.
    func defaultFollow(_ st: HerbDialogState) -> String? {
        let strength = st.data.text("strength") ?? st.meta.text("strengthWas") ?? "medium"
        let table: [String: Int?] = ["red_hot": 1, "hot": 1, "medium": 3, "cold": 14, "no_go": nil]
        let days: Int? = table[strength] ?? 3
        guard let days else { return nil }
        var d = now.adding(days: days)
        while d.weekday >= 5 { d = d.adding(days: 1) }
        return d.iso
    }

    func defaultValue(_ st: HerbDialogState, _ key: String) -> HerbValue? {
        switch key {
        case "followUp": defaultFollow(st).map { .string($0) }
        case "income": st.meta["estimate"].flatMap { $0 == .null ? nil : $0 }
        default: nil
        }
    }

    func composeNotes(_ st: HerbDialogState) -> String? {
        let m = st.meta, d = st.data
        var out: [String] = []
        if let amt = m.num("loanAmount"), amt != 0 { out.append("About \(Format.money(amt)) \(m.text("loanPurpose") ?? "purchase").") }
        else if let p = m.text("loanPurpose") { out.append("\(p.pyCapitalize).") }
        out += m.strings("tags").map { $0.upperFirst + "." }
        if let ft = m.text("followTime"), let fu = d.day("followUp") {
            out.append("Wants to talk \(Format.relativeDay(fu, now: now)) after \(ft).")
        }
        out += m.strings("notes")
        return out.isEmpty ? nil : out.joined(separator: " ")
    }

    static let prospectiveClient = HerbTags(.clients, "cat.prospective_client", "act.prospective_client_interaction")

    func finalData(_ st: HerbDialogState) -> HerbFields {
        var d = st.data
        let m = st.meta
        d.setDefault("date", .string(now.iso))
        switch st.frame {
        case "prospects":
            if !d.has("categoryId") { d.merge(D.tagUpdate(Self.prospectiveClient)) { $1 } }
            d.setDefault("strength", "medium")
            d.setDefault("planOfAction", "Call")
            if !st.known.contains("followUp") && !d.has("followUp") { d["followUp"] = HerbValue(defaultFollow(st)) }
            var notes = composeNotes(st)
            if m.has("sourceUnknown") && !d.has("source") {  // D3: visible in reports, waiting in the Review queue
                d["source"] = .string(D.unknownSource)
                d["reviewed"] = false
                if !(notes ?? "").contains("HERB: still need") {
                    notes = [notes, "HERB: still need the source."].compactMap { $0 }.joined(separator: " ")
                }
            }
            d["notes"] = HerbValue(notes)
            d["capture"] = "voice"
        case "update":
            d["date"] = nil
            if m.has("touched") && !st.known.contains("followUp") { d["followUp"] = HerbValue(defaultFollow(st)) }
            if let new = composeNotes(st) { d["notes"] = .string((m.text("existingNotes").map { $0 + " | " } ?? "") + new) }
        case "expenses":
            if !d.has("categoryId") {
                d["groupId"] = "general"
                d["categoryId"] = "exp.general.office_supplies"
                d["reviewed"] = false
            }
            let meal = m.text("meal")
            if !d.has("vendor") { d["vendor"] = .string(meal?.pyCapitalize ?? "Unknown vendor") }
            if let meal, let w = d.text("withWhom"), !d.has("purpose") {
                d["purpose"] = .string("\(meal.pyCapitalize) with \(w) — business discussion")
            }
            d["relationshipSubPillar"] = d.str("groupId") == "relationships" ? "professional" : .null
            d["hasReceipt"] = false
            d["capture"] = "voice"
        case "activities":
            if let n = m.num("leads"), n != 0 { d["notes"] = .string("Said: \(Int(n)) leads.") }
            d["capture"] = "voice"
        case "income":
            d.setDefault("type", "commission")
            d["mode"] = "type"
            d["expect1099"] = true
            d["capture"] = "voice"
        case "trips":
            d.setDefault("destination", "Unknown")
            d.setDefault("reason", "Office Visits")
            d["isBusiness"] = true
            d.setDefault("capture", "voice")
        case "closings":
            if !st.known.contains("income") { d["income"] = m["estimate"] ?? .null }
            if m.has("repeat"), let pid = d.str("prospectId"), let p = book.prospects.first(where: { $0.id == pid }) {
                let a = p.attribution
                return ["date": d["date"]!, "mode": "transaction", "lastName": .string(p.lastName),
                        "transactionSize": d["transactionSize"] ?? .null, "amount": d["income"] ?? .null,
                        "pillar": HerbValue(a.pillar?.rawValue), "subPillar": HerbValue(a.subPillar?.rawValue),
                        "categoryId": HerbValue(a.categoryID), "activityId": HerbValue(a.activityID),
                        "sourceId": HerbValue(a.sourceID), "type": "commission", "notes": "Repeat transaction (rule R4)",
                        "capture": "voice"]
            }
            d["addToIncome"] = true
            d["referralRequest"] = "ask_14"
            d["capture"] = "voice"
            if !d.has("prospectId") { d.merge(D.tagUpdate(Self.prospectiveClient)) { $1 } }
        default: break
        }
        return d
    }

    func saveLog(_ st: HerbDialogState) -> HerbLog {
        if st.frame == "closings" && st.meta.has("repeat") { return .income }
        return HerbLog(rawValue: st.log) ?? .prospects
    }

    func makeDraft(_ st: HerbDialogState, _ pending: HerbPending?) -> HerbDraft {
        HerbDraft(log: saveLog(st), recordID: st.id, data: finalData(st), summary: summary(st, pending))
    }

    // MARK: The draft card and readbacks

    func summary(_ st: HerbDialogState, _ pending: HerbPending?) -> [HerbSummaryRow] {
        let d = finalData(st), m = st.meta
        let asking = Set([pending?.slot].compactMap { $0 } + (pending?.slots ?? []))
        var rows: [HerbSummaryRow] = []
        func row(_ slot: String?, _ label: String, _ value: String?) {
            rows.append(HerbSummaryRow(label: label, value: value.flatMap { $0.isEmpty ? nil : $0 } ?? Format.dash,
                                       asking: slot.map(asking.contains) ?? false))
        }
        switch st.frame {
        case "prospects", "update":
            if st.frame == "update" { row(nil, "Updating", m.text("name")) }
            else { row("name", "Name", st.data.has("lastName") || st.data.has("firstNames") ? who(st, full: true) : "?") }
            if st.frame == "prospects" || d.has("phone1") { row("phone", d.text("phone1Type") ?? "Mobile", d.text("phone1")) }
            if st.frame == "prospects" || d.has("address") { row("address", "Address", D.addrText(d)) }
            if d.has("email1") || asking.contains("email") { row("email", "Email", d.text("email1")) }
            if st.frame == "prospects" {
                let names = HerbParse.tagNames(d.str("subPillar"), d.str("categoryId"), d.str("activityId"))
                row("source", "Source", m.has("sourceUnknown") ? "Unknown — to review" : d.text("source"))
                row("relation", "Pillar · Category", st.known.contains("relation") || st.known.contains("source")
                    ? "\(names.0) · \(names.1)" : "\(names.0) · \(names.1) (default)")
            }
            if st.frame == "prospects" || d.has("strength") {
                row("strength", "Strength", Strength(rawValue: d.text("strength") ?? "medium")?.name)
            }
            if st.frame == "prospects" || d["followUp"] != nil {
                row("followUp", "Follow-up", d.has("followUp") ? D.dayText(d.str("followUp"), now: now, time: m.text("followTime"))
                    : st.frame == "update" ? Format.dash : "None")
            }
            if m.has("loanAmount") || m.has("loanPurpose") {
                row("loan", "Loan", (m.text("loanPurpose") ?? "purchase").pyCapitalize
                    + (m.num("loanAmount").flatMap { $0 == 0 ? nil : " · ~\(Format.money($0))" } ?? ""))
            }
            if st.frame == "update" && d.has("notes") { row(nil, "Note added", composeNotes(st)) }
            if m.has("dupId") && !st.known.contains("dup") { row("dup", "Possible duplicate", "Existing prospect from \(m.text("dupDate") ?? "")") }
        case "expenses":
            let cat = Taxonomy.expenseCategoryByID[d.str("categoryId") ?? ""]
            row("amount", "Amount", d.num("amount").flatMap { $0 == 0 ? nil : Format.money($0, cents: true) })
            row("category", "Category", st.known.contains("category")
                ? "\(ExpenseGroup(rawValue: d.str("groupId") ?? "")?.name ?? "") · \(cat?.name ?? "")" : nil)
            row("vendor", "Vendor", st.data.text("vendor"))
            if m.has("mealish") { row("withWhom", "With", m.has("solo") ? "Just me" : d.text("withWhom")) }
            if let p = d.text("purpose"), m.has("meal") { row("purpose", "Purpose", p) }
            if st.known.contains("category") { row(nil, "IRS category", cat?.irs) }
        case "activities":
            let a = Taxonomy.activityByID[d.str("activityId") ?? ""]
            let mins = Int(d.num("minutes") ?? 0)
            row("activity", "Activity", a?.name)
            row(nil, "Pillar", a?.pillar.name)
            row("minutes", "Time", mins == 0 ? nil : mins >= 60 ? "\(mins / 60) h \(String(format: "%02d", mins % 60)) min" : "\(mins) min")
            if d.has("source") || asking.contains("withWhom") { row("withWhom", "With", d.text("source")) }
        case "income":
            row("amount", "Amount", d.num("amount").flatMap { $0 == 0 ? nil : Format.money($0) })
            row("type", "Type", st.known.contains("type") ? IncomeType(rawValue: d.str("type") ?? "")?.name : nil)
            row("payer", "Payer", d.text("payer"))
        case "trips":
            let rate = Taxonomy.mileageRate(on: d.day("date") ?? now)
            let mi = d.num("gpsMiles").flatMap { $0 == 0 ? nil : $0 }
            row("destination", "Destination", st.data.text("destination"))
            row("miles", "Miles", mi.map { Format.num($0, decimals: 1) })
            row("reason", "Reason", st.data.text("reason"))
            if let mi { row(nil, "Deduction", "\(Format.money(mi * rate, cents: true)) at \(Format.num(rate * 100, decimals: 1))¢/mi") }
        case "closings":
            row("client", "Client", m.text("name"))
            if let c = m["candidates"]?.list, !c.isEmpty {
                row("pick", "Which one?", c.compactMap { $0.object?["name"]?.string }.joined(separator: " or "))
            }
            row("size", "Transaction size", d.num("transactionSize").flatMap { $0 == 0 ? nil : Format.money($0) })
            let inc = st.data.num("income").flatMap { $0 == 0 ? nil : $0 } ?? m.num("estimate").flatMap { $0 == 0 ? nil : $0 }
            row("income", "Income", inc.map { Format.money($0) + (st.known.contains("income") ? "" : " (estimate)") })
            if m.has("repeat") { row(nil, "Logged as", "Income (repeat client, rule R4)") }
            else {
                row(nil, "Add to income log", "Yes")
                row(nil, "Referral / review request", "Ask in 14 days")
            }
        default: break
        }
        return rows
    }

    func readback(_ st: HerbDialogState) -> String {
        let d = finalData(st), m = st.meta
        switch st.frame {
        case "prospects":
            var parts = [who(st, full: true)]
            if let ph = d.text("phone1") { parts.append("\((d.text("phone1Type") ?? "mobile").lowercased()) \(ph)") }
            if d.has("address") { parts.append(D.addrText(d)) }
            if let e = d.text("email1") { parts.append(e) }
            if let s = d.text("source") { parts.append(m.has("sourceUnknown") ? "source unknown" : "from \(s)") }
            else if st.known.contains("relation") {
                parts.append(HerbParse.tagNames(d.str("subPillar"), d.str("categoryId"), d.str("activityId")).1)
            }
            if let amt = m.num("loanAmount"), amt != 0 { parts.append("\(m.text("loanPurpose") ?? "purchase") around \(Format.money(amt))") }
            parts.append(d.has("followUp") ? "follow-up \(D.dayText(d.str("followUp"), now: now, time: m.text("followTime")))" : "no follow-up")
            let lead = st.chain?.total.map { "Lead \(st.chain!.i) of \($0): " } ?? ""
            return lead + parts.joined(separator: ", ") + ". Save it?"
        case "update":
            var ch: [String] = []
            if let ph = d.text("phone1") { ch.append("phone \(ph)") }
            if let e = d.text("email1") { ch.append("email \(e)") }
            if d.has("address") { ch.append("address \(D.addrText(d))") }
            if let s = d.text("strength").flatMap(Strength.init(rawValue:)) { ch.append("strength \(s.name.lowercased())") }
            if d["followUp"] != nil {
                ch.append(d.has("followUp") ? "follow-up \(D.dayText(d.str("followUp"), now: now, time: m.text("followTime")))" : "no follow-up")
            }
            if let note = composeNotes(st) { ch.append("note: \(note)") }
            return "Update \(m.text("name") ?? ""): " + (ch.isEmpty ? "no changes" : ch.joined(separator: "; ")).rstrip(".") + ". Save it?"
        case "expenses":
            let cat = Taxonomy.expenseCategoryByID[d.str("categoryId") ?? ""]
            let amt = d.num("amount") ?? 0
            var s = Format.money(amt, cents: amt.truncatingRemainder(dividingBy: 1) != 0)
            if st.data.has("vendor") { s += " at \(d.str("vendor") ?? "")" }
            if let w = d.text("withWhom") { s += " with \(w)" }
            s += ", as \(cat?.name ?? "")."
            if m.has("solo") && m.has("meal") {
                s += " Heads up: meals on your own usually aren't deductible unless you're traveling overnight."
            }
            if amt >= 75 { s += " It's over 75 dollars, so snap the receipt when you can." }
            if d.str("categoryId") == "exp.travel.car_expenses" {
                s += " Note: if you use the standard mileage rate, gas usually isn't deductible separately."
            }
            return s + " Save it?"
        case "activities":
            let a = Taxonomy.activityByID[d.str("activityId") ?? ""]
            var s = "\(Format.spokenMinutes(Int(d.num("minutes") ?? 0))) of \(a?.name ?? "")" + (d.text("source").map { " with \($0)" } ?? "") + "."
            if let n = m.num("leads"), n != 0 { s += " You mentioned \(Int(n)) leads — I'll help you add them after this." }
            return s + " Save it?"
        case "income":
            let type = IncomeType(rawValue: d.str("type") ?? "")?.name.lowercased() ?? ""
            return "\(Format.money(d.num("amount"))) \(type)" + (d.text("payer").map { " from \($0)" } ?? "") + ". Save it?"
        case "trips":
            let rate = Taxonomy.mileageRate(on: d.day("date") ?? now)
            let mi = d.num("gpsMiles") ?? 0
            let dest = st.data.text("destination")
            let reason = d.str("reason") ?? ""
            let why = dest.map { $0.lowercased().contains(reason.lowercased()) } ?? false ? "" : " for \(reason)"
            return "\(gFormat(mi)) business miles" + (dest.map { " to \($0)" } ?? "") + why
                + " — worth \(Format.money(mi * rate, cents: true)). Save it?"
        case "closings":
            if m.has("repeat") {
                return "\(m.text("name") ?? "") already has a closing, so I'll log this one as income to keep your conversion rate honest: \(Format.money(d.num("amount"))). Save it?"
            }
            return "\(m.text("name") ?? "") closed: \(Format.money(d.num("transactionSize"))), and you earned \(Format.money(d.num("income"))). Save it and ask for a review in 14 days?"
        default:
            return "Save it?"
        }
    }

    /// Short spoken confirmation of what was just captured (implicit confirmation, §17.2 rule 4).
    func echo(_ st: HerbDialogState, _ keys: Set<String>) -> String {
        let d = st.data, m = st.meta
        let order = (D.frames[st.frame] ?? []).map(\.key) + ["phone", "email", "address", "followUp", "strength"]
        var out: [String] = []
        for k in keys.sorted(by: { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }) {
            switch k {
            case "name" where st.frame == "prospects": out.append(who(st, full: true))
            case "phone": if let ph = d.text("phone1") { out.append("\((d.text("phone1Type") ?? "mobile").lowercased()) \(ph)") }
            case "address": if d.has("address") { out.append(D.addrText(d)) }
            case "email": if let e = d.text("email1") { out.append(e) }
            case "source" where st.frame == "prospects":
                if m.has("sourceUnknown") { out.append("source unknown") }
                else if let s = d.text("source") { out.append("from \(s)") }
                else if d.has("categoryId") { out.append(HerbParse.tagNames(d.str("subPillar"), d.str("categoryId"), d.str("activityId")).1) }
            case "relation" where !keys.contains("source") && d.has("categoryId"):
                let cat = HerbParse.tagNames(d.str("subPillar"), d.str("categoryId"), d.str("activityId")).1
                out.append("\(d.text("source") ?? "that source") as \(cat.lowercased())")
            case "followUp":
                out.append(d.has("followUp") ? "follow-up \(D.dayText(d.str("followUp"), now: now, time: m.text("followTime")))" : "no follow-up")
            case "strength": if let s = d.text("strength").flatMap(Strength.init(rawValue:)) { out.append(s.name.lowercased()) }
            case "loan":
                if m.has("loanAmount") || m.has("loanPurpose") {
                    out.append((m.text("loanPurpose") ?? "purchase") + (m.num("loanAmount").flatMap { $0 == 0 ? nil : " around \(Format.money($0))" } ?? ""))
                }
            case "amount":
                if let a = d.num("amount"), a != 0 { out.append(Format.money(a, cents: a.truncatingRemainder(dividingBy: 1) != 0)) }
            case "category": if let c = Taxonomy.expenseCategoryByID[d.str("categoryId") ?? ""] { out.append(c.name.lowercased()) }
            case "vendor": if let v = d.text("vendor") { out.append("at \(v)") }
            case "withWhom": out.append(m.has("solo") ? "just you" : "with \(d.text("withWhom") ?? d.text("source") ?? "")")
            case "purpose": out.append("purpose noted")
            case "activity": if let a = Taxonomy.activityByID[d.str("activityId") ?? ""] { out.append(a.name) }
            case "minutes": if let n = d.num("minutes"), n != 0 { out.append(Format.spokenMinutes(Int(n))) }
            case "type": if let t = IncomeType(rawValue: d.str("type") ?? "") { out.append(t.name.lowercased()) }
            case "payer": if let p = d.text("payer") { out.append("from \(p)") }
            case "miles": if let mi = d.num("gpsMiles"), mi != 0 { out.append("\(gFormat(mi)) miles") }
            case "destination": if let x = d.text("destination") { out.append("to \(x)") }
            case "reason":
                if let r = d.text("reason"), !(d.str("destination") ?? "").lowercased().contains(r.lowercased()) { out.append("for \(r)") }
            case "client": if let n = m.text("name") { out.append(n) }
            case "size": if let s = d.num("transactionSize"), s != 0 { out.append("\(Format.money(s)) loan") }
            case "income": if let i = d.num("income"), i != 0 { out.append("you earned \(Format.money(i))") }
            default: break
            }
        }
        return out.joined(separator: ", ")
    }

    // MARK: Questions

    func question(_ st: HerbDialogState, _ q: HerbPending, _ prev: HerbPending?) -> (String, [String]) {
        let k = q.slot, d = st.data, m = st.meta
        let nm = who(st), frame = st.frame
        if q.type == "confirm" { return (readback(st), []) }
        if q.type == "offer" {
            let ks = q.slots ?? []
            let again = ks.contains(where: st.offered.contains)
            let labels = ks.map { (again ? D.offerThe : D.offerA)[$0]! }
            let joined = joinAnd(Array(labels.prefix(1)) + labels.dropFirst().map { rxSub("^(?:an?|the) ", $0, "") })
            return ("Do you want to add \(joined)?", ["Yes", "No"] + (ks.count > 1 ? ks.map { "\(D.short[$0]!) only" } : []))
        }
        let skip = D.isRequired(frame, k) ? [] : ["Skip"]
        if q.type == "default" {
            if k == "followUp" {
                return ("When should you follow up with \(nm)\(frame == "update" ? " next" : "") — \(D.dayText(q.value?.string, now: now))?",
                        ["Yes", "Next week", "In 2 weeks", "No follow-up"])
            }
            if k == "income" {
                let v = q.value?.number
                return ("What did you earn on it? At your usual \(Format.num(book.closingYield(now: now) * 100, decimals: 2))% that's about \(Format.money(v)).",
                        ["Yes, \(Format.money(v))", "Different amount"])
            }
        }
        if let k, ["address", "phone", "email"].contains(k) {
            if let prev, prev.type == "value", let ps = prev.slot, ["address", "phone", "email"].contains(ps), ps != k {
                return ("And \(D.offerThe[k]!)?", skip)
            }
            return (["address": "What's the address?", "phone": "What's the phone number?", "email": "What's the email address?"][k]!, skip)
        }
        switch (frame, k) {
        case ("prospects", "name"):
            if let ch = st.chain, let total = ch.total { return ("Lead \(ch.i) of \(total) — what's the name?", ["That's all"]) }
            if st.chain != nil { return ("Go ahead — what's the name?", ["That's all"]) }
            return ("What's the new prospect's name?", [])
        case ("prospects", "lastName"): return ("And \(nm)'s last name?", [])
        case ("prospects", "dup"):
            let when = m.day("dupDate").map { Format.relativeDay($0, now: now) } ?? "before"
            return ("You already have a \(who(st, full: true)) from \(when). Is this the same person?", ["Same person", "New prospect"])
        case ("prospects", "source"):
            return ("Who referred \(nm), or where did the lead come from?", ["Open house", "Online", "Don't know"])
        case ("prospects", "relation"):
            let s = d.str("source") ?? ""
            return ("\(s) is new to me. Who is \(s) to you — a realtor, a past client, a friend or family member, or another professional?",
                    ["Realtor", "Past client", "Friend or family", "Other professional"])
        case ("prospects", "followUp"), ("update", "followUp"):
            return ("When should you follow up with \(nm)\(frame == "update" ? " next" : "")?", ["Tomorrow", "Next week", "In 2 weeks", "No follow-up"])
        case ("prospects", "strength"): return ("How hot is \(nm) — hot, warm or cold?", ["Hot", "Warm", "Cold"])
        case ("prospects", "loan"): return ("Do you know the loan yet — purchase or refinance, and roughly how much?", ["Skip"])
        case ("expenses", "amount"), ("income", "amount"): return ("How much was it?", [])
        case ("expenses", "category"):
            if m.has("elseAsked") { return ("In a few words, what was it for?", []) }
            return ("What was it for — a meal, gas, office supplies, marketing, or something else?",
                    ["Meal", "Gas", "Office supplies", "Marketing", "Gift", "Something else"])
        case ("expenses", "withWhom"):
            if !m.has("meal") { return ("Who was the gift for?", skip) }
            return ("Who was the \(m.text("meal") ?? "meal") with?", ["Just me"] + skip)
        case ("expenses", "vendor"): return (m.has("meal") ? "Which restaurant?" : "Where did you buy it?", skip)
        case ("expenses", "purpose"): return ("What was the business purpose — what did you talk about?", skip)
        case ("activities", "activity"):
            if m.has("elseAsked") { return ("In a few words, what was it?", []) }
            let mins = d.num("minutes").flatMap { $0 == 0 ? nil : " — \(Format.spokenMinutes(Int($0)))" } ?? ""
            return ("What kind of activity was that\(mins)? For example door knocking, an open house, a realtor meeting or cold calls.",
                    ["Door knocking", "Open house", "Realtor meeting", "Cold calls", "Something else"])
        case ("activities", "minutes"):
            let name = Taxonomy.activityByID[d.str("activityId") ?? ""]?.name ?? "it"
            return ("How long did you spend on \(name)?", ["30 minutes", "1 hour", "2 hours"])
        case ("activities", "withWhom"): return ("Who was it with?", skip)
        case ("income", "type"):
            return ("What kind of income — a commission, a referral fee, a bonus, or a consulting fee?",
                    ["Commission", "Referral fee", "Bonus", "Consulting fee"])
        case ("income", "payer"): return ("Who paid it?", skip)
        case ("trips", "miles"): return ("How many miles was the drive\(d.text("destination").map { " to \($0)" } ?? "")?", [])
        case ("trips", "destination"): return ("Where did you drive to?", skip)
        case ("trips", "reason"):
            return ("What was the business purpose — a client meeting, a closing, a realtor visit, or an open house?",
                    ["Client meeting", "Closing", "Realtor visit", "Open house", "Office"])
        case ("closings", "client"): return ("Congratulations! Which client closed?", [])
        case ("closings", "pick"):
            let names = m["candidates"]?.list?.compactMap { $0.object?["name"]?.string } ?? []
            return ("Which one — \(joinAnd(names).replacingOccurrences(of: " and ", with: " or "))?", names)
        case ("closings", "size"): return ("What was the loan amount?", [])
        case ("closings", "income"): return ("What did you earn on it?", [])
        default: return ("Can you tell me more?", skip)
        }
    }

    func nextQuestion(_ st: inout HerbDialogState) -> HerbPending {
        let allowed = D.levels(settings.questionStyle), never = Set(settings.neverAsk)
        let slots = (D.frames[st.frame] ?? []).filter { $0.applies(st) }
        let queue = st.queue
        let todo = slots.filter { s in
            if st.known.contains(s.key) || st.skipped.contains(s.key) { return false }
            return s.level == D.required || queue.contains(s.key) || (allowed.contains(s.level) && !never.contains(s.key))
        }
        for k in queue {
            if todo.contains(where: { $0.key == k }) { return HerbPending("value", slot: k) }
            st.queue.removeAll { $0 == k }
        }
        guard let s = todo.first else { return HerbPending("confirm") }
        if let g = s.group { return HerbPending("offer", slots: todo.filter { $0.group == g }.map(\.key)) }
        if s.kind == "default" {
            if let v = defaultValue(st, s.key), !st.meta.has("noDefault") { return HerbPending("default", slot: s.key, value: v) }
            return HerbPending("value", slot: s.key)
        }
        return HerbPending(s.kind, slot: s.key)
    }

    // MARK: Replies

    func hasContent(_ st: HerbDialogState) -> Bool { !st.known.isEmpty || st.id != nil }

    /// Something worth saving (chain defaults alone don't count).
    func hasEntry(_ st: HerbDialogState) -> Bool { st.frame == "prospects" ? st.known.contains("name") : hasContent(st) }

    func intent(_ st: HerbDialogState) -> HerbIntent { D.intent[st.frame] ?? .logProspect }

    func end(_ intent: HerbIntent, _ say: String, _ actions: [HerbAction] = []) -> HerbReply {
        HerbReply(intent, say, actions: actions)
    }

    func ack(_ st: HerbDialogState) -> String { ["Got it.", "Okay.", "Thanks.", "Great."][st.turns % 4] }

    func leadFor(_ st: HerbDialogState, _ keys: Set<String>, first: Bool = false) -> String {
        let e = echo(st, keys)
        if first { return e.isEmpty ? "" : "Got it — \(e)." }
        return e.isEmpty ? ack(st) : e.upperFirst + "."
    }

    func joinSay(_ parts: String...) -> String { parts.filter { !$0.isEmpty }.joined(separator: " ") }

    mutating func askChange(_ st: inout HerbDialogState, _ say: String, _ chips: [String] = []) -> HerbReply {
        let pending = HerbPending("change")
        st.pending = pending
        var out = HerbReply(intent(st), say, actions: chips.map { HerbAction.reply($0) } + [HerbAction("Edit", .editDraft), .reply("Cancel")],
                            followUp: true)
        out.draft = makeDraft(st, pending)
        out.state = st
        out.pending = pending
        return out
    }

    /// Ask the next question. `soft` is an echo of what was just captured — dropped when the next step is the full
    /// readback, which repeats it anyway.
    mutating func respond(_ st: inout HerbDialogState, _ lead: String = "", extra: [HerbAction] = [], soft: String = "") -> HerbReply {
        let prev = st.pending
        var q = nextQuestion(&st)
        if !(q.type == prev?.type && q.slot == prev?.slot && (q.slots ?? []) == (prev?.slots ?? [])) { st.tries = 0 }
        let (text, opts) = question(st, q, prev)
        if q.type == "offer" { st.offered = Set(st.offered).union(q.slots ?? []).sorted() }
        q.say = text
        st.pending = q
        var actions: [HerbAction]
        if q.type == "confirm" {
            actions = [.reply("Save"), HerbAction("Edit", .editDraft), .reply("Cancel")]
            if st.frame == "expenses" && (st.data.num("amount") ?? 0) >= 75 { actions.append(HerbAction("Add receipt photo", .open(.receiptScanner))) }
        } else {
            actions = opts.map { HerbAction.reply($0) }
            if hasContent(st) { actions.append(HerbAction("Edit", .editDraft)) }
        }
        let pending = q.brief
        let lead = !soft.isEmpty && q.type != "confirm" ? joinSay(lead, soft) : lead
        var out = HerbReply(intent(st), joinSay(lead, text), actions: actions + extra, followUp: true)
        out.draft = hasContent(st) ? makeDraft(st, pending) : nil
        out.state = st
        out.pending = pending
        return out
    }

    // MARK: Starting

    /// First turn: extract everything from the utterance, then ask for what's missing.
    mutating func start(_ log: String, _ text: String, data: HerbFields = [:], known: [String] = [], meta: HerbFields = [:],
                        chain: HerbChain? = nil, lead: String = "") -> HerbReply {
        var st = HerbDialogState(log: log, data: data, known: known, meta: meta)
        st.chain = chain
        let t = D.clean(text)
        var (upd, got) = extract(st, t)
        if log == "prospects" && D.batch.test(t) {
            upd["firstNames"] = nil
            upd["lastName"] = nil
            got.remove("name")
            got.remove("lastName")
            st.chain = st.chain ?? HerbChain(total: nil, i: 1, saved: 0, defaults: [:], known: [])
        }
        apply(&st, upd, got)
        st.turns = 1
        var lead = lead
        if log == "closings" && lead.isEmpty { lead = st.known.contains("client") ? "Congratulations!" : "" }
        let firstLead = leadFor(st, got, first: true)
        if nextQuestion(&st).type == "confirm" { return respond(&st, lead) }
        return respond(&st, joinSay(lead, firstLead))
    }

    static let updateCue = Rx(#"(?:'s|s')\s+(?:phone|number|cell|mobile|email|address|follow[- ]?up)|\b(?:his|her|their)\s+(?:phone|number|cell|email|address)\b|add (?:a )?note|\bnote (?:for|to|on)\b|\b(?:phone(?: number)?|number|cell|e-?mail|address)\s+(?:is|should be)\b|\bnew (?:phone|number|cell|e-?mail|address) for\b|\b(?:move|change|push|reschedule|set|update)\b.*\bfollow[- ]?up|\bmark\b.*\bas\b|\bupdate\b|\bis (?:now )?(?:red hot|hot|cold|warm|a no go|not interested)\b"#, true)

    /// "I called Priya Shah, not ready yet" / "Kevin Morales's email is …" → an existing prospect to update.
    func matchUpdate(_ t: String) -> ProspectRecord? {
        if rxTest(#"\bnew (?:lead|prospect|client|contact)\b|\bclosed\b|\bfunded\b|\breceipt\b"#, t) { return nil }
        if HerbParse.isQuestion(t) { return nil }
        guard Self.updateCue.test(t) || D.touch.test(t) else { return nil }
        var cands = book.prospectCandidates(t)
        if cands.isEmpty {
            if let src = book.matchSource(t), src.kind == "person" {
                let st = HerbParse.tokens(src.name), tt = HerbParse.tokens(t)
                if st.count > 1 && st.allSatisfy(tt.contains) { return nil }
            }
            let closed = book.closedProspectIDs
            let firsts = book.prospectCandidates(t, firstNameOK: true).filter { !closed.contains($0.prospect.id) }
            if Set(firsts.map(\.prospect.id)).count == 1 { cands = firsts }
        }
        return cands.first?.prospect
    }

    mutating func startUpdate(_ p: ProspectRecord, _ text: String) -> HerbReply {
        let t = D.clean(text)
        let name = p.fullName
        var st = HerbDialogState(log: "prospects", frame: "update",
                                 meta: ["name": .string(name), "existingNotes": HerbValue(p.notes), "strengthWas": HerbValue(p.strength?.rawValue)])
        st.id = p.id
        var (upd, got) = extract(st, t)
        let m = D.touch.search(t)
        if let m {
            let g = m[1]!.lowercased()
            let verb = D.touchVerb.first { g.hasPrefix($0.0) }?.1 ?? "Called"
            var after = t.u16(from: m.end)
            for tok in name.words { after = rxSub("^\\W*\(NSRegularExpression.escapedPattern(for: tok))\\b", after, "") }
            let f = D.followCue.search(after)
            var outcome = (f.map { after.u16(to: $0.start) } ?? after).strip(" ,.;-")
            outcome = rxSub(#"\s*,?\s*(?:and|so)$"#, outcome, "").strip(" ,.")
            upd["_addNote"] = .string("\(monthAbbreviations[now.month - 1]) \(now.day): \(verb)" + (outcome.isEmpty ? "" : " — \(outcome)") + ".")
            upd["_touched"] = true
        }
        apply(&st, upd, got)
        st.turns = 1
        if got.isEmpty && m == nil && st.meta.strings("notes").isEmpty {
            let pending = HerbPending("change")
            st.pending = pending
            var out = HerbReply(.updateProspect, "What would you like to update for \(name) — the phone, email, address, follow-up date, or a note?",
                                actions: [.reply("Follow-up date", "Change the follow-up"), .reply("Add a note")], followUp: true)
            out.state = st
            out.pending = pending
            return out
        }
        return respond(&st)
    }

    // MARK: Saving

    func chainDefaults(_ st: HerbDialogState) -> (HerbFields, [String]) {
        let act = st.data.str("activityId")
        guard let tags = HerbParse.categoryKeywords.map(\.1).first(where: { $0.act == act }) else { return ([:], []) }
        var d = D.tagUpdate(tags)
        if let src = st.data.text("source") ?? (act.map(D.tagFromActivity.contains) == true ? book.latestSource(forActivity: act!) : nil) {
            d["source"] = .string(src)
        }
        return (d, ["source", "relation"])
    }

    func savedSay(_ st: HerbDialogState, _ d: HerbFields) -> String {
        switch st.frame {
        case "prospects":
            return "Saved \(who(st, full: true))." + (d.has("followUp") ? " I'll remind you to follow up \(D.dayText(d.str("followUp"), now: now))." : "")
        case "update": return "Updated \(st.meta.text("name") ?? "")."
        case "closings":
            return st.meta.has("repeat") ? "Saved as income."
                : "Saved — congratulations! It's on your income log, and I'll remind you to ask for a review in 14 days."
        case "expenses": return "Expense saved."
        case "activities": return "Activity saved."
        case "income": return "Income saved."
        default: return "Trip saved."
        }
    }

    mutating func saveNow(_ st: inout HerbDialogState) -> HerbReply {
        let data = finalData(st), log = saveLog(st)
        do { try save(log: log, data: data, id: st.id) } catch {
            return respond(&st, "I couldn't save that: \(error)")
        }
        var out = afterSave(st, data)
        out.saved = log
        return out
    }

    /// What comes next: the leads the user mentioned, the next lead in a batch, or an utterance that was waiting.
    mutating func afterSave(_ st: HerbDialogState, _ data: HerbFields) -> HerbReply {
        let lead = savedSay(st, data)
        let intent = intent(st)
        if st.frame == "activities", let n = st.meta.num("leads").map({ Int($0) }), n != 0 {
            var nst = HerbDialogState(log: "prospects")
            let (defaults, kn) = chainDefaults(st)
            nst.chain = HerbChain(total: n, i: 1, saved: 0, defaults: defaults, known: kn)
            nst.pending = HerbPending("chainOffer")
            let act = Taxonomy.activityByID[st.data.str("activityId") ?? ""]?.name ?? "that"
            var out = HerbReply(intent, "\(lead) You mentioned \(n) lead\(n != 1 ? "s" : "") from \(act) — want to add \(n != 1 ? "them" : "it") now?",
                                actions: [.reply("Yes"), .reply("Later", "Not now")], followUp: true)
            out.state = nst
            out.pending = nst.pending
            return out
        }
        if st.frame == "prospects", var ch = st.chain {
            ch.saved += 1
            if let total = ch.total, ch.i >= total { return thenQueued(st, end(intent, "\(lead) That's all \(total) leads.")) }
            var nst = HerbDialogState(log: "prospects", data: ch.defaults, known: ch.known)
            nst.chain = ch
            nst.chain!.i += 1
            if ch.total != nil { return respond(&nst, lead) }
            nst.pending = HerbPending("next")
            var out = HerbReply(intent, "\(lead) Next lead?", actions: [.reply("Yes"), .reply("That's all")], followUp: true)
            out.state = nst
            out.pending = nst.pending
            return thenQueued(st, out)
        }
        let receipt = st.frame == "expenses" && (data.num("amount") ?? 0) >= 75 ? [HerbAction("Add receipt photo", .open(.receiptScanner))] : []
        return thenQueued(st, end(intent, lead, receipt))
    }

    /// Run an utterance the user said while a draft was waiting ("new prospect …" before saving the last one).
    mutating func thenQueued(_ st: HerbDialogState, _ out: HerbReply) -> HerbReply {
        guard let q = st.queued, !q.isEmpty else { return out }
        var nxt = route(q)
        nxt.say = "\(out.say) \(nxt.say)"
        return nxt
    }

    /// Side questions don't lose the draft (§17.2 rule 8).
    mutating func sideAnswer(_ st: inout HerbDialogState, _ t: String) -> HerbReply? {
        let intent = HerbParse.detectIntent(t)
        if intent.isLog || intent == .unknown || intent == .smalltalk { return nil }
        let r = route(t)
        st.pending = nil
        var q = respond(&st)  // re-ask where we were, with its buttons and the draft card
        q.intent = r.intent
        q.say = "\(r.say) Back to \(who(st, full: true)): \(q.say)"
        q.cards = r.cards
        q.actions += r.actions.filter { if case .open = $0.kind { true } else { false } }
        return q
    }

    /// "Finish later": save what we have, unreviewed, so it waits in the Review queue instead of getting lost.
    mutating func park(_ st: inout HerbDialogState, _ text: String) -> HerbReply {
        let allowed = D.levels(settings.questionStyle), never = Set(settings.neverAsk)
        let slots = D.frames[st.frame] ?? []
        var missing = slots.filter {
            $0.applies(st) && !st.known.contains($0.key) && !st.skipped.contains($0.key)
                && (allowed.contains($0.level) || $0.level == D.required) && !never.contains($0.key)
        }.map(\.key)
        if st.meta.has("sourceUnknown") { missing.append("source") }
        if slots.contains(where: { missing.contains($0.key) && $0.level == D.required }) && !["prospects", "update"].contains(st.frame) {
            return respond(&st, "I need a bit more before I can hold it — or say cancel.")
        }
        st.data["reviewed"] = false
        let labels = joinAnd(missing.filter { $0 != "dup" }.map { D.missingLabel[$0] ?? $0 })
        if !missing.isEmpty { st.meta["notes"] = .list((st.meta["notes"]?.list ?? []) + [.string("HERB: still need \(labels).")]) }
        let data = finalData(st), log = saveLog(st)
        do { try save(log: log, data: data, id: st.id) } catch {
            return respond(&st, "I couldn't hold it: \(error)")
        }
        let say = "Saved to your Review queue" + (missing.isEmpty ? "." : " — I'll ask about \(labels) later.")
            + (text.lowercased().contains("driv") ? " Drive safe." : "")
        var out = end(intent(st), say)
        out.saved = log
        return out
    }

    // MARK: One turn

    mutating func turn(_ state: HerbDialogState, _ text: String) -> HerbReply {
        guard D.frames[state.frame] != nil else { return route(D.clean(text)) }
        var st = state
        var t = D.clean(text)
        let p = st.pending
        let typ = p?.type, k = p?.slot
        let intent = intent(st)
        let between = typ == "next" || typ == "chainOffer"
        st.turns += 1
        if t.isEmpty || D.repeatRx.match(t) != nil {
            if !between { return respond(&st) }
            var out = HerbReply(intent, "Want to add another one?", followUp: true)
            out.state = st
            out.pending = p?.brief
            return out
        }
        if D.cancel.match(t) != nil {
            var say = hasContent(st) && !between ? "Okay, I won't save that." : "Okay."
            if let n = st.chain?.saved, n != 0 { say += " \(n) lead\(n != 1 ? "s" : "") saved." }
            return thenQueued(st, end(intent, say))
        }
        if D.edit.match(t) != nil && hasContent(st) {
            var out = respond(&st, "Opening the form.")
            out.state = nil
            out.openForm = true
            return out
        }
        if D.later.match(t) != nil && hasEntry(st) && !between { return park(&st, t) }

        // batch / chain prompts between records
        if typ == "chainOffer" {
            if D.yes.match(t) != nil, let ch = st.chain {
                var nst = HerbDialogState(log: "prospects", data: ch.defaults, known: ch.known)
                nst.chain = ch
                return respond(&nst)
            }
            return end(intent, "Okay — you can add them from the Log tab any time.")
        }
        if typ == "next" {
            let ch = st.chain
            if D.done.match(t) != nil || D.no.match(t) != nil {
                let n = ch?.saved ?? 0
                return end(.logProspect, "All set — \(n) lead\(n != 1 ? "s" : "") saved.")
            }
            if D.yes.match(t) != nil {
                st.pending = nil
                return respond(&st)
            }
            return start("prospects", t, data: ch?.defaults ?? [:], known: ch?.known ?? [], chain: ch)
        }

        // a new entry while this one waits: finish this one first (§17.2 rule 9)
        if D.newEntry.match(t) != nil {
            if hasEntry(st) {
                st.queued = t
                st.pending = nil
                if nextQuestion(&st).type == "confirm" { return respond(&st, "Sure. Before we start the next one:") }
                return askChange(&st, "Sure. Should I save \(who(st, full: true)) as it is first?", ["Yes", "No"])
            }
            t = D.newEntry.sub(t, "").strip(" ,:")
        }
        if st.frame == "prospects" && k == "name" && st.chain != nil && D.done.match(t) != nil {
            let n = st.chain?.saved ?? 0
            return end(.logProspect, "All set — \(n) lead\(n != 1 ? "s" : "") saved.")
        }
        if typ == "change", let next = st.meta.removeValue(forKey: "noteNext"), next.truthy {
            apply(&st, ["_addNote": .string(t.upperFirst + ".")], [])
            return respond(&st, "Noted.")
        }

        let (upd, got) = extract(st, t, focus: ["value", "choice", "default"].contains(typ ?? "") ? k : nil)
        let isNo = D.no.match(t) != nil, isDone = D.done.match(t) != nil, isYes = D.yes.match(t) != nil

        if typ == "confirm" || typ == "change" {
            if !got.isEmpty || upd["_addNote"] != nil || upd["_tag"] != nil {
                apply(&st, upd, got)
                return respond(&st, got.isEmpty ? "Noted." : "Got it.")
            }
            let isSave = D.save.match(t) != nil
            if isSave && (typ == "confirm" || st.queued != nil) { return saveNow(&st) }
            if typ == "change" && (isSave || isNo) {
                if st.queued != nil { return thenQueued(st, end(intent, "Okay, I won't save it.")) }
                return respond(&st, "Okay.")
            }
            if isNo { return askChange(&st, "What should I change? For example \"the phone is …\" or \"follow up Friday\".") }
            if rxTest(#"\bfollow[- ]?up\b"#, t) && ["prospects", "update"].contains(st.frame) {
                st.queue = ["followUp"]
                st.known.removeAll { $0 == "followUp" }
                st.meta["noDefault"] = true
                st.meta["touched"] = true
                return respond(&st)
            }
            if rxTest(#"^(?:add|write|make) (?:a )?note$"#, t) {
                st.meta["noteNext"] = true
                return askChange(&st, "What's the note?")
            }
            if HerbParse.isQuestion(t), let side = sideAnswer(&st, t) { return side }
            return respond(&st, "Sorry, I didn't catch a change. Say yes to save, or tell me what to change — or say Edit to open the form.")
        }

        if typ == "offer" {
            let S = p?.slots ?? []
            let named = S.filter { D.slotWords[$0]!.test(t) }
            let negated = named.filter { D.slotNeg[$0]!.test(t) }
            let chosen = named.filter { !negated.contains($0) }
            let filled = S.filter(got.contains)
            let neg = isNo || D.negWord.test(t)
            let onlyT = D.only.test(t)
            if !upd.isEmpty { apply(&st, upd, got) }
            if !filled.isEmpty {
                let drop = S.filter { !got.contains($0) }.filter { negated.contains($0) || (onlyT && !chosen.contains($0)) || (neg && chosen.isEmpty) }
                let msg = drop.isEmpty ? nil : decline(&st, drop)
                return respond(&st, msg ?? "", soft: leadFor(st, got))
            }
            if !named.isEmpty {
                let msg = negated.isEmpty ? nil : decline(&st, negated)
                if !chosen.isEmpty {
                    st.queue = chosen
                    if onlyT { _ = decline(&st, S.filter { !named.contains($0) }) }
                }
                return respond(&st, msg ?? (!negated.isEmpty && chosen.isEmpty ? "Okay." : ""))
            }
            if isYes {
                st.queue = S
                return respond(&st)
            }
            if neg { return respond(&st, decline(&st, S) ?? "Okay.") }
            if !got.isEmpty { return respond(&st, soft: leadFor(st, got)) }
            if HerbParse.isQuestion(t), let side = sideAnswer(&st, t) { return side }
            st.tries += 1
            if st.tries < 2 { return respond(&st, "Sorry — you can say yes, no, or just tell me.") }
            _ = decline(&st, S)
            return respond(&st, "I'll skip that for now.")
        }

        // value / choice / default
        if let k, got.contains(k) {
            apply(&st, upd, got)
            if k == "dup" {
                if st.frame == "update" {
                    if st.data.isEmpty && st.meta.strings("notes").isEmpty {
                        return askChange(&st, "Okay — what would you like to update for \(who(st)): the phone, email, address, follow-up date, or a note?")
                    }
                    return respond(&st, "Okay — I'll update the one you have.")
                }
                return respond(&st, "Okay — a new prospect.")
            }
            return respond(&st, soft: leadFor(st, got))
        }
        if typ == "default" && isYes, let k {
            var upd = upd
            if k == "followUp" || k == "income" { upd[k] = p?.value ?? .null }
            apply(&st, upd, got.union([k]))
            return respond(&st, soft: leadFor(st, [k]))
        }
        if typ == "default" && (isNo || rxTest("different|another|pick a day|other", t)) {
            st.meta["noDefault"] = true
            if !upd.isEmpty { apply(&st, upd, got) }
            return respond(&st, "Okay.")
        }
        let required = D.isRequired(st.frame, k)
        if k == "source" && st.frame == "prospects" && (isNo || isDone || D.unknown.test(t)) {
            apply(&st, ["_sourceUnknown": true, "_sourceNew": false], ["source"])
            return respond(&st, "Okay — I'll mark the source unknown and put \(who(st)) in your Review queue so you can fill it in later.")
        }
        if typ == "choice" && rxTest(#"something else|\bother\b|else"#, t) && (k == "category" || k == "activity") && !st.meta.has("elseAsked") {
            st.meta["elseAsked"] = true
            return respond(&st)
        }
        if (isNo || isDone) && got.isEmpty {
            if required { return respond(&st, "I need that one to save it. Or say Edit to use the form, or cancel.") }
            return respond(&st, decline(&st, k.map { [$0] } ?? []) ?? "No problem.")
        }
        if !got.isEmpty {
            apply(&st, upd, got)
            return respond(&st, soft: leadFor(st, got))
        }
        if HerbParse.isQuestion(t), let side = sideAnswer(&st, t) { return side }
        st.tries += 1
        if st.tries < 2 { return respond(&st, k.flatMap { D.retryHint[$0] } ?? "Sorry, I didn't catch that.") }
        if k == "dup" {  // don't block on it: keep it as a new prospect
            apply(&st, ["_dupAnswer": "new"], ["dup"])
            return respond(&st, "I'll keep it as a new prospect.")
        }
        if k == "category" && st.meta.has("elseAsked") {
            apply(&st, ["groupId": "general", "categoryId": "exp.general.office_supplies", "reviewed": false], ["category"])
            return respond(&st, "I'll file it under General for now and put it in your Review queue.")
        }
        if required { return respond(&st, "Let's do this one on the form.") }
        _ = decline(&st, k.map { [$0] } ?? [])
        return respond(&st, "I'll leave that blank — you can add it later.")
    }
}
