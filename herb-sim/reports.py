"""Report builders (design §14, §15). Every report is a list of widgets (see CONTRACT.md)."""
import calendar
from datetime import date

import calc
import db
import herb
import taxonomy as tx
from calc import money, money_k, num, pct, ratio

# ---------------------------------------------------------------- widget helpers


def W(type_, title, **kw):
    d = {"type": type_, "title": title}
    d.update({k: v for k, v in kw.items() if v is not None})
    return d


def col(key, label, align="left", fmt=None):
    c = {"key": key, "label": label, "align": align}
    if fmt:
        c["format"] = fmt
    return c


def stat_item(label, display, caption=None, formula=None):
    d = {"label": label, "display": display}
    if caption:
        d["caption"] = caption
    if formula:
        d["formula"] = formula
    return d


def items(rows, label="name", value="value", fmt=money):
    return [{"label": r[label], "value": r[value] or 0, "display": fmt(r[value] or 0)} for r in rows]


def top(rows, key, n=5, min_value=0):
    return sorted([r for r in rows if (r.get(key) or 0) > min_value], key=lambda r: -(r[key] or 0))[:n]


# ---------------------------------------------------------------- shared blocks


def summary_widgets(led):
    """Page 1 of the annual report — also the monthly and YTD summaries."""
    s = led
    exp_share, prof_share = ratio(s.expenses_total, s.income_total), ratio(s.profit, s.income_total)
    ws = [
        W("stack", "Profit and Loss", span=1, items=[
            {"label": "Profit", "value": max(0, s.profit), "display": f"{money(s.profit)} ({pct(prof_share)})",
             "role": "profit"},
            {"label": "Expenses", "value": s.expenses_total, "display": f"{money(s.expenses_total)} ({pct(exp_share)})",
             "role": "expense"}]),
        W("donut", "Conversion Rate", center=pct(s.conversion), items=[
            {"label": "Closings", "value": s.n_closings, "display": f"{s.n_closings} closings"},
            {"label": "Not yet converted", "value": max(0, s.n_prospects - s.n_closings),
             "display": f"{max(0, s.n_prospects - s.n_closings)} of {s.n_prospects} prospects"}],
          caption=f"{pct(s.conversion)} = {s.n_closings} ÷ {s.n_prospects}"),
        W("stats", "Transaction Summary", items=[
            stat_item("Average closing volume", money(s.avg_volume), formula=f"{money(s.volume)} ÷ {s.n_closings}"),
            stat_item("Average closing income", money(s.avg_closing_income),
                      formula=f"{money(s.closing_income)} ÷ {s.n_closings}")]),
        W("stats", "Efficiency Analysis", items=[
            stat_item("Business-building hours per prospect", num(s.hours_per_prospect, 2),
                      formula=f"{num(s.hours_per_prospect, 2)} = {num(s.bb_hours, 2)} ÷ {s.n_prospects}"),
            stat_item("Business-building hours per closing", num(s.hours_per_closing, 2),
                      formula=f"{num(s.hours_per_closing, 2)} = {num(s.bb_hours, 2)} ÷ {s.n_closings}")]),
        W("stats", "Hourly Rate Analysis", items=[
            stat_item("Based on gross income", money(s.hourly_gross),
                      formula=f"{money(s.income_total)} ÷ {num(s.work_hours)} hours"),
            stat_item("Based on net income", money(s.hourly_net),
                      formula=f"{money(s.profit)} ÷ {num(s.work_hours)} hours")]),
        W("stat", "Volume Closed", value=s.volume, display=money(s.volume), caption=f"{s.n_closings} closings",
          formula=f"Σ transaction size, {led.period.label}"),
        herb.index_widget(led),
    ]
    return ws


def top_performers(led, min_prospects=3):
    rows = []
    for dim, label in (("pillar", "Pillar"), ("category", "Category"), ("source", "Source"),
                       ("activity", "Activity")):
        b = [r for r in led.breakdown(dim) if r["key"] is not None]
        conv = [r for r in b if r["prospects"] >= min_prospects]
        best_conv = max(conv, key=lambda r: r["conversion"] or 0) if conv else None
        best_vol = max(b, key=lambda r: r["volume"]) if b else None
        best_inc = max(b, key=lambda r: r["closingIncome"]) if b else None
        rows.append({"dimension": label,
                     "conversion": f"{best_conv['name']} ({pct(best_conv['conversion'])})" if best_conv else "—",
                     "volume": f"{best_vol['name']} ({money_k(best_vol['volume'])})" if best_vol and best_vol["volume"] else "—",
                     "income": f"{best_inc['name']} ({money(best_inc['closingIncome'])})" if best_inc and best_inc["closingIncome"] else "—"})
    return W("table", "Top Performers", span=3, columns=[
        col("dimension", ""), col("conversion", "Best conversion"), col("volume", "Most volume closed"),
        col("income", "Most income earned")], rows=rows,
        note=f"Conversion leaders need at least {min_prospects} prospects.")


def monthly_averages(led):
    m = led.months_in_use
    metrics = [("Prospects", led.n_prospects, lambda v: num(v, 1)), ("Closings", led.n_closings, lambda v: num(v, 1)),
               ("Volume", led.volume, money), ("Income", led.income_total, money),
               ("Expenses", led.expenses_total, money), ("Profit", led.profit, money),
               ("Business-building hours", led.bb_hours, lambda v: num(v, 1))]
    return W("table", "Monthly Averages", columns=[col("metric", "Metric"), col("total", "Total", "right"),
                                                   col("avg", f"Per month ({m} months in use)", "right")],
             rows=[{"metric": n, "total": f(v), "avg": f(v / m)} for n, v, f in metrics])


def input_output(led):
    ms = led.by_month()
    return W("columns", "Input to Output", span=3,
             series=[{"name": "Business-building hours"}, {"name": "Prospects"}, {"name": "Closings"},
                     {"name": "Income ($k)"}],
             items=[{"label": r["label"], "values": [round(r["bbHours"], 1), r["prospects"], r["closings"],
                                                     round(r["income"] / 1000, 1)],
                     "displays": [num(r["bbHours"], 1), str(r["prospects"]), str(r["closings"]), money_k(r["income"])]}
                    for r in ms])


def pillar_pie(led, measure, title, fmt=lambda v: str(int(v))):
    rows = led.breakdown("pillar")
    total = sum(r[measure] for r in rows) or 1
    return W("pie", title, items=[{"label": r["name"], "value": r[measure],
                                   "display": f"{fmt(r[measure])} ({pct(r[measure] / total)})"} for r in rows])


# ---------------------------------------------------------------- log reports

LOG_COLUMNS = {
    "prospects": [col("date", "Date"), col("name", "Name"), col("phone1", "Phone"), col("pillarName", "Pillar"),
                  col("categoryName", "Category"), col("sourceName", "Source"), col("activityName", "Activity"),
                  col("strengthName", "Strength"), col("plan_of_action", "Plan of action"),
                  col("follow_up", "Follow-up")],
    "closings": [col("date", "Date"), col("name", "Name"), col("pillarName", "Pillar"),
                 col("categoryName", "Category"), col("sourceName", "Source"), col("activityName", "Activity"),
                 col("transaction_size", "Transaction size", "right", "money"),
                 col("income", "Income", "right", "money")],
    "income": [col("date", "Date"), col("modeName", "Kind"), col("name", "Name / type"), col("payer", "Payer"),
               col("transaction_count", "# trans.", "right", "num"),
               col("transaction_size", "Transaction size", "right", "money"),
               col("amount", "Income", "right", "money")],
    "expenses": [col("date", "Date"), col("vendor", "Vendor"), col("groupName", "Group"),
                 col("categoryName", "Category"), col("irs", "IRS category"), col("receipt", "Receipt"),
                 col("amount", "Amount", "right", "money")],
    "trips": [col("date", "Date"), col("reason", "Reason"), col("destination", "Destination"),
              col("odometer_start", "Begin", "right", "num1"), col("odometer_end", "End", "right", "num1"),
              col("miles", "Miles", "right", "num1"), col("businessName", "Use"),
              col("deduction", "Deduction", "right", "money")],
    "activities": [col("date", "Date"), col("pillarName", "Pillar"), col("activityName", "Activity"),
                   col("sourceName", "With"), col("minutes", "Minutes", "right", "num"),
                   col("hours", "Hours", "right", "num1")],
}
LOG_TITLES = {"prospects": "Prospects Log", "closings": "Closings Log", "income": "Income Log",
              "expenses": "Expense Log", "trips": "Mileage Log", "activities": "Activity Log"}


def decorate(conn, log, rows):
    """Add the display fields the UI and reports need (names instead of IDs)."""
    srcs = {r["id"]: r["name"] for r in conn.execute("SELECT id, name FROM sources")}
    pros = {}
    if log == "closings":
        pros = {r["id"]: r for r in db.rows(conn.execute("SELECT id, first_names, last_name FROM prospects"))}
    out = []
    for r in rows:
        r = dict(r)
        r["sourceName"] = srcs.get(r.get("source_id"))
        if "category_id" in r and log != "expenses":
            r["categoryName"] = tx.CATEGORY_BY_ID.get(r.get("category_id"), {}).get("name")
        if "activity_id" in r:
            r["activityName"] = tx.ACTIVITY_BY_ID.get(r.get("activity_id"), {}).get("name")
        if "pillar" in r:
            r["pillarName"] = tx.pillar_name(r.get("pillar"))
        if log == "prospects":
            r["name"] = f"{r['first_names'] or ''} {r['last_name'] or ''}".strip()
            r["strengthName"] = tx.STRENGTH_NAME.get(r.get("strength"), "")
        elif log == "closings":
            p = pros.get(r.get("prospect_id"), {})
            r["name"] = f"{p.get('first_names', '')} {p.get('last_name', '')}".strip()
        elif log == "income":
            r["modeName"] = {"transaction": "Transaction", "batch": "Batch", "type": "By type"}.get(r["mode"], r["mode"])
            r["typeName"] = tx.INCOME_TYPE_NAME.get(r.get("type"), "")
            r["name"] = r.get("last_name") if r["mode"] == "transaction" else r["typeName"]
            r["avgPerTransaction"] = ratio(r["amount"], r.get("transaction_count")) if r["mode"] == "batch" else None
        elif log == "expenses":
            meta = tx.EXPENSE_CATEGORY_BY_ID.get(r.get("category_id"), {})
            r["categoryName"] = meta.get("name")
            r["irs"] = meta.get("irs")
            r["groupName"] = tx.EXPENSE_GROUP_NAME.get(r.get("group_id"))
            r["receipt"] = "✓" if r.get("has_receipt") else ("Missing" if (r.get("amount") or 0) >= 75 else "—")
        elif log == "trips":
            r["miles"] = calc.trip_miles(r)
            r["deduction"] = r["miles"] * tx.mileage_rate(r["date"]) if r["is_business"] else 0.0
            r["rate"] = tx.mileage_rate(r["date"])
            r["businessName"] = "Business" if r["is_business"] else "Personal"
        elif log == "activities":
            r["hours"] = (r.get("minutes") or 0) / 60
        out.append(r)
    return out


def log_totals(log, rows):
    t = {"count": len(rows)}
    if log == "closings":
        t.update(volume=sum(r["transaction_size"] or 0 for r in rows), income=sum(r["income"] or 0 for r in rows))
    elif log in ("income", "expenses"):
        t["amount"] = sum(r["amount"] or 0 for r in rows)
    elif log == "trips":
        t.update(miles=sum(r["miles"] for r in rows if r["is_business"]),
                 deduction=sum(r["deduction"] for r in rows))
    elif log == "activities":
        t.update(minutes=sum(r["minutes"] or 0 for r in rows), hours=sum(r["minutes"] or 0 for r in rows) / 60)
    return t


def log_widget(conn, led, log):
    rows = {"prospects": led.prospects, "closings": led.closings, "income": led.income, "expenses": led.expenses,
            "trips": led.trips, "activities": led.activities}[log]
    rows = decorate(conn, log, sorted(rows, key=lambda r: (r["date"], r["id"]), reverse=True))
    totals = log_totals(log, rows)
    total_row = {"date": f"{totals['count']} entries"}
    for k in ("volume", "income", "amount", "miles", "deduction", "minutes", "hours"):
        if k in totals:
            total_row[{"volume": "transaction_size"}.get(k, k)] = totals[k]
    return W("table", LOG_TITLES[log], span=3, columns=LOG_COLUMNS[log], rows=rows, total=total_row)


# ---------------------------------------------------------------- detailed reports


def r_prospects(conn, led):
    pil = led.breakdown("pillar")
    cats = led.breakdown("category")
    acts = led.breakdown("activity")
    srcs = led.breakdown("source")
    strength = {}
    for p in led.prospects:
        strength[p["strength"]] = strength.get(p["strength"], 0) + 1
    tp = max(pil, key=lambda r: r["prospects"]) if pil else None
    return [
        W("stats", "Prospects", items=[
            stat_item("Prospects", str(led.n_prospects), caption=led.period.label),
            stat_item("Conversion", pct(led.conversion), formula=f"{led.n_closings} ÷ {led.n_prospects}"),
            stat_item("Hours per prospect", num(led.hours_per_prospect, 2),
                      formula=f"{num(led.bb_hours, 1)} ÷ {led.n_prospects}"),
            stat_item("Top pillar", tp["name"] if tp else "—",
                      caption=f"{tp['prospects']} prospects" if tp else None)]),
        pillar_pie(led, "prospects", "Prospects by Pillar"),
        W("pie", "Strength of Contact", items=[{"label": tx.STRENGTH_NAME[k], "value": strength.get(k, 0),
                                                "display": str(strength.get(k, 0))} for k, _, _ in tx.STRENGTH]),
        W("bar", "Top 5 Categories", horizontal=True,
          items=[{"label": r["name"], "value": r["prospects"], "display": str(r["prospects"])} for r in
                 top(cats, "prospects")]),
        W("bar", "Top 5 Activities", horizontal=True,
          items=[{"label": r["name"], "value": r["prospects"], "display": str(r["prospects"])} for r in
                 top(acts, "prospects")]),
        W("table", "Top Sources", columns=[col("name", "Source"), col("prospects", "Prospects", "right", "num"),
                                           col("share", "Share", "right", "pct")],
          rows=[{"name": r["name"], "prospects": r["prospects"], "share": ratio(r["prospects"], led.n_prospects)}
                for r in top(srcs, "prospects", 8)]),
        W("table", "Prospects by Category", span=2,
          columns=[col("name", "Category"), col("pillarName", "Pillar"), col("prospects", "Prospects", "right", "num"),
                   col("share", "% of total", "right", "pct")],
          rows=[{"name": r["name"], "pillarName": tx.pillar_name(r.get("pillar")), "prospects": r["prospects"],
                 "share": ratio(r["prospects"], led.n_prospects)} for r in cats if r["prospects"]]),
        W("columns", "Prospects by Month", span=3, series=[{"name": "Prospects"}],
          items=[{"label": m["label"], "values": [m["prospects"]], "displays": [str(m["prospects"])]}
                 for m in led.by_month()]),
    ]


def r_closings(conn, led):
    pil = led.breakdown("pillar")
    cats = [r for r in led.breakdown("category") if r["closings"]]
    acts = [r for r in led.breakdown("activity") if r["closings"]]
    return [
        W("stats", "Closings", items=[
            stat_item("Closings", str(led.n_closings), caption=led.period.label),
            stat_item("Volume", money(led.volume)),
            stat_item("Closing income", money(led.closing_income)),
            stat_item("Average closing volume", money(led.avg_volume), formula=f"{money(led.volume)} ÷ {led.n_closings}"),
            stat_item("Average closing income", money(led.avg_closing_income),
                      formula=f"{money(led.closing_income)} ÷ {led.n_closings}")]),
        pillar_pie(led, "closings", "Share by Quantity"),
        pillar_pie(led, "volume", "Share by Volume", money_k),
        pillar_pie(led, "closingIncome", "Share by Income", money),
        W("bar", "Average Volume per Closing by Pillar",
          items=[{"label": r["name"], "value": r["avgVolume"] or 0, "display": money_k(r["avgVolume"])} for r in pil]),
        W("table", "Closings by Category", span=2,
          columns=[col("name", "Category"), col("closings", "Closings", "right", "num"),
                   col("volume", "Volume", "right", "money"), col("closingIncome", "Income", "right", "money"),
                   col("avgVolume", "Avg volume", "right", "money"), col("avgIncome", "Avg income", "right", "money")],
          rows=sorted(cats, key=lambda r: -r["closingIncome"])),
        W("table", "Top 5 Activities by Closings", span=3,
          columns=[col("name", "Activity"), col("closings", "Closings", "right", "num"),
                   col("volume", "Volume", "right", "money"), col("closingIncome", "Income", "right", "money")],
          rows=top(acts, "closings")),
    ]


def conv_rows(rows):
    return sorted([r for r in rows if r["prospects"]], key=lambda r: (-(r["conversion"] or 0), -r["closings"]))


CONV_COLS = lambda label: [col("name", label), col("prospects", "Prospects", "right", "num"),
                           col("closings", "Closings", "right", "num"), col("conversion", "Conversion", "right", "pct")]


def r_conversion(conn, led):
    pil = led.breakdown("pillar")
    cats = conv_rows(led.breakdown("category"))
    acts = conv_rows(led.breakdown("activity"))
    none = [r for r in cats + acts if r["closings"] == 0]
    return [
        W("stat", "Overall Conversion", value=led.conversion, display=pct(led.conversion),
          caption=f"{led.n_closings} closings from {led.n_prospects} prospects",
          formula=f"{pct(led.conversion)} = {led.n_closings} ÷ {led.n_prospects}"),
        W("bar", "Conversion by Pillar",
          items=[{"label": r["name"], "value": r["conversion"] or 0, "display": pct(r["conversion"])} for r in pil]),
        W("bar", "Top 5 Categories by Conversion", horizontal=True,
          items=[{"label": r["name"], "value": r["conversion"] or 0, "display": pct(r["conversion"])}
                 for r in [c for c in cats if c["prospects"] >= 3][:5]]),
        W("table", "Categories, best to worst", span=2, columns=CONV_COLS("Category"),
          rows=[r for r in cats if r["closings"]]),
        W("table", "Activities, best to worst", span=2, columns=CONV_COLS("Activity"),
          rows=[r for r in acts if r["closings"]]),
        W("list", "No conversion yet", span=1, items=[
            {"title": r["name"], "text": f"{r['prospects']} prospects, 0 closings",
             "level": "concern" if r["prospects"] >= 4 else "watch"}
            for r in sorted(none, key=lambda r: -r["prospects"])]),
    ]


def r_source_conversion(conn, led):
    srcs = led.breakdown("source")
    conv = conv_rows([r for r in srcs if r["closings"]])
    none = sorted([r for r in srcs if r["prospects"] and not r["closings"]], key=lambda r: -r["prospects"])
    cols = CONV_COLS("Source") + [col("closingIncome", "Income", "right", "money"),
                                  col("expenses", "Spent", "right", "money")]
    return [
        W("bar", "Top Sources by Income", horizontal=True,
          items=[{"label": r["name"], "value": r["closingIncome"], "display": money(r["closingIncome"])}
                 for r in top(srcs, "closingIncome", 6)]),
        W("table", "Sources with Conversion", span=2, columns=cols, rows=conv),
        W("table", "Sources with No Conversion", span=3, columns=cols, rows=none,
          note="A source sending 4–5 prospects that never convert: time to move on, or coach the source."),
    ]


def r_income(conn, led):
    cats = led.breakdown("category")
    acts = led.breakdown("activity")
    pil = led.breakdown("pillar")
    tr = calc.plan_tracking(conn, led.period.to.year)
    by_type = {}
    for i in led.income:
        if i["mode"] != "transaction":
            k = tx.INCOME_TYPE_NAME.get(i["type"], "Other") + (" (batch)" if i["mode"] == "batch" else "")
            by_type[k] = by_type.get(k, 0) + i["amount"]
    return [
        W("stats", "Income", items=[
            stat_item("Total income", money(led.income_total), caption=led.period.label),
            stat_item("From closings", money(led.closing_income), caption=f"{led.n_closings} closings"),
            stat_item("Non-transaction income", money(led.nontrans_income)),
            stat_item("Projected annual income", money(tr["forecast"]["value"]),
                      formula="YTD + open pipeline + recent run rate")]),
        W("bar", "Top 5 Categories by Income", horizontal=True, items=items(top(cats, "income"), value="income")),
        W("bar", "Top 5 Activities by Income", horizontal=True, items=items(top(acts, "income"), value="income")),
        W("table", "Income per Closing by Pillar", columns=[
            col("name", "Pillar"), col("closings", "Closings", "right", "num"), col("income", "Income", "right", "money"),
            col("avgIncome", "Per closing", "right", "money")], rows=pil),
        W("table", "Non-transaction Income", columns=[col("type", "Type"), col("amount", "Amount", "right", "money")],
          rows=[{"type": k, "amount": v} for k, v in sorted(by_type.items(), key=lambda kv: -kv[1])]),
        W("columns", "Income by Month", span=3, series=[{"name": "Income"}],
          items=[{"label": m["label"], "values": [round(m["income"])], "displays": [money_k(m["income"])]}
                 for m in led.by_month()]),
    ]


def expense_groups(led):
    out = {}
    for e in led.expenses:
        out[e["group_id"]] = out.get(e["group_id"], 0) + (e["amount"] or 0)
    return out


def irs_totals(led):
    out = {k: 0.0 for k in tx.IRS_CATEGORIES}
    for e in led.expenses:
        out[tx.EXPENSE_CATEGORY_BY_ID.get(e["category_id"], {}).get("irs", "Other")] += e["amount"] or 0
    out["Car & Truck"] += led.mileage_deduction
    return out


def r_expenses(conn, led):
    groups = expense_groups(led)
    total_cash = led.cash_expenses or 1
    irs = irs_totals(led)
    cats = {}
    for e in led.expenses:
        cats[e["category_id"]] = cats.get(e["category_id"], 0) + e["amount"]
    missing = [e for e in decorate(conn, "expenses", led.expenses) if e["amount"] >= 75 and not e["has_receipt"]]
    return [
        W("stats", "Expenses", items=[
            stat_item("Total expenses", money(led.expenses_total), caption=led.period.label),
            stat_item("Cash expenses", money(led.cash_expenses)),
            stat_item("Mileage deduction", money(led.mileage_deduction)),
            stat_item("Share of income", pct(ratio(led.expenses_total, led.income_total)),
                      formula=f"{money(led.expenses_total)} ÷ {money(led.income_total)}")]),
        W("pie", "Expenses by Group", items=[
            {"label": tx.EXPENSE_GROUP_NAME[g], "value": v, "display": f"{money(v)} ({pct(v / total_cash)})"}
            for g, v in sorted(groups.items(), key=lambda kv: -kv[1])]),
        W("table", "By IRS Category", columns=[col("irs", "IRS category"), col("amount", "Amount", "right", "money")],
          rows=[{"irs": k, "amount": v} for k, v in irs.items() if v]),
        W("table", "Top Specific Categories", columns=[col("group", "Group"), col("name", "Category"),
                                                       col("irs", "IRS"), col("amount", "Amount", "right", "money")],
          rows=[{"group": tx.EXPENSE_GROUP_NAME[tx.EXPENSE_CATEGORY_BY_ID[k]["group"]],
                 "name": tx.EXPENSE_CATEGORY_BY_ID[k]["name"], "irs": tx.EXPENSE_CATEGORY_BY_ID[k]["irs"], "amount": v}
                for k, v in sorted(cats.items(), key=lambda kv: -kv[1])[:12] if k in tx.EXPENSE_CATEGORY_BY_ID]),
        W("table", "Receipts Missing ($75 or more)", columns=[col("date", "Date"), col("vendor", "Vendor"),
                                                             col("categoryName", "Category"),
                                                             col("amount", "Amount", "right", "money")],
          rows=missing, note="IRS documentary-evidence threshold. Snap these so they hold up in an audit."),
        W("columns", "Expenses by Month", span=3, series=[{"name": "Expenses"}],
          items=[{"label": m["label"], "values": [round(m["expenses"])], "displays": [money_k(m["expenses"])]}
                 for m in led.by_month()]),
    ]


def r_mileage(conn, led):
    rate_rows = []
    for start, end, rate in tx.MILEAGE_RATES:
        miles = sum(calc.trip_miles(t) for t in led.business_trips if start.isoformat() <= t["date"] <= end.isoformat())
        if miles:
            rate_rows.append({"period": f"{start:%b %d} – {end:%b %d, %Y}", "miles": miles, "rate": rate,
                              "deduction": miles * rate, "formula": f"{num(miles, 1)} mi × ${rate:.3f}"})
    dests = {}
    for t in led.business_trips:
        dests[t["destination"]] = dests.get(t["destination"], 0) + calc.trip_miles(t)
    m = led.months_in_use
    return [
        W("stats", "Mileage", items=[
            stat_item("Business miles", num(led.business_miles), caption=led.period.label),
            stat_item("Deduction", money(led.mileage_deduction), formula="miles × IRS rate by trip date"),
            stat_item("Average miles per month", num(led.business_miles / m), formula=f"÷ {m} months in use"),
            stat_item("Estimated hours in the car", num(led.business_miles / 60, 1), formula="miles ÷ 60")]),
        W("table", "Deduction by Rate Period", columns=[
            col("period", "Period"), col("miles", "Miles", "right", "num1"), col("rate", "Rate", "right"),
            col("deduction", "Deduction", "right", "money"), col("formula", "Math")], rows=rate_rows,
          note="The IRS raised the 2026 rate mid-year (72.5¢ Jan–Jun, 76¢ Jul–Dec); each trip uses its date's rate."),
        W("bar", "Top Destinations (miles)", horizontal=True,
          items=[{"label": k, "value": v, "display": num(v)} for k, v in sorted(dests.items(), key=lambda kv: -kv[1])[:8]]),
        W("columns", "Miles by Month", span=3, series=[{"name": "Business miles"}],
          items=[{"label": r["label"], "values": [round(r["miles"])], "displays": [num(r["miles"])]}
                 for r in led.by_month()]),
    ]


def r_activity(conn, led):
    acts = [r for r in led.breakdown("activity") if r["hours"]]
    total = led.bb_hours or 1
    return [
        W("stats", "Business-building Time", items=[
            stat_item("Hours", num(led.bb_hours, 1), caption=led.period.label),
            stat_item("Hours per week", num(led.bb_hours_per_week, 1)),
            stat_item("Income per hour", money(led.income_per_bb_hour),
                      formula=f"{money(led.income_total)} ÷ {num(led.bb_hours, 1)} h")]),
        pillar_pie(led, "hours", "Hours by Pillar", lambda v: f"{v:.1f} h"),
        W("bar", "Hours by Activity", horizontal=True,
          items=[{"label": r["name"], "value": r["hours"], "display": f"{r['hours']:.1f} h"}
                 for r in sorted(acts, key=lambda r: -r["hours"])[:10]]),
        W("bar", "Income per Hour by Activity (top 5)", horizontal=True,
          items=[{"label": r["name"], "value": r["incomePerHour"] or 0, "display": money(r["incomePerHour"])}
                 for r in top(acts, "incomePerHour")]),
        W("table", "Activity Detail", span=3, columns=[
            col("name", "Activity"), col("hours", "Hours", "right", "num1"),
            col("share", "% of time", "right", "pct"), col("prospects", "Prospects", "right", "num"),
            col("closings", "Closings", "right", "num"), col("income", "Income", "right", "money"),
            col("incomePerHour", "$ / hour", "right", "money")],
          rows=[dict(r, share=r["hours"] / total) for r in sorted(acts, key=lambda r: -r["hours"])]),
    ]


def r_efficiency(conn, led):
    pil = led.breakdown("pillar")
    rows = []
    for r in pil:
        exp = r["expenses"]
        rows.append(dict(r, profitPerHour=ratio(r["income"] - exp, r["hours"])))
    rows.append({"name": "Overall", "hoursPerProspect": led.hours_per_prospect, "hoursPerClosing": led.hours_per_closing,
                 "incomePerHour": led.income_per_bb_hour, "profitPerHour": led.profit_per_bb_hour,
                 "hours": led.bb_hours, "prospects": led.n_prospects, "closings": led.n_closings})
    best = min([r for r in rows[:-1] if r["hoursPerClosing"]], key=lambda r: r["hoursPerClosing"], default=None)
    return [
        W("table", "Efficiency by Pillar", span=3, columns=[
            col("name", "Pillar"), col("hours", "Hours", "right", "num1"),
            col("hoursPerProspect", "Hours / prospect", "right", "num1"),
            col("hoursPerClosing", "Hours / closing", "right", "num1"),
            col("incomePerHour", "Gross $ / hour", "right", "money"),
            col("profitPerHour", "Profit $ / hour", "right", "money")], rows=rows,
          note=("Lower hours per prospect and per closing is better." +
                (f" Most efficient: {best['name']}." if best else ""))),
        W("bar", "Hours per Prospect", items=[{"label": r["name"], "value": r["hoursPerProspect"] or 0,
                                               "display": num(r["hoursPerProspect"], 1)} for r in rows[:-1]]),
        W("bar", "Hours per Closing", items=[{"label": r["name"], "value": r["hoursPerClosing"] or 0,
                                              "display": num(r["hoursPerClosing"], 1)} for r in rows[:-1]]),
        W("stats", "Standard Hourly Rates", items=[
            stat_item("Gross", money(led.hourly_gross), formula=f"{money(led.income_total)} ÷ {num(led.work_hours)} work hours"),
            stat_item("Net", money(led.hourly_net), formula=f"{money(led.profit)} ÷ {num(led.work_hours)} work hours"),
            stat_item("Business-building hours per week", num(led.bb_hours_per_week, 1))]),
    ]


IRS_LINES = [("Advertising", "8"), ("Car & Truck", "9"), ("Commissions/Fees", "10"), ("Insurance", "15"),
             ("Interest-Other", "16b"), ("Legal/Professional", "17"), ("Office", "18"), ("Rent", "20b"),
             ("Repairs", "21"), ("Supplies", "22"), ("Taxes", "23"), ("Travel", "24a"),
             ("Meals/Entertainment", "24b"), ("Utilities", "25"), ("Wages", "26"), ("Other", "27a")]


def r_pnl(conn, led):
    irs = irs_totals(led)
    other = {}
    for e in led.expenses:
        meta = tx.EXPENSE_CATEGORY_BY_ID.get(e["category_id"], {})
        if meta.get("irs") == "Other":
            other[meta["name"]] = other.get(meta["name"], 0) + e["amount"]
    rows = [{"line": ln, "name": n, "amount": irs.get(n, 0)} for n, ln in IRS_LINES]
    return [
        W("stats", "Profit & Loss (Schedule C format)", items=[
            stat_item("Gross receipts", money(led.income_total)),
            stat_item("Total expenses", money(led.expenses_total)),
            stat_item("Net profit", money(led.profit), formula=f"{money(led.income_total)} − {money(led.expenses_total)}")]),
        W("table", "Expenses by Line", span=2, columns=[col("line", "Line"), col("name", "Expense"),
                                                        col("amount", "Amount", "right", "money")],
          rows=rows, total={"name": "Total expenses", "amount": led.expenses_total},
          note="Car & Truck uses the standard mileage deduction. Meals are shown in full; generally 50% is deductible "
               "— confirm treatment with your CPA."),
        W("table", "Statement 1 — Other Expenses", columns=[col("name", "Item"), col("amount", "Amount", "right", "money")],
          rows=[{"name": k, "amount": v} for k, v in sorted(other.items(), key=lambda kv: -kv[1])],
          total={"name": "Total other", "amount": sum(other.values())}),
    ]


def r_profit_roi(conn, led):
    rows = led.pillar_roi()
    pil = [r for r in rows if r["key"] not in ("overhead", "total")]
    return [
        W("stack", "Profit and Loss", items=[
            {"label": "Profit", "value": max(0, led.profit), "display": f"{money(led.profit)} ({pct(led.margin)})",
             "role": "profit"},
            {"label": "Expenses", "value": led.expenses_total,
             "display": f"{money(led.expenses_total)} ({pct(ratio(led.expenses_total, led.income_total))})",
             "role": "expense"}]),
        W("stats", "Profit", items=[
            stat_item("Net profit", money(led.profit), formula=f"{money(led.income_total)} − {money(led.expenses_total)}"),
            stat_item("Profit margin", pct(led.margin, 1)),
            stat_item("Net ROI (with time)", pct(led.net_roi), formula="(income − capital) ÷ capital")]),
        W("pie", "Profit by Pillar", items=[{"label": r["name"], "value": max(0, r["profit"]),
                                             "display": money(r["profit"])} for r in pil]),
        W("table", "ROI by Pillar — money only", span=3, columns=[
            col("name", "Pillar"), col("income", "Income", "right", "money"), col("expenses", "Expenses", "right", "money"),
            col("profit", "Profit", "right", "money"), col("margin", "Margin", "right", "pct"),
            col("roi", "ROI", "right", "num1")], rows=rows),
        W("table", "ROI by Pillar — time and money", span=3, columns=[
            col("name", "Pillar"), col("hours", "Hours", "right", "num1"), col("wages", "Wages invested", "right", "money"),
            col("capital", "Capital", "right", "money"), col("profitWithTime", "Profit", "right", "money"),
            col("roiWithTime", "ROI", "right", "num1"), col("label", "")], rows=rows,
          note=f"Wages invested = business-building hours × your gross hourly rate ({money(led.hourly_gross)}). "
               "Overhead (General, Self-Improvement, Technology, Travel and mileage) is included in the total."),
        W("columns", "Income, Expenses and Profit by Pillar", span=3,
          series=[{"name": "Income"}, {"name": "Expenses"}, {"name": "Profit"}],
          items=[{"label": r["name"], "values": [round(r["income"]), round(r["expenses"]), round(r["profit"])],
                  "displays": [money_k(r["income"]), money_k(r["expenses"]), money_k(r["profit"])]} for r in pil]),
    ]


def r_relationships_ads(conn, led):
    sp = {r["key"]: r for r in led.breakdown("sub_pillar")}
    hg = led.hourly_gross or 0
    keys = ["personal", "professional", "internet", "traditional"]
    metrics = [("Prospects", "prospects", lambda v: num(v)), ("Closings", "closings", lambda v: num(v)),
               ("Conversion", "conversion", pct), ("Volume", "volume", money_k), ("Income", "income", money),
               ("Hours", "hours", lambda v: num(v, 1)), ("Estimated wages", "wages", money),
               ("Expenses", "expenses", money), ("Profit", "profit", money)]
    for k in keys:
        r = sp.get(k) or {}
        r["wages"] = (r.get("hours") or 0) * hg
        r["profit"] = (r.get("income") or 0) - r["wages"] - (r.get("expenses") or 0)
        sp[k] = r
    rows = [dict({"metric": label}, **{k: f(sp[k].get(key)) for k in keys}) for label, key, f in metrics]
    return [W("table", "Relationships & Advertising", span=3, columns=[
        col("metric", ""), col("personal", "Personal", "right"), col("professional", "Professional", "right"),
        col("internet", "Internet", "right"), col("traditional", "Traditional", "right")], rows=rows,
        note="Profit = income − estimated wages (hours × gross hourly rate) − expenses."),
        W("columns", "Income vs Cost", span=3, series=[{"name": "Income"}, {"name": "Wages + expenses"}],
          items=[{"label": tx.sub_pillar_name(k).split("– ")[-1],
                  "values": [round(sp[k].get("income") or 0), round(sp[k]["wages"] + (sp[k].get("expenses") or 0))],
                  "displays": [money_k(sp[k].get("income") or 0), money_k(sp[k]["wages"] + (sp[k].get("expenses") or 0))]}
                 for k in keys])]


def r_overall(conn, led):
    return [monthly_averages(led), W("stats", "Totals", items=[
        stat_item("Prospects", str(led.n_prospects)), stat_item("Closings", str(led.n_closings)),
        stat_item("Volume", money(led.volume)), stat_item("Income", money(led.income_total)),
        stat_item("Expenses", money(led.expenses_total)), stat_item("Profit", money(led.profit))])]


def r_coaching(conn, led):
    ins = herb.insights(conn)
    guidance = [
        "Overall numbers: income, expenses, profit, conversion and hours per prospect and per closing are the "
        "foundation of next year's plan.",
        "Conversion: watch any category or activity with 2–3 prospects and no closings; 4 or more with none is a "
        "concern. Notice sources that send prospects who never convert.",
        "Closings and income: keep working where you close, and look at the pillars with the biggest average deal "
        "and the most income per closing.",
        "Activities: lower hours per prospect and per closing is better — move hours from inefficient pillars to "
        "the ones that close with less time.",
        "Profit and ROI: look for the pillars with the highest return on the time and money you invest.",
    ]
    return [W("list", "HERB's coaching for you", span=2,
              items=[{"title": i["title"], "text": i["text"], "level": i["level"]} for i in ins[:10]]),
            W("text", "How to read your numbers", paragraphs=guidance)]


def r_business_plan(conn, led):
    year = led.period.to.year
    tr = calc.plan_tracking(conn, year)
    p = calc.plan_json(conn, year)
    o = p["outputs"]
    ms = calc.Ledger(conn, calc.Period("year", str(year), date(year, 1, 1), date(year, 12, 31))).by_month()
    rows = [{"month": m["label"], "income": m["income"], "planIncome": o["monthlyGross"], "profit": m["profit"],
             "planProfit": o["monthlyNet"], "closings": m["closings"], "planClosings": o["monthlyTransactions"],
             "volume": m["volume"], "planVolume": o["monthlyVolume"]} for m in ms]
    ytd = calc.ledger(conn, "ytd") if year == calc.today().year else led
    return [
        W("progress", "Business Plan Progress", span=3, items=[
            {"label": i["label"], "actual": i["actual"], "projected": i["projected"], "goal": i["goal"],
             "displayActual": i["display"]["actual"], "displayProjected": i["display"]["projected"],
             "displayGoal": i["display"]["goal"], "pct": i["pacePct"]} for i in tr["items"]]),
        W("table", "Month by Month", span=3, columns=[
            col("month", "Month"), col("income", "Income", "right", "money"), col("planIncome", "Plan", "right", "money"),
            col("profit", "Profit", "right", "money"), col("planProfit", "Plan", "right", "money"),
            col("closings", "Closings", "right", "num"), col("planClosings", "Plan", "right", "num1"),
            col("volume", "Volume", "right", "money"), col("planVolume", "Plan", "right", "money")], rows=rows),
        W("stats", "Hourly Rates", items=[
            stat_item("Projected gross", money(o["hourlyGross"]),
                      formula=f"{money(p['inputs']['grossIncomeGoal'])} ÷ {num(o['annualWorkHours'])} h"),
            stat_item("Actual gross", money(ytd.hourly_gross), caption=f"{pct(ratio(ytd.hourly_gross, o['hourlyGross']))} of plan"),
            stat_item("Projected net", money(o["hourlyNet"])),
            stat_item("Actual net", money(ytd.hourly_net), caption=f"{pct(ratio(ytd.hourly_net, o['hourlyNet']))} of plan")]),
        W("stat", "Year-end Forecast", value=tr["forecast"]["value"], display=money(tr["forecast"]["value"]),
          caption=f"Goal {money(p['inputs']['grossIncomeGoal'])}",
          formula=f"{money(tr['forecast']['ytd'])} YTD + {money(tr['forecast']['pipeline'])} pipeline + "
                  f"{money(tr['forecast']['runRate'])} run rate"),
    ]


def r_index(conn, led):
    w = herb.index_widget(led)
    trend = calc.index_trend(conn, led.period.to.year)
    return [w, W("bar", "Index by Month (year to date through each month)",
                 items=[{"label": t["label"], "value": t["value"] or 0, "display": num(t["value"])} for t in trend]),
            W("text", "How the index works", paragraphs=[
                "Logsperity Index = 100 × [(0.5 × Net ROI + profit margin) ÷ 2.5 + conversion rate].",
                "100 is a healthy business: 30% conversion, 200% net ROI and 75% of gross income kept. Below 100 is "
                "weaker; above 100 is stronger.",
                f"Yours: 100 × [(0.5 × {num(led.net_roi, 2)} + {num(led.margin, 2)}) ÷ 2.5 + {num(led.conversion, 2)}] "
                f"= {num(led.index, 1)}."])]


def r_summary(conn, led):
    return summary_widgets(led)


def r_month(conn, led):
    if led.period.frm > calc.today():
        return [W("text", led.period.label, paragraphs=["This month hasn't started yet."])]
    prev = calc.Ledger(conn, calc.previous_period(led.period))
    change = []
    for label, a, b, f in [("Prospects", led.n_prospects, prev.n_prospects, num),
                           ("Closings", led.n_closings, prev.n_closings, num),
                           ("Income", led.income_total, prev.income_total, money),
                           ("Expenses", led.expenses_total, prev.expenses_total, money),
                           ("Business-building hours", led.bb_hours, prev.bb_hours, lambda v: num(v, 1)),
                           ("Business miles", led.business_miles, prev.business_miles, num)]:
        change.append({"metric": label, "this": f(a), "prev": f(b), "change": f"{'+' if a - b >= 0 else '−'}{f(abs(a - b))}"})
    return summary_widgets(led) + [W("table", f"Compared with {prev.period.label}", span=3, columns=[
        col("metric", "Metric"), col("this", led.period.label, "right"), col("prev", prev.period.label, "right"),
        col("change", "Change", "right")], rows=change)]


# ---------------------------------------------------------------- quick stats


def q_prospects(conn, led):
    return r_prospects(conn, led)[:2]


def q_closings(conn, led):
    return r_closings(conn, led)[:2]


def q_profit(conn, led):
    return r_profit_roi(conn, led)[:2]


def q_current_month(conn, led):
    return summary_widgets(calc.ledger(conn, "month"))


def q_annual_ytd(conn, led):
    return summary_widgets(calc.ledger(conn, "ytd"))


def q_streamlined(conn, led):
    l2 = calc.ledger(conn, "ytd")
    return summary_widgets(l2)[:6] + r_business_plan(conn, l2)[:1] + [top_performers(l2)]


# ---------------------------------------------------------------- annual report (§15.2)


def annual_pages(conn, year, version="complete"):
    now = calc.today()
    if version == "ytd" or year == now.year:
        period = calc.Period("ytd", f"{year} year to date", date(year, 1, 1), min(date(year, 12, 31), now))
    else:
        period = calc.parse_period(f"year:{year}")
    led = calc.Ledger(conn, period)
    pages = [
        {"title": f"{year} Complete Report — Summary", "widgets": summary_widgets(led)},
        {"title": "Business Plan Progress Tracker", "widgets": r_business_plan(conn, led)[:1] + r_business_plan(conn, led)[2:]},
        {"title": "Monthly Averages and Top Performers", "widgets": [monthly_averages(led), top_performers(led)]},
        {"title": "Input to Output", "widgets": [input_output(led)]},
        {"title": f"{year} Prospects Report", "widgets": r_prospects(conn, led)},
        {"title": f"{year} Closings Report", "widgets": r_closings(conn, led)},
        {"title": f"{year} Income Report", "widgets": r_income(conn, led)},
        {"title": f"{year} Conversion Rate Report", "widgets": r_conversion(conn, led)},
        {"title": "Source Conversion", "widgets": r_source_conversion(conn, led)},
        {"title": f"{year} Mileage Report", "widgets": r_mileage(conn, led)},
        {"title": f"{year} Profit & Loss", "widgets": r_pnl(conn, led)},
        {"title": "ROI by Pillar", "widgets": r_profit_roi(conn, led)},
        {"title": "Logsperity Index", "widgets": r_index(conn, led)},
        {"title": "Coaching Advice", "widgets": r_coaching(conn, led)},
        {"title": "HERB's Year in Review", "widgets": [year_in_review(conn, led)]},
    ]
    if version == "streamlined":
        keep = {0, 1, 2, 12, 13, 14}
        pages = [p for i, p in enumerate(pages) if i in keep]
        pages[0]["title"] = f"{year} Streamlined Report — Summary"
    title = {"complete": f"{year} Complete Annual Report", "streamlined": f"{year} Streamlined Annual Report",
             "ytd": f"{year} Annual Report — Year to Date"}[version]
    return {"title": title, "period": period.json(), "pages": pages}


def year_in_review(conn, led):
    ins = herb.insights(conn)
    wins = [i for i in ins if i["level"] == "win"][:2]
    concerns = [i for i in ins if i["level"] in ("concern", "watch")][:3]
    pil = [r for r in led.breakdown("pillar") if r["prospects"]]
    best = max(pil, key=lambda r: r["conversion"] or 0) if pil else None
    paras = [f"You logged {led.n_prospects} prospects and {led.n_closings} closings for {money(led.income_total)} of "
             f"income and {money(led.profit)} of profit ({pct(led.margin)} margin). Your Logsperity Index is "
             f"{num(led.index)}."]
    if best:
        paras.append(f"What worked: {best['name']} converted best at {pct(best['conversion'])}. " +
                     " ".join(w["text"] for w in wins))
    if concerns:
        paras.append("What didn't: " + " ".join(c["text"] for c in concerns))
    f = herb.focus(conn)
    paras.append("For next year's plan: " + "; ".join(i["title"] for i in f["items"]) +
                 (f"; and drop {f['drop']['title']}." if f.get("drop") else "."))
    return W("text", "HERB's Year in Review", span=3, paragraphs=paras)


# ---------------------------------------------------------------- registry and menu


def _log(log):
    return lambda conn, led: [log_widget(conn, led, log)]


def _all_logs(conn, led):
    return [log_widget(conn, led, k) for k in LOG_TITLES]


def _annual(version):
    def build(conn, led):
        rep = annual_pages(conn, led.period.to.year, version)
        out = []
        for p in rep["pages"]:
            out.append(W("text", p["title"], span=3, paragraphs=[], page=True))
            out.extend(p["widgets"])
        return out
    return build


REPORTS = {
    "log_prospects": ("Prospects Log", _log("prospects")), "log_closings": ("Closings Log", _log("closings")),
    "log_income": ("Income Log", _log("income")), "log_expenses": ("Expense Log", _log("expenses")),
    "log_trips": ("Mileage Log", _log("trips")), "log_activities": ("Activity Log", _log("activities")),
    "log_all": ("All Logs", _all_logs),
    "quick_prospects": ("Prospects", q_prospects), "quick_closings": ("Closings", q_closings),
    "quick_profit": ("Profit", q_profit), "quick_current_month": ("Current Month", q_current_month),
    "quick_annual_ytd": ("Annual Report YTD", q_annual_ytd),
    "quick_annual_streamlined": ("Annual Report Streamlined", q_streamlined),
    "prospects": ("Prospects Report", r_prospects), "conversion": ("Conversion Rate Report", r_conversion),
    "source_conversion": ("Source Conversion Report", r_source_conversion),
    "closings": ("Closings Report", r_closings), "income": ("Income Report", r_income),
    "expenses": ("Expense Report", r_expenses), "mileage": ("Mileage Report", r_mileage),
    "activity": ("Activity Report", r_activity), "efficiency": ("Efficiency Analysis", r_efficiency),
    "input_output": ("Input-to-Output Report", lambda conn, led: [input_output(led)]),
    "pnl": ("Profit & Loss (traditional)", r_pnl), "profit_roi": ("Profit & ROI Report", r_profit_roi),
    "relationships_ads": ("Relationships & Ads Report", r_relationships_ads),
    "overall_stats": ("Basic Overall Stats", r_overall), "coaching_advice": ("Coaching Advice", r_coaching),
    "business_plan": ("Business Plan Report", r_business_plan), "index": ("Logsperity Index", r_index),
    "annual_ytd": ("Annual Report YTD", _annual("ytd")),
    "annual_streamlined": ("Annual Report Streamlined", _annual("streamlined")),
    "annual_complete": ("Annual Report Complete", _annual("complete")),
    "ytd": ("Year to Date Report", r_summary),
}
for _m in range(1, 13):
    REPORTS[f"month_{_m:02d}"] = (f"{calendar.month_name[_m]} Report", r_month)
REPORT_TITLES = {k: v[0] for k, v in REPORTS.items()}

MENU = {"groups": [
    {"id": "logs", "title": "Logs", "items": [{"key": k, "title": REPORT_TITLES[k]} for k in
                                               ("log_prospects", "log_closings", "log_income", "log_expenses",
                                                "log_trips", "log_activities", "log_all")]},
    {"id": "quick", "title": "Quick Stats", "items": [{"key": k, "title": REPORT_TITLES[k]} for k in
                                                      ("quick_prospects", "quick_closings", "quick_profit",
                                                       "quick_current_month", "quick_annual_ytd",
                                                       "quick_annual_streamlined")]},
    {"id": "detailed", "title": "Detailed Reports", "items": [{"key": k, "title": REPORT_TITLES[k]} for k in
                                                              ("prospects", "conversion", "source_conversion",
                                                               "closings", "income", "expenses", "mileage",
                                                               "activity", "efficiency", "input_output", "pnl",
                                                               "profit_roi", "relationships_ads", "overall_stats",
                                                               "coaching_advice", "business_plan", "index",
                                                               "annual_ytd", "annual_streamlined", "annual_complete")]},
    {"id": "monthly", "title": "Monthly & YTD", "items": [{"key": f"month_{m:02d}", "title": calendar.month_name[m]}
                                                          for m in range(1, 13)] + [{"key": "ytd", "title": "Year to Date"}]},
]}


def build(conn, key, period_key=None):
    if key not in REPORTS:
        raise KeyError(key)
    title, fn = REPORTS[key]
    if key.startswith("month_"):
        y = calc.today().year
        if period_key and period_key.startswith("year:"):
            y = int(period_key[5:])
        period_key = f"month:{y}-{key[6:]}"
    elif key in ("ytd", "quick_annual_ytd", "quick_annual_streamlined", "annual_ytd"):
        period_key = "ytd"
    led = calc.ledger(conn, period_key or "ytd")
    return {"key": key, "title": title, "period": led.period.json(), "widgets": fn(conn, led)}
