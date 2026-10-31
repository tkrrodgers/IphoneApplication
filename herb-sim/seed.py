"""Deterministic synthetic year for the simulator (seed 42).

Pilot user: Marcus Reed, independent mortgage broker, Denton TX. All people and companies are fictional.
The data is shaped so HERB's coaching rules have something real to say:
past clients and professional relationships convert best; paid web leads bring volume but rarely close;
door knocking never closes; open houses eat hours; LeadBoost is a zombie subscription; Jared Cole has drifted.

Usage:  python seed.py --reset
"""
import argparse
import json
import random
from datetime import date, timedelta

import calc
import db
import taxonomy as tx

FIRST = ["Aaron", "Abby", "Alan", "Amelia", "Ben", "Bianca", "Caleb", "Carmen", "Chris", "Dana", "Derek",
         "Elena", "Ethan", "Faith", "Gabe", "Grace", "Hector", "Hannah", "Ian", "Isabel", "Jacob", "Jasmine",
         "Kyle", "Kara", "Liam", "Lucia", "Mason", "Maya", "Nate", "Nina", "Owen", "Olivia", "Paul", "Paige",
         "Raj", "Rosa", "Sam", "Sofia", "Trey", "Tessa", "Victor", "Wendy", "Xavier", "Yara", "Zach", "Zoe"]
LAST = ["Adams", "Baker", "Bennett", "Brooks", "Castillo", "Chen", "Coleman", "Diaz", "Edwards", "Fischer",
        "Flores", "Garcia", "Gupta", "Hayes", "Hughes", "Jensen", "Kim", "Lawson", "Lopez", "Mendez", "Mitchell",
        "Nguyen", "Novak", "Owens", "Patel", "Perry", "Quinn", "Ramos", "Reyes", "Rivera", "Russell", "Sanders",
        "Shaw", "Silva", "Stewart", "Sullivan", "Torres", "Turner", "Vargas", "Walsh", "Warren", "Watts", "Young"]
PAST_CLIENTS = ["Greg Wallace", "Helen Ng", "Marco Bianchi", "Linda Foster", "Darnell Price", "Kate Murphy",
                "Omar Haddad", "Janet Kwan", "Luis Medina", "Rachel Stone", "Peter Holm", "Tasha Greene",
                "Victor Alvarado", "Wes Tanaka", "Erin Doyle"]
REALTORS = {"Dana Ruiz": "Lakeside Realty", "Jared Cole": "North Star Realty",
            "Ruth Alvarez": "Cedar & Main Realty", "Kim Tran": "Prairie Oak Realty"}
RESTAURANTS = ["Cedar Grill", "Juniper Cafe", "Oak Street Bistro", "Sundance Coffee", "Square Burger Co."]
LENDERS = ["Summit Wholesale Lending", "Bluebonnet Mortgage Wholesale", "Lone Star Wholesale"]
DESTINATIONS = [("Lakeside Realty", "act.relationship_building_professional"),
                ("North Star Realty", "act.relationship_building_professional"),
                ("Cedar & Main Realty", "act.relationship_building_professional"),
                ("Prairie Oak Realty", "act.relationship_building_professional"),
                ("Denton County Title", None), ("Client home – Hickory St", "act.past_client_interaction"),
                ("Client home – Bell Ave", "act.current_client_interaction"),
                ("Okafor Insurance", "act.relationship_building_professional"),
                ("Hale & Co. CPAs", "act.relationship_building_professional"),
                ("Denton Chamber of Commerce", "act.networking_open_group"),
                ("Bank branch – University Dr", None), ("Coffee meeting – Sundance Coffee", None)]

# (key, count, closings, sub_pillar, category, activity, source(s), kind)
STREAMS = [
    ("past_client", 18, 7, "clients", "cat.past_client", "act.past_client_interaction", PAST_CLIENTS, "person"),
    ("current_client", 4, 1, "clients", "cat.current_client", "act.current_client_interaction",
     ["Linda Foster", "Omar Haddad"], "person"),
    ("dana", 14, 5, "professional", "cat.realtor", "act.relationship_building_professional", ["Dana Ruiz"], "person"),
    ("jared", 10, 3, "professional", "cat.realtor", "act.relationship_building_professional", ["Jared Cole"], "person"),
    ("ruth", 12, 3, "professional", "cat.realtor", "act.relationship_building_professional", ["Ruth Alvarez"], "person"),
    ("kim", 13, 1, "professional", "cat.realtor", "act.relationship_building_professional", ["Kim Tran"], "person"),
    ("brenda", 5, 2, "professional", "cat.insurance_agent", "act.networking_closed_group", ["Brenda Okafor"], "person"),
    ("tom", 4, 1, "professional", "cat.accountant", "act.relationship_building_professional", ["Tom Hale"], "person"),
    ("family", 6, 2, "personal", "cat.family", "act.relationship_building_personal",
     ["Mike Reed", "Sarah Lin", "Dave Ortiz"], "person"),
    ("church", 3, 0, "personal", "cat.church", "act.community_involvement_personal",
     ["Grace Community Church"], "company"),
    ("zillow", 22, 1, "internet", "cat.website_paid", "act.website_ad_set_up_paid", ["Zillow"], "online"),
    ("leadboost", 12, 0, "internet", "cat.website_paid", "act.website_ad_set_up_paid", ["LeadBoost"], "online"),
    ("website", 6, 1, "internet", "cat.website_personal", "act.website_set_up", ["reedhomelending.com"], "online"),
    ("mailer", 5, 1, "traditional", "cat.mailer_farming", "act.mail_campaigning.advertising",
     ["Hickory Creek farm mailer"], "company"),
    ("open_house", 16, 1, "prospecting", "cat.open_house", "act.open_houses", None, "venue"),
    ("door", 5, 0, "prospecting", "cat.door_knocking", "act.door_knocking", ["Savannah neighborhood"], "venue"),
    ("seminar", 8, 2, "prospecting", "cat.seminar", "act.seminar", ["First-Time Buyer Seminar"], "venue"),
    ("chamber", 5, 1, "prospecting", "cat.network_open_group", "act.networking_open_group",
     ["Denton Chamber mixer"], "company"),
]
OPEN_HOUSE_ADDRESSES = ["2201 Bonnie Brae", "418 Pecan Ln", "1702 Emerson Ct", "93 Hilltop Dr", "3310 Teasley Ln",
                        "750 Mockingbird Ln", "1215 Egan St", "88 Lakeview Blvd", "605 Fulton St",
                        "2904 Wind River Ln", "141 Oak Hollow", "3721 Sandpiper Dr", "910 Locust St",
                        "2650 Mesa Ct", "47 Live Oak Ct", "1980 Cedar Bend", "5122 Cypress Way", "77 Elm Park"]

VACATION_WEEKS_2026 = {date(2026, 3, 16), date(2026, 7, 6), date(2026, 8, 24)}


def daterange(a, b):
    d = a
    while d <= b:
        yield d
        d += timedelta(days=1)


def monday(d):
    return d - timedelta(days=d.weekday())


class Seeder:
    def __init__(self, conn, now):
        self.conn = conn
        self.now = now
        self.yesterday = now - timedelta(days=1)
        self.r = random.Random(42)
        self.used_names = set()
        self.src = {}
        self.odometer = 41250.0

    # ---------------------------------------------------------------- helpers
    def source(self, name, kind="person"):
        if name not in self.src:
            self.src[name] = db.source_id_for(self.conn, name, kind)
        return self.src[name]

    def person(self):
        while True:
            f, l = self.r.choice(FIRST), self.r.choice(LAST)
            if (f, l) not in self.used_names:
                self.used_names.add((f, l))
                return f, l

    def phone(self):
        return f"(940) 555-{self.r.randint(100, 9999):04d}"

    def insert(self, table, **row):
        cols = ", ".join(row)
        q = ", ".join("?" for _ in row)
        cur = self.conn.execute(f"INSERT INTO {table}({cols}) VALUES({q})", tuple(row.values()))
        return cur.lastrowid

    def is_vacation(self, d):
        return monday(d) in VACATION_WEEKS_2026

    def business_days(self, a, b):
        return [d for d in daterange(a, b) if d.weekday() < 5 and not self.is_vacation(d)]

    # ---------------------------------------------------------------- prospects and closings
    def stream_dates(self, key, n, a, b):
        days = self.business_days(a, b)
        if key == "jared":  # Jared Cole drifts: nothing from him in the last ~41 days
            days = [d for d in days if d <= self.now - timedelta(days=42)]
        if key in ("open_house",):
            sats = [d for d in daterange(a, b) if d.weekday() == 5 and not self.is_vacation(d)]
            step = max(1, len(sats) // n)
            return [sats[min(len(sats) - 1, i * step + 1)] for i in range(n)]
        return sorted(self.r.choice(days) for _ in range(n))

    def build_prospects(self, a, b, scale=1.0, story=True):
        made = []
        for key, count, closes, sub, cat, act, sources, kind in STREAMS:
            n = max(1, round(count * scale))
            k = round(closes * scale)
            dates = self.stream_dates(key, n, a, b)
            ids = []
            for i, d in enumerate(dates):
                f, l = self.person()
                if key == "open_house":
                    sname = f"Open house – {OPEN_HOUSE_ADDRESSES[i % len(OPEN_HOUSE_ADDRESSES)]}"
                else:
                    sname = self.r.choice(sources)
                pid = self.add_prospect(d, f, l, sub, cat, act, self.source(sname, kind), key)
                ids.append((pid, d, sub, cat, act, sname))
            made.append((key, k, ids))
        # closings: the earliest eligible prospects of each stream close 30-75 days later
        for key, k, ids in made:
            eligible = [x for x in ids if x[1] <= self.yesterday - timedelta(days=35)]
            self.r.shuffle(eligible)
            done = 0
            for pid, d, sub, cat, act, sname in eligible:
                if done >= k:
                    break
                cd = d + timedelta(days=self.r.randint(30, 75))
                if cd > self.yesterday:
                    continue
                self.add_closing(pid, cd, key)
                done += 1
        return made

    def add_prospect(self, d, first, last, sub, cat, act, source_id, key, **extra):
        r = self.r
        strength = extra.pop("strength", None) or r.choices(
            ["red_hot", "hot", "medium", "cold", "no_go"], [5, 20, 40, 25, 10])[0]
        if d >= self.now - timedelta(days=30):
            follow = (self.now + timedelta(days=r.randint(2, 20))).isoformat()
        else:
            follow = (d + timedelta(days=r.choice(tx.FOLLOW_UP_DAYS[:6]))).isoformat()
        row = dict(date=d.isoformat(), last_name=last, first_names=first, phone1=self.phone(), phone1_type="Mobile",
                   email1=f"{first.lower()}.{last.lower()}@example.com", zip="76201", city="Denton", state="TX",
                   pillar=tx.SUB_PILLAR_PILLAR[sub], sub_pillar=sub, category_id=cat, source_id=source_id,
                   activity_id=act, strength=strength, plan_of_action=r.choice(["Call", "Email", "Add to Database",
                                                                                "Call", "Visit"]),
                   follow_up=follow, notes=None, capture="manual", reviewed=1, created_at=d.isoformat())
        row.update(extra)
        return self.insert("prospects", **row)

    def add_closing(self, pid, d, key):
        r = self.r
        p = db.one(self.conn.execute("SELECT * FROM prospects WHERE id = ?", (pid,)))
        base = 380000 + (40000 if p["sub_pillar"] == "professional" else 0) + (25000 if key == "seminar" else 0)
        size = round(min(650000, max(210000, r.gauss(base, 70000))), -3)
        income = round(size * r.uniform(0.0112, 0.0145))
        self.conn.execute("UPDATE prospects SET strength = 'hot' WHERE id = ?", (pid,))
        days_ago = (self.now - d).days
        req = "ask_14" if days_ago < 20 else r.choice(["yes", "yes", "ask_14", "ask_30", "no"])
        cid = self.insert("closings", date=d.isoformat(), prospect_id=pid, pillar=p["pillar"],
                          sub_pillar=p["sub_pillar"], category_id=p["category_id"], source_id=p["source_id"],
                          activity_id=p["activity_id"], transaction_size=size, income=income, referral_request=req,
                          post_closing_follow_up=(d + timedelta(days=180)).isoformat(), notes=None, capture="manual",
                          reviewed=1)
        self.insert("income", date=d.isoformat(), mode="transaction", closing_id=cid, pillar=p["pillar"],
                    sub_pillar=p["sub_pillar"], category_id=p["category_id"], source_id=p["source_id"],
                    activity_id=p["activity_id"], type="commission", transaction_count=1, transaction_size=size,
                    last_name=p["last_name"], amount=income, payer=r.choice(LENDERS), expect_1099=1,
                    capture="manual", reviewed=1)
        # closing gift
        self.insert("expenses", date=d.isoformat(), vendor="Denton Gift Co.", amount=round(r.uniform(75, 150), 2),
                    group_id="clients", category_id="exp.clients.closing_gift", source_id=p["source_id"],
                    card_last4="4417", purpose=f"Closing gift – {p['first_names']} {p['last_name']}",
                    has_receipt=1, capture="manual", reviewed=1)
        return cid

    def story_prospects(self):
        n = self.now
        s = self.source
        self.add_prospect(n - timedelta(days=20), "Priya", "Shah", "professional", "cat.realtor",
                          "act.relationship_building_professional", s("Dana Ruiz"), "dana", strength="red_hot",
                          follow_up=(n - timedelta(days=2)).isoformat(), plan_of_action="Call",
                          notes="Pre-approval expires Nov 2. Last contact Oct 19 (text).")
        self.add_prospect(n - timedelta(days=6), "Lena", "Ortiz", "prospecting", "cat.open_house", "act.open_houses",
                          s("Open house – 2201 Bonnie Brae", "venue"), "open_house", strength="hot",
                          follow_up=(n - timedelta(days=5)).isoformat(), plan_of_action="Call",
                          notes="Met at Saturday's open house — not called yet.")
        self.add_prospect(n - timedelta(days=12), "Tom & Ana", "Becker", "clients", "cat.past_client",
                          "act.past_client_interaction", s("Greg Wallace"), "past_client", strength="red_hot",
                          follow_up=n.isoformat(), plan_of_action="Call",
                          notes="Rate-lock decision call at 2:00 PM.")
        self.add_prospect(n - timedelta(days=3), "Kevin", "Morales", "professional", "cat.realtor",
                          "act.relationship_building_professional", s("Ruth Alvarez"), "ruth", strength="hot",
                          follow_up=n.isoformat(), plan_of_action="Call",
                          notes="Move-up buyer, about $520,000. Wants to talk after 5.")
        self.add_prospect(n - timedelta(days=9), "Marisol", "Vega", "clients", "cat.past_client",
                          "act.past_client_interaction", s("Helen Ng"), "past_client", strength="hot",
                          follow_up=(n - timedelta(days=1)).isoformat(), plan_of_action="Email",
                          notes="Refinance question — sent docs list.")
        self.add_prospect(n - timedelta(days=15), "Derrick", "Hall", "internet", "cat.website_paid",
                          "act.website_ad_set_up_paid", s("Zillow", "online"), "zillow", strength="medium",
                          follow_up=(n + timedelta(days=1)).isoformat(), plan_of_action="Call",
                          notes="Zillow lead; slow to respond.")
        # auto-captured by voice yesterday — waiting in the Review queue
        self.add_prospect(n - timedelta(days=1), "Alicia", "Gomez", "professional", "cat.realtor",
                          "act.relationship_building_professional", s("Kim Tran"), "kim", strength="medium",
                          follow_up=(n + timedelta(days=4)).isoformat(), plan_of_action="Call", capture="voice",
                          reviewed=0, notes="Said by voice: met at Prairie Oak office; buying in spring.")

    # ---------------------------------------------------------------- activity, trips, expenses, income
    def build_activities(self, a, b, jared_cutoff):
        r = self.r
        realtors = ["Dana Ruiz", "Ruth Alvarez", "Kim Tran", "Jared Cole"]
        for d in daterange(a, b):
            if self.is_vacation(d):
                continue
            wd = d.weekday()
            acts = []
            if wd == 1:
                acts.append(("act.past_client_interaction", r.choice([60, 75, 90]), r.choice(PAST_CLIENTS)))
            if wd == 3:
                acts.append(("act.past_client_interaction", 30, r.choice(PAST_CLIENTS)))
            if wd == 0 and d.day <= 7:
                acts.append(("act.database_marketing", 60, None))
            if wd in (1, 3):
                choices = [x for x in realtors if x != "Jared Cole" or d < jared_cutoff]
                acts.append(("act.relationship_building_professional", r.choice([45, 60, 75]), r.choice(choices)))
            if wd == 2:
                acts.append(("act.networking_closed_group", 60, "Brenda Okafor" if d.day <= 7 else None))
            if wd == 4 and d.isocalendar()[1] % 2 == 0:
                acts.append(("act.partner_coaching", 45, r.choice(["Dana Ruiz", "Ruth Alvarez"])))
            if wd == 4 and d.isocalendar()[1] % 2 == 1:
                acts.append(("act.socializing", 45, None))
            if wd == 0:
                acts.append(("act.website_ad_set_up_paid", 30, r.choice(["Zillow", "LeadBoost"])))
            if wd == 0 and 8 <= d.day <= 14:
                acts.append(("act.website_set_up", 60, "reedhomelending.com"))
            if d.month in (2, 5, 8, 11) and d.day == 3 and wd < 5:
                acts.append(("act.mail_campaigning.advertising", 90, "Hickory Creek farm mailer"))
            if d.day == 15 and wd < 5:
                acts.append(("act.relationship_building_professional", 45, "Tom Hale"))
            if wd == 4 and d.day in (5, 6, 7, 19, 20, 21) and d.month in (3, 4, 9, 10):
                acts.append(("act.cold_calling", 30, None))
            for act, minutes, src in acts:
                if d > b:
                    continue
                meta = tx.ACTIVITY_BY_ID[act]
                self.insert("activities", date=d.isoformat(), pillar=meta["pillar"], sub_pillar=meta["subPillar"],
                            activity_id=act, minutes=minutes,
                            source_id=self.source(src, "online" if src in ("Zillow", "LeadBoost",
                                                                           "reedhomelending.com") else "person")
                            if src else None, notes=None, capture="calendar" if d.month >= 9 else "manual",
                            reviewed=1)

    def build_events(self, a, b):
        """Open houses, door knocking, seminars, chamber mixers — time-heavy prospecting."""
        r = self.r
        sats = [d for d in daterange(a, b) if d.weekday() == 5 and not self.is_vacation(d)]
        oh_days = sats[1::2][:20] if len(sats) > 30 else sats[1::2]
        for i, d in enumerate(oh_days):
            self.event(d, "act.open_houses", 210, f"Open house – {OPEN_HOUSE_ADDRESSES[i % len(OPEN_HOUSE_ADDRESSES)]}",
                       "venue")
            self.trip(d, "Open Houses", OPEN_HOUSE_ADDRESSES[i % len(OPEN_HOUSE_ADDRESSES)], r.uniform(6, 18),
                      "act.open_houses")
            self.expense(d, "FedEx Office", 38.50, "prospecting", "exp.prospecting.leave_behind_material",
                         purpose="Open house flyers")
        thursdays = [d for d in daterange(a, b) if d.weekday() == 3 and not self.is_vacation(d)]
        for d in thursdays[3::9][:5]:
            self.event(d, "act.door_knocking", 120, "Savannah neighborhood", "venue")
            self.trip(d, "Door Knocking", "Savannah neighborhood", r.uniform(8, 14), "act.door_knocking")
        tuesdays = [d for d in daterange(a, b) if d.weekday() == 1 and not self.is_vacation(d)]
        for d in tuesdays[5::10][:4]:
            self.event(d, "act.seminar", 150, "First-Time Buyer Seminar", "venue")
            self.event(d - timedelta(days=1), "act.seminar", 60, "First-Time Buyer Seminar", "venue")
            self.expense(d, "Denton Public Library", 160.00, "prospecting", "exp.prospecting.seminar_production",
                         purpose="Seminar room and handouts")
        wednesdays = [d for d in daterange(a, b) if d.weekday() == 2 and not self.is_vacation(d)]
        for d in wednesdays[2::8][:5]:
            self.event(d, "act.networking_open_group", 90, "Denton Chamber mixer", "company")

    def event(self, d, act, minutes, src, kind):
        if d > self.yesterday:
            return
        meta = tx.ACTIVITY_BY_ID[act]
        self.insert("activities", date=d.isoformat(), pillar=meta["pillar"], sub_pillar=meta["subPillar"],
                    activity_id=act, minutes=minutes, source_id=self.source(src, kind), notes=None,
                    capture="manual", reviewed=1)

    def trip(self, d, reason, dest, miles, act=None, business=True, capture=None, reviewed=1):
        if d > self.yesterday and reviewed:
            return
        miles = round(miles, 1)
        gps = d >= date(2026, 9, 1)
        capture = capture or ("gps" if gps else "manual")
        start = self.odometer
        self.odometer += miles
        self.insert("trips", date=d.isoformat(), reason=reason, destination=dest,
                    odometer_start=None if gps else round(start, 1), odometer_end=None if gps else round(self.odometer, 1),
                    gps_miles=miles if gps else None, is_business=1 if business else 0, activity_id=act,
                    source_id=None, notes=None, capture=capture, reviewed=reviewed)

    def build_trips(self, a, b):
        r = self.r
        for d in self.business_days(a, b):
            for _ in range(r.choice([1, 2, 2, 2, 3, 3])):
                dest, act = r.choice(DESTINATIONS)
                reason = tx.ACTIVITY_BY_ID[act]["name"] if act else r.choice(["Closing", "Title Company", "Office"])
                business = r.random() > 0.07
                self.trip(d, reason if business else "Personal errand", dest, r.uniform(7, 42), act, business)

    def expense(self, d, vendor, amount, group, cat, source=None, purpose=None, with_whom=None, receipt=1,
                capture="manual", reviewed=1):
        if d > self.yesterday and reviewed:
            return
        return self.insert("expenses", date=d.isoformat(), vendor=vendor, amount=round(amount, 2), group_id=group,
                           relationship_sub_pillar="professional" if group == "relationships" else None,
                           category_id=cat, source_id=self.source(source) if source else None, check_number=None,
                           card_last4="4417", purpose=purpose, with_whom=with_whom, has_receipt=receipt, notes=None,
                           capture=capture, reviewed=reviewed)

    def build_expenses(self, a, b):
        r = self.r
        months = []
        d = date(a.year, a.month, 1)
        while d <= b:
            months.append(d)
            d = date(d.year + (d.month == 12), d.month % 12 + 1, 1)
        for m in months:
            def on(day):
                return date(m.year, m.month, min(day, 28))
            self.expense(on(3), "LeadBoost", 95.00, "ad_internet", "exp.ad_internet.website_ad", "LeadBoost",
                         "Monthly lead subscription", capture="bank" if m.month >= 6 else "manual")
            self.expense(on(10), "Zillow Premier Agent", 250.00, "ad_internet", "exp.ad_internet.website_ad", "Zillow",
                         "Zillow lead program")
            self.expense(on(5), "HostPilot", 24.00, "ad_internet", "exp.ad_internet.web_hosting", purpose="Website hosting")
            self.expense(on(18), "Verizon", 92.00, "general", "exp.general.phone", purpose="Mobile phone (business share)")
            self.expense(on(1), "LoanPilot CRM", 59.00, "technology", "exp.technology.software", purpose="CRM")
            self.expense(on(7), "Prosperity Simplified", 149.00, "self_improvement",
                         "exp.self_improvement.coaching_fees", purpose="Business coaching")
            for _ in range(3):
                day = r.randint(2, 27)
                realtor = r.choice(["Dana Ruiz", "Ruth Alvarez", "Kim Tran"] +
                                   (["Jared Cole"] if on(day) < self.now - timedelta(days=42) else []))
                self.expense(on(day), r.choice(RESTAURANTS), r.uniform(24, 96), "relationships",
                             "exp.relationships.meal", realtor, "Referral pipeline review", realtor)
            if m.month % 3 == 1:
                self.expense(on(r.randint(5, 25)), "Office Depot", r.uniform(55, 140), "general",
                             "exp.general.office_supplies", purpose="Office supplies")
            if m.month in (2, 5, 8, 11):
                self.expense(on(2), "PrintHub Direct", 420.00, "ad_traditional", "exp.ad_traditional.mailers",
                             "Hickory Creek farm mailer", "Farm mailer – 600 homes")
        if a.year == 2026:
            fixed = [(date(2026, 1, 12), "NMLS", 330.00, "general", "exp.general.license", None, "License renewal"),
                     (date(2026, 1, 20), "Denton Chamber of Commerce", 425.00, "relationships",
                      "exp.relationships.networking_dues", "Denton Chamber mixer", "Annual dues"),
                     (date(2026, 2, 3), "Shield E&O", 940.00, "general", "exp.general.insurance", None, "E&O insurance"),
                     (date(2026, 3, 20), "Hale & Co. CPAs", 650.00, "general", "exp.general.tax_preparation",
                      "Tom Hale", "2025 tax return"),
                     (date(2026, 4, 14), "MortgageEd Online", 249.00, "self_improvement",
                      "exp.self_improvement.training", None, "NMLS continuing education"),
                     (date(2026, 6, 13), "Lakeview Pavilion", 1250.00, "clients",
                      "exp.clients.client_appreciation_party", None, "Client appreciation party"),
                     (date(2026, 9, 9), "Canva", 119.99, "technology", "exp.technology.software", None,
                      "Design software (annual)")]
            for d, v, amt, g, c, s, p in fixed:
                self.expense(d, v, amt, g, c, s, p)
        # some $75+ expenses missing receipts (substantiation alerts)
        big = db.rows(self.conn.execute("SELECT id FROM expenses WHERE amount >= 75 AND date BETWEEN ? AND ? "
                                        "AND vendor NOT IN ('LeadBoost','Zillow Premier Agent') ORDER BY id",
                                        (a.isoformat(), b.isoformat())))
        for row in self.r.sample(big, min(5, len(big))):
            self.conn.execute("UPDATE expenses SET has_receipt = 0 WHERE id = ?", (row["id"],))

    def build_income_2026(self):
        rows = [(date(2026, 3, 18), "type", "consulting_fees", 1500.00, None, "Denton Builders Assoc.",
                 "Builder financing workshop"),
                (date(2026, 7, 15), "type", "bonuses", 2000.00, None, "Summit Wholesale Lending", "Volume bonus Q2"),
                (date(2026, 8, 21), "type", "consulting_fees", 1500.00, None, "Denton Builders Assoc.",
                 "Builder financing workshop"),
                (date(2026, 9, 30), "batch", "commission", 3100.00, 2, "Bluebonnet Mortgage Wholesale",
                 "Two small refinances paid together")]
        for d, mode, typ, amt, cnt, payer, notes in rows:
            if d <= self.yesterday:
                self.insert("income", date=d.isoformat(), mode=mode, type=typ, amount=amt, transaction_count=cnt,
                            payer=payer, expect_1099=1, notes=notes, capture="manual", reviewed=1)

    def build_review_items(self):
        """~8 auto-captured items from the last two days waiting for the user's one-minute review."""
        n = self.now
        y, y2 = n - timedelta(days=1), n - timedelta(days=2)
        self.trip(y, "Relationship Building-Professional", "Lakeside Realty", 12.4,
                  "act.relationship_building_professional", capture="gps", reviewed=0)
        self.trip(y, "Relationship Building-Professional", "Cedar Grill", 3.1, None, capture="gps", reviewed=0)
        self.trip(y2, "Open Houses", "2201 Bonnie Brae", 6.1, "act.open_houses", capture="gps", reviewed=0)
        self.expense(y, "Cedar Grill", 86.40, "relationships", "exp.relationships.meal", "Dana Ruiz",
                     "Q4 referral pipeline review", "Dana Ruiz", receipt=0, capture="bank", reviewed=0)
        self.expense(y2, "Office Depot", 43.17, "general", "exp.general.office_supplies", None, "Printer paper, folders",
                     receipt=1, capture="receipt", reviewed=0)
        for d, act, minutes, src, note in [(y, "act.relationship_building_professional", 75, "Dana Ruiz",
                                            "Calendar: Lunch – Dana Ruiz"),
                                           (y2, "act.networking_open_group", 90, "Denton Chamber mixer",
                                            "Calendar: Chamber mixer")]:
            meta = tx.ACTIVITY_BY_ID[act]
            self.insert("activities", date=d.isoformat(), pillar=meta["pillar"], sub_pillar=meta["subPillar"],
                        activity_id=act, minutes=minutes, source_id=self.source(src), notes=note, capture="calendar",
                        reviewed=0)

    # ---------------------------------------------------------------- account, plan, settings
    def build_settings(self):
        db.set_account(self.conn, {
            "name": "Marcus Reed", "title": "Owner / Mortgage Broker", "email": "marcus.reed@example.com",
            "company": "Reed Home Lending", "phone": "(940) 555-0100", "profession": "Lender",
            "address": "1200 Hickory St", "zip": "76201", "city": "Denton", "state": "TX", "reminderTime": "17:30",
            "plan": "monthly", "herbQuestions": "balanced",
            "subscription": {"status": "active", "via": "Apple In-App Purchase (simulated)",
                             "renews": (self.now + timedelta(days=12)).isoformat(), "price": "$50/month"},
        })
        for year, inputs in [(2026, (180000, 150000, 5500, 380000, 45, 3)),
                             (2025, (160000, 132000, 5200, 360000, 45, 3))]:
            self.conn.execute("INSERT OR REPLACE INTO plans VALUES(?,?,?,?,?,?,?)", (year, *inputs))
        for key, level in AUTOPILOT_DEFAULTS.items():
            self.conn.execute("INSERT OR REPLACE INTO autopilot VALUES(?,?)", (key, level[0]))
        last_monday = monday(self.now) if self.now.weekday() > 0 else self.now - timedelta(days=7)
        cid = self.insert("checkins", date=last_monday.isoformat(),
                          json=json.dumps({"note": "Seeded check-in", "index": None}))
        for text, act, target in [("2 hours of Past Client Interaction", "act.past_client_interaction", 2),
                                  ("1 hour of Partner Coaching", "act.partner_coaching", 1),
                                  ("Coffee with Jared Cole", "act.relationship_building_professional", 1)]:
            self.insert("commitments", checkin_id=cid, text=text, activity_id=act, target=target,
                        due=(last_monday + timedelta(days=6)).isoformat())

    def run(self):
        for t in ("sources", "prospects", "closings", "income", "expenses", "trips", "activities", "account",
                  "plans", "autopilot", "checkins", "commitments", "insight_dismissals"):
            self.conn.execute(f"DELETE FROM {t}")
        jared_cutoff = self.now - timedelta(days=41)
        # Q4 2025 history (for "same period last year" and past-client sources)
        h0, h1 = date(2025, 10, 1), date(2025, 12, 31)
        self.build_prospects(h0, h1, scale=0.2)
        self.build_activities(h0, h1, jared_cutoff)
        self.build_trips(h0, h1)
        self.build_expenses(h0, h1)
        # 2026 to yesterday
        a, b = date(2026, 1, 2), self.yesterday
        self.build_prospects(a, b)
        self.story_prospects()
        self.build_activities(a, b, jared_cutoff)
        self.build_events(a, b)
        self.build_trips(a, b)
        self.build_expenses(a, b)
        self.build_income_2026()
        self.build_review_items()
        self.build_settings()
        self.conn.commit()


AUTOPILOT_DEFAULTS = {
    # key: (default level, min, max, label, description)
    "mileage": (3, 0, 4, "Mileage trips", "Detect drives and classify Business/Personal"),
    "receipts": (2, 0, 4, "Receipt reading", "Read receipt photos and pick the category"),
    "bank": (3, 0, 4, "Bank & card transactions", "Categorize imported transactions by vendor rules"),
    "calendar": (3, 0, 4, "Calendar → activities", "Turn meetings into business-building activity"),
    "prospects": (1, 0, 2, "New prospects", "Offer to log callers and lead emails as prospects"),
    "closings": (2, 0, 3, "Closings & income", "Fill closings and match deposits — money is always reviewed"),
    "followups": (4, 0, 4, "Follow-up reminders", "Remind you of follow-ups, expiries and partner drift"),
    "messages": (2, 0, 2, "Messages", "Draft texts and emails — HERB never sends"),
    "weekly_plan": (4, 0, 4, "Weekly check-in", "Run the Monday check-in automatically"),
    "goals": (1, 0, 1, "Goal changes", "Suggest plan changes — you decide goals"),
}


def build(conn, now=None):
    Seeder(conn, now or calc.today()).run()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--reset", action="store_true", help="delete and rebuild the database")
    ap.add_argument("--db", help="database path (default data/logsperity.db)")
    args = ap.parse_args()
    conn = db.connect(args.db)
    build(conn)
    led = calc.ledger(conn, "ytd")
    s = led.summary()
    print(f"Seeded {db.db_path() if not args.db else args.db}")
    print(f"YTD: {s['prospects']} prospects, {s['closings']} closings ({calc.pct(s['conversion'])}), "
          f"income {calc.money(s['income'])}, expenses {calc.money(s['expenses'])}, "
          f"miles {s['businessMiles']:,.0f}, BB hours {s['bbHours']:.0f}, index {s['index']:.0f}")


if __name__ == "__main__":
    main()
