"""Logsperity calculation engine (design §9.2, §11, §12, §13).

Every number HERB says or a report shows comes from here. No HTTP code.
"""
import calendar
import os
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta

import db
import taxonomy as tx

# Probability a prospect closes, by strength (used for forecasts and focus).
STRENGTH_PROBABILITY = {"red_hot": 0.6, "hot": 0.4, "medium": 0.2, "cold": 0.08, "no_go": 0.0}
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def today():
    v = os.environ.get("SIM_TODAY")
    return date.fromisoformat(v) if v else date.today()


# ---------------------------------------------------------------- formatting

def money(x, cents=False):
    if x is None:
        return "—"
    neg = x < 0
    s = f"${abs(x):,.2f}" if cents else f"${abs(x):,.0f}"
    return "-" + s if neg else s


def money_k(x):
    if x is None:
        return "—"
    if abs(x) >= 1_000_000:
        return f"${x / 1_000_000:.2f}M"
    if abs(x) >= 10_000:
        return f"${x / 1000:.1f}k"
    return money(x)


def pct(x, d=0):
    return "—" if x is None else f"{x * 100:.{d}f}%"


def num(x, d=0):
    if x is None:
        return "—"
    return f"{x:,.{d}f}"


def hours(x):
    return "—" if x is None else f"{x:,.1f} h"


def ratio(a, b):
    return a / b if b else None


# ---------------------------------------------------------------- periods

@dataclass
class Period:
    key: str
    label: str
    frm: date
    to: date

    def json(self):
        return {"key": self.key, "label": self.label, "from": self.frm.isoformat(), "to": self.to.isoformat()}

    @property
    def days(self):
        return (self.to - self.frm).days + 1


def month_end(y, m):
    return date(y, m, calendar.monthrange(y, m)[1])


def parse_period(key=None, now=None):
    now = now or today()
    key = (key or "ytd").strip()
    try:
        if key == "ytd":
            return Period(key, f"{now.year} year to date", date(now.year, 1, 1), now)
        if key == "month":
            return Period(key, f"{calendar.month_name[now.month]} {now.year} to date", date(now.year, now.month, 1), now)
        if key == "last30":
            return Period(key, "Last 30 days", now - timedelta(days=29), now)
        if key.startswith("month:"):
            y, m = map(int, key[6:].split("-"))
            return Period(key, f"{calendar.month_name[m]} {y}", date(y, m, 1), month_end(y, m))
        if key.startswith("q:"):
            y, q = map(int, key[2:].split("-"))
            m0 = 3 * (q - 1) + 1
            return Period(key, f"Q{q} {y}", date(y, m0, 1), month_end(y, m0 + 2))
        if key.startswith("year:"):
            y = int(key[5:])
            return Period(key, str(y), date(y, 1, 1), date(y, 12, 31))
        if key.startswith("custom:"):
            _, a, b = key.split(":")
            fa, fb = date.fromisoformat(a), date.fromisoformat(b)
            if fb < fa:
                fa, fb = fb, fa
            return Period(key, f"{fa:%b %d, %Y} – {fb:%b %d, %Y}", fa, fb)
    except (ValueError, IndexError):
        pass
    raise ValueError(f"Unknown period '{key}'")


def previous_period(p):
    """Same-length period immediately before p (months map to the previous month)."""
    if p.key.startswith("month:") or p.key == "month":
        first = p.frm
        prev_last = first - timedelta(days=1)
        return Period(f"month:{prev_last:%Y-%m}", f"{calendar.month_name[prev_last.month]} {prev_last.year}",
                      date(prev_last.year, prev_last.month, 1), prev_last)
    to = p.frm - timedelta(days=1)
    return Period("custom", "Previous period", to - timedelta(days=p.days - 1), to)


def same_period_last_year(p):
    def back(d):
        try:
            return d.replace(year=d.year - 1)
        except ValueError:
            return d.replace(year=d.year - 1, day=28)
    return Period("custom", f"Same period {p.frm.year - 1}", back(p.frm), back(p.to))


# ---------------------------------------------------------------- business plan (§9.2)

DEFAULT_PLAN = {"grossIncomeGoal": 150000, "netProfitGoal": 125000, "avgCommission": 6500,
                "avgTransactionSize": 335000, "hoursPerWeek": 40, "vacationWeeks": 0}
PLAN_COLS = {"grossIncomeGoal": "gross_income_goal", "netProfitGoal": "net_profit_goal",
             "avgCommission": "avg_commission", "avgTransactionSize": "avg_transaction_size",
             "hoursPerWeek": "hours_per_week", "vacationWeeks": "vacation_weeks"}


def plan_outputs(i):
    gross, net = float(i["grossIncomeGoal"]), float(i["netProfitGoal"])
    comm, size = float(i["avgCommission"]), float(i["avgTransactionSize"])
    hpw, vac = float(i["hoursPerWeek"]), float(i["vacationWeeks"])
    tx_year = ratio(gross, comm) or 0
    work_hours = (52 - vac) * hpw
    return {
        "monthlyGross": gross / 12,
        "monthlyNet": net / 12,
        "annualExpenses": gross - net,
        "monthlyExpenses": (gross - net) / 12,
        "yieldPct": ratio(comm, size) or 0,
        "annualTransactions": tx_year,
        "monthlyTransactions": tx_year / 12,
        "annualVolume": tx_year * size,
        "monthlyVolume": tx_year * size / 12,
        "annualWorkHours": work_hours,
        "hourlyGross": ratio(gross, work_hours) or 0,
        "hourlyNet": ratio(net, work_hours) or 0,
    }


def get_plan(conn, year):
    r = conn.execute("SELECT * FROM plans WHERE year = ?", (year,)).fetchone()
    if not r:
        return dict(DEFAULT_PLAN)
    return {k: r[c] for k, c in PLAN_COLS.items()}


def save_plan(conn, year, inputs):
    cur = get_plan(conn, year)
    for k in PLAN_COLS:
        if k in inputs and inputs[k] not in (None, ""):
            cur[k] = float(inputs[k])
    if cur["netProfitGoal"] > cur["grossIncomeGoal"]:
        raise ValueError("Net profit goal can't be larger than the gross income goal")
    conn.execute("INSERT OR REPLACE INTO plans(year, gross_income_goal, net_profit_goal, avg_commission, "
                 "avg_transaction_size, hours_per_week, vacation_weeks) VALUES(?,?,?,?,?,?,?)",
                 (year, *[cur[k] for k in PLAN_COLS]))
    conn.commit()
    return cur


def plan_extended(conn, year, outputs, inputs):
    """§9.3: continue the chain past transactions using the user's own YTD rates."""
    led = Ledger(conn, parse_period(f"year:{year}") if year != today().year else parse_period("ytd"))
    conv = led.conversion
    hpp = led.hours_per_prospect
    weeks = max(1, 52 - float(inputs.get("vacationWeeks") or 0))
    prospects_needed = ratio(outputs["annualTransactions"], conv) if conv else None
    bb = prospects_needed * hpp if (prospects_needed and hpp) else None
    return {"conversion": conv, "prospectsNeeded": prospects_needed,
            "prospectsPerWeek": prospects_needed / weeks if prospects_needed else None,
            "hoursPerProspect": hpp, "bbHoursNeeded": bb, "bbHoursPerWeek": bb / weeks if bb else None}


def plan_json(conn, year):
    inputs = get_plan(conn, year)
    outputs = plan_outputs(inputs)
    return {"year": year, "inputs": inputs, "outputs": outputs, "extended": plan_extended(conn, year, outputs, inputs)}


def elapsed_fraction(year, now=None):
    now = now or today()
    if year < now.year:
        return 1.0
    if year > now.year:
        return 0.0
    start = date(year, 1, 1)
    days = 366 if calendar.isleap(year) else 365
    return ((now - start).days + 1) / days


# ---------------------------------------------------------------- the ledger

def trip_miles(t):
    if t.get("gps_miles") is not None:
        return float(t["gps_miles"])
    s, e = t.get("odometer_start"), t.get("odometer_end")
    if s is None or e is None:
        return 0.0
    return max(0.0, float(e) - float(s))


def expense_pillar(e):
    return tx.EXPENSE_GROUP_PILLAR.get(e.get("group_id"))


def expense_sub_pillar(e):
    g = e.get("group_id")
    return {"clients": "clients", "ad_internet": "internet", "ad_traditional": "traditional",
            "prospecting": "prospecting"}.get(g) or (e.get("relationship_sub_pillar") if g == "relationships" else None)


class Ledger:
    """All six logs for one period, with the §11 metrics as properties."""

    def __init__(self, conn, period, now=None):
        self.conn = conn
        self.period = period
        self.now = now or today()
        f, t = period.frm.isoformat(), period.to.isoformat()

        def q(table):
            return db.rows(conn.execute(f"SELECT * FROM {table} WHERE date BETWEEN ? AND ? ORDER BY date, id", (f, t)))

        self.prospects = q("prospects")
        self.closings = q("closings")
        self.income = q("income")
        self.expenses = q("expenses")
        self.trips = q("trips")
        self.activities = q("activities")
        self.source_names = {r["id"]: r["name"] for r in conn.execute("SELECT id, name FROM sources")}
        self.plan = get_plan(conn, period.to.year)
        self.plan_out = plan_outputs(self.plan)

    # ---- counts and totals (§11.2)
    @property
    def n_prospects(self):
        return len(self.prospects)

    @property
    def n_closings(self):
        return len(self.closings)

    @property
    def volume(self):
        return sum(c["transaction_size"] or 0 for c in self.closings)

    @property
    def closing_income(self):
        return sum(c["income"] or 0 for c in self.closings)

    @property
    def income_total(self):
        return sum(i["amount"] or 0 for i in self.income)

    @property
    def nontrans_income(self):
        return sum(i["amount"] or 0 for i in self.income if i["mode"] != "transaction")

    @property
    def cash_expenses(self):
        return sum(e["amount"] or 0 for e in self.expenses)

    @property
    def business_trips(self):
        return [t for t in self.trips if t["is_business"]]

    @property
    def business_miles(self):
        return sum(trip_miles(t) for t in self.business_trips)

    @property
    def mileage_deduction(self):
        return sum(trip_miles(t) * tx.mileage_rate(t["date"]) for t in self.business_trips)

    @property
    def expenses_total(self):
        return self.cash_expenses + self.mileage_deduction

    @property
    def bb_hours(self):
        return sum(a["minutes"] or 0 for a in self.activities) / 60

    @property
    def work_hours(self):
        """Total work hours from the plan, pro-rated to the part of the period up to today."""
        end = min(self.period.to, self.now)
        if end < self.period.frm:
            return 0.0
        days = (end - self.period.frm).days + 1
        year_days = 366 if calendar.isleap(self.period.frm.year) else 365
        return self.plan_out["annualWorkHours"] * days / year_days

    # ---- conversion and efficiency (§11.3, §11.4)
    @property
    def conversion(self):
        return ratio(self.n_closings, self.n_prospects)

    @property
    def avg_volume(self):
        return ratio(self.volume, self.n_closings)

    @property
    def avg_closing_income(self):
        return ratio(self.closing_income, self.n_closings)

    @property
    def hours_per_prospect(self):
        return ratio(self.bb_hours, self.n_prospects)

    @property
    def hours_per_closing(self):
        return ratio(self.bb_hours, self.n_closings)

    @property
    def profit(self):
        return self.income_total - self.expenses_total

    @property
    def margin(self):
        return ratio(self.profit, self.income_total)

    @property
    def hourly_gross(self):
        return ratio(self.income_total, self.work_hours)

    @property
    def hourly_net(self):
        return ratio(self.profit, self.work_hours)

    @property
    def income_per_bb_hour(self):
        return ratio(self.income_total, self.bb_hours)

    @property
    def profit_per_bb_hour(self):
        return ratio(self.profit, self.bb_hours)

    @property
    def bb_hours_per_week(self):
        end = min(self.period.to, self.now)
        weeks = max(1 / 7, ((end - self.period.frm).days + 1) / 7)
        return self.bb_hours / weeks

    # ---- profit and ROI (§11.5)
    @property
    def wages_invested(self):
        return self.bb_hours * (self.hourly_gross or 0)

    @property
    def net_roi(self):
        capital = self.expenses_total + self.wages_invested
        return ratio(self.income_total - capital, capital)

    @property
    def index(self):
        return logsperity_index(self.net_roi, self.margin, self.conversion)

    # ---- breakdowns
    def name_for(self, dim, key):
        if key is None:
            return "Unassigned"
        if dim == "pillar":
            return tx.pillar_name(key)
        if dim == "sub_pillar":
            return tx.sub_pillar_name(key)
        if dim == "category":
            return tx.CATEGORY_BY_ID.get(key, {}).get("name", key)
        if dim == "activity":
            return tx.ACTIVITY_BY_ID.get(key, {}).get("name", key)
        if dim == "source":
            return self.source_names.get(key, "Unknown")
        return str(key)

    _FIELD = {"pillar": "pillar", "sub_pillar": "sub_pillar", "category": "category_id",
              "activity": "activity_id", "source": "source_id"}

    def breakdown(self, dim):
        """Per-item prospects, closings, conversion, volume, income, hours, expenses for one dimension."""
        f = self._FIELD[dim]
        acc = defaultdict(lambda: defaultdict(float))
        for p in self.prospects:
            acc[p[f]]["prospects"] += 1
        for c in self.closings:
            a = acc[c[f]]
            a["closings"] += 1
            a["volume"] += c["transaction_size"] or 0
            a["closingIncome"] += c["income"] or 0
        for i in self.income:
            if i.get(f) is not None:
                acc[i[f]]["income"] += i["amount"] or 0
        if dim in ("pillar", "sub_pillar", "activity", "source"):
            for a in self.activities:
                acc[a[f]]["hours"] += (a["minutes"] or 0) / 60
        if dim == "pillar":
            for e in self.expenses:
                acc[expense_pillar(e)]["expenses"] += e["amount"] or 0
        elif dim == "sub_pillar":
            for e in self.expenses:
                sp = expense_sub_pillar(e)
                if sp:
                    acc[sp]["expenses"] += e["amount"] or 0
        elif dim == "source":
            for e in self.expenses:
                if e.get("source_id"):
                    acc[e["source_id"]]["expenses"] += e["amount"] or 0
        out = []
        for key, a in acc.items():
            if dim == "pillar" and key is None:
                continue  # overhead expenses are reported separately
            row = {"key": key, "name": self.name_for(dim, key)}
            for k in ("prospects", "closings", "volume", "closingIncome", "income", "hours", "expenses"):
                row[k] = a.get(k, 0.0)
            row["prospects"], row["closings"] = int(row["prospects"]), int(row["closings"])
            row["conversion"] = ratio(row["closings"], row["prospects"])
            row["avgVolume"] = ratio(row["volume"], row["closings"])
            row["avgIncome"] = ratio(row["closingIncome"], row["closings"])
            row["incomePerHour"] = ratio(row["income"], row["hours"])
            row["hoursPerProspect"] = ratio(row["hours"], row["prospects"])
            row["hoursPerClosing"] = ratio(row["hours"], row["closings"])
            if dim == "category":
                row["pillar"] = tx.CATEGORY_BY_ID.get(key, {}).get("pillar")
            if dim == "activity":
                row["pillar"] = tx.ACTIVITY_BY_ID.get(key, {}).get("pillar")
            out.append(row)
        order = {k: i for i, (k, _) in enumerate(tx.PILLARS)}
        if dim == "pillar":
            for k, _ in tx.PILLARS:  # always show all four pillars
                if k not in {r["key"] for r in out}:
                    out.append(self._empty_row(dim, k))
            out.sort(key=lambda r: order.get(r["key"], 9))
        elif dim == "sub_pillar":
            for k, _, _ in tx.SUB_PILLARS:
                if k not in {r["key"] for r in out}:
                    out.append(self._empty_row(dim, k))
            sorder = {k: i for i, (k, _, _) in enumerate(tx.SUB_PILLARS)}
            out = [r for r in out if r["key"] is not None]
            out.sort(key=lambda r: sorder.get(r["key"], 9))
        else:
            out.sort(key=lambda r: (-r["prospects"], -r["closings"], r["name"]))
        return out

    def _empty_row(self, dim, key):
        r = {"key": key, "name": self.name_for(dim, key), "prospects": 0, "closings": 0, "volume": 0.0,
             "closingIncome": 0.0, "income": 0.0, "hours": 0.0, "expenses": 0.0}
        for k in ("conversion", "avgVolume", "avgIncome", "incomePerHour", "hoursPerProspect", "hoursPerClosing"):
            r[k] = None
        return r

    @property
    def overhead_expenses(self):
        cash = sum(e["amount"] or 0 for e in self.expenses if expense_pillar(e) is None)
        return cash + self.mileage_deduction

    def pillar_roi(self):
        """§11.5 per pillar plus an overhead row and the overall total."""
        hg = self.hourly_gross or 0
        rows = []
        for r in self.breakdown("pillar"):
            inc, exp, hrs = r["income"], r["expenses"], r["hours"]
            wages = hrs * hg
            capital = exp + wages
            rows.append({"key": r["key"], "name": r["name"], "income": inc, "expenses": exp,
                         "profit": inc - exp, "margin": ratio(inc - exp, inc),
                         "roi": ratio(inc - exp, exp), "hours": hrs, "wages": wages, "capital": capital,
                         "profitWithTime": inc - capital, "roiWithTime": ratio(inc - capital, capital)})
        unattributed = self.income_total - sum(r["income"] for r in rows)
        oh = self.overhead_expenses
        rows.append({"key": "overhead", "name": "Overhead & unassigned income", "income": unattributed,
                     "expenses": oh, "profit": unattributed - oh, "margin": None, "roi": None, "hours": 0.0,
                     "wages": 0.0, "capital": oh, "profitWithTime": unattributed - oh, "roiWithTime": None})
        ranked = [r for r in rows if r["key"] != "overhead" and r["roiWithTime"] is not None]
        if len(ranked) >= 2:
            best = max(ranked, key=lambda r: r["roiWithTime"])
            worst = min(ranked, key=lambda r: r["roiWithTime"])
            for r in rows:
                r["label"] = "Best" if r is best else "Worst" if r is worst else ""
        total_capital = self.expenses_total + self.wages_invested
        rows.append({"key": "total", "name": "Total", "income": self.income_total, "expenses": self.expenses_total,
                     "profit": self.profit, "margin": self.margin,
                     "roi": ratio(self.profit, self.expenses_total), "hours": self.bb_hours,
                     "wages": self.wages_invested, "capital": total_capital,
                     "profitWithTime": self.income_total - total_capital, "roiWithTime": self.net_roi, "label": ""})
        return rows

    # ---- time series
    def months(self):
        """Month starts covered by the period (clipped to today for current periods)."""
        end = min(self.period.to, max(self.now, self.period.frm))
        out, y, m = [], self.period.frm.year, self.period.frm.month
        while date(y, m, 1) <= end:
            out.append((y, m))
            m += 1
            if m == 13:
                y, m = y + 1, 1
        return out

    def by_month(self):
        rows = []
        for y, m in self.months():
            key = f"{y}-{m:02d}"
            sel = lambda lst: [r for r in lst if r["date"].startswith(key)]
            pr, cl, inc, ex, tr, ac = (sel(self.prospects), sel(self.closings), sel(self.income),
                                       sel(self.expenses), sel(self.trips), sel(self.activities))
            miles = sum(trip_miles(t) for t in tr if t["is_business"])
            ded = sum(trip_miles(t) * tx.mileage_rate(t["date"]) for t in tr if t["is_business"])
            income = sum(i["amount"] or 0 for i in inc)
            expenses = sum(e["amount"] or 0 for e in ex) + ded
            rows.append({"month": key, "label": MONTHS[m - 1], "prospects": len(pr), "closings": len(cl),
                         "volume": sum(c["transaction_size"] or 0 for c in cl), "income": income,
                         "expenses": expenses, "profit": income - expenses, "miles": miles, "deduction": ded,
                         "bbHours": sum(a["minutes"] or 0 for a in ac) / 60})
        return rows

    @property
    def months_in_use(self):
        ms = self.by_month()
        used = [i for i, r in enumerate(ms) if r["prospects"] or r["closings"] or r["income"] or r["expenses"]
                or r["bbHours"]]
        return (len(ms) - used[0]) if used else max(1, len(ms))

    def summary(self):
        return {
            "prospects": self.n_prospects, "closings": self.n_closings, "conversion": self.conversion,
            "volume": self.volume, "closingIncome": self.closing_income, "income": self.income_total,
            "nonTransactionIncome": self.nontrans_income, "cashExpenses": self.cash_expenses,
            "mileageDeduction": self.mileage_deduction, "expenses": self.expenses_total, "profit": self.profit,
            "margin": self.margin, "businessMiles": self.business_miles, "bbHours": self.bb_hours,
            "workHours": self.work_hours, "avgVolume": self.avg_volume, "avgClosingIncome": self.avg_closing_income,
            "hoursPerProspect": self.hours_per_prospect, "hoursPerClosing": self.hours_per_closing,
            "hourlyGross": self.hourly_gross, "hourlyNet": self.hourly_net, "netRoi": self.net_roi,
            "index": self.index,
        }


def ledger(conn, period_key="ytd"):
    return Ledger(conn, parse_period(period_key))


# ---------------------------------------------------------------- index (§12)

def logsperity_index(net_roi, margin, conversion):
    """100 × [(0.5 × Net ROI + margin) ÷ 2.5 + conversion]; 100 = healthy (200% ROI, 75% kept, 30% conversion)."""
    if net_roi is None or margin is None or conversion is None:
        return None
    return 100 * ((0.5 * net_roi + margin) / 2.5 + conversion)


INDEX_BENCHMARKS = {"conversion": 0.30, "netRoi": 2.0, "margin": 0.75}


def index_trend(conn, year, now=None):
    """Index for YTD-through-each-month (cumulative, so it's stable)."""
    now = now or today()
    out = []
    for m in range(1, 13):
        end = month_end(year, m)
        if date(year, m, 1) > now:
            break
        p = Period("custom", MONTHS[m - 1], date(year, 1, 1), min(end, now))
        led = Ledger(conn, p, now)
        out.append({"month": f"{year}-{m:02d}", "label": MONTHS[m - 1], "value": led.index})
    return out


# ---------------------------------------------------------------- plan tracking (§11.6)

def plan_tracking(conn, year=None, now=None):
    now = now or today()
    year = year or now.year
    inputs = get_plan(conn, year)
    out = plan_outputs(inputs)
    frac = elapsed_fraction(year, now)
    led = Ledger(conn, Period("ytd", str(year), date(year, 1, 1), min(date(year, 12, 31), now)), now)
    goals = {"income": inputs["grossIncomeGoal"], "profit": inputs["netProfitGoal"],
             "closings": out["annualTransactions"], "volume": out["annualVolume"]}
    actual = {"income": led.income_total, "profit": led.profit, "closings": led.n_closings, "volume": led.volume}
    labels = {"income": "Income", "profit": "Profit", "closings": "Transactions", "volume": "Volume"}
    fmt = {"income": money, "profit": money, "closings": lambda v: num(v, 1 if v % 1 else 0), "volume": money_k}
    items = []
    for k in ("income", "profit", "closings", "volume"):
        proj = goals[k] * frac
        items.append({"key": k, "label": labels[k], "actual": actual[k], "projected": proj, "goal": goals[k],
                      "pacePct": ratio(actual[k], proj),
                      "display": {"actual": fmt[k](actual[k]), "projected": fmt[k](proj), "goal": fmt[k](goals[k])}})
    return {"year": year, "elapsedFraction": frac, "items": items, "forecast": forecast_income(conn, led, now)}


def forecast_income(conn, led, now=None):
    """Year-end forecast = YTD + open pipeline (by strength) + half of the trailing 8-week run rate."""
    now = now or today()
    year_end = date(now.year, 12, 31)
    remaining_days = max(0, (year_end - now).days)
    avg_inc = led.avg_closing_income or led.plan["avgCommission"]
    open_p = db.rows(conn.execute(
        "SELECT p.strength FROM prospects p LEFT JOIN closings c ON c.prospect_id = p.id "
        "WHERE c.id IS NULL AND p.date >= ?", ((now - timedelta(days=120)).isoformat(),)))
    pipeline = sum(STRENGTH_PROBABILITY.get(p["strength"], 0.1) for p in open_p) * avg_inc * 0.5
    recent = Ledger(conn, Period("custom", "8w", now - timedelta(days=55), now), now).income_total
    run = recent / 56 * remaining_days * 0.5
    return {"value": led.income_total + pipeline + run, "ytd": led.income_total, "pipeline": pipeline,
            "runRate": run}


# ---------------------------------------------------------------- scorecards (§13)

def scorecard(conn, log, measure, dimension, period_key="ytd"):
    """Generic pivot: rows = items of `dimension`, columns = months, value = `measure`."""
    led = ledger(conn, period_key)
    data = {"prospects": led.prospects, "closings": led.closings, "income": led.income,
            "expenses": led.expenses, "activities": led.activities}[log]
    months = [f"{y}-{m:02d}" for y, m in led.months()]
    field = {"pillar": "pillar", "sub_pillar": "sub_pillar", "category": "category_id",
             "activity": "activity_id", "source": "source_id", "irs": None, "group": "group_id",
             "type": "type"}[dimension]

    def value(r):
        return {"quantity": 1, "income": r.get("income") if log == "closings" else r.get("amount"),
                "volume": r.get("transaction_size"), "amount": r.get("amount"),
                "minutes": r.get("minutes")}[measure] or 0

    def key(r):
        if dimension == "irs":
            return tx.EXPENSE_CATEGORY_BY_ID.get(r.get("category_id"), {}).get("irs", "Other")
        return r.get(field)

    acc = defaultdict(lambda: [0.0] * len(months))
    for r in data:
        mk = r["date"][:7]
        if mk in months:
            acc[key(r)][months.index(mk)] += value(r)
    rows = []
    for k, vals in acc.items():
        if dimension == "irs":
            name = k
        elif dimension == "type":
            name = tx.INCOME_TYPE_NAME.get(k, k or "Transaction")
        elif dimension == "group":
            name = tx.EXPENSE_GROUP_NAME.get(k, k)
        else:
            name = led.name_for(dimension, k)
        sp = None
        if dimension == "category":
            sp = tx.CATEGORY_BY_ID.get(k, {}).get("subPillar")
        elif dimension == "activity":
            sp = tx.ACTIVITY_BY_ID.get(k, {}).get("subPillar")
        rows.append({"key": k, "name": name, "subPillar": sp, "values": vals, "total": sum(vals)})
    rows.sort(key=lambda r: -r["total"])
    sub_totals = defaultdict(float)
    for r in rows:
        if r["subPillar"]:
            sub_totals[r["subPillar"]] += r["total"]
    return {"log": log, "measure": measure, "dimension": dimension, "period": led.period.json(),
            "months": months, "rows": rows, "subPillarTotals": dict(sub_totals),
            "total": sum(r["total"] for r in rows)}
