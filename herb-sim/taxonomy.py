"""Logsperity taxonomy: pillars, categories, activities, expense categories and pick lists.

IDs are stable slugs so names can be corrected without breaking history (design §4).
"""
import re
from datetime import date

PILLARS = [
    ("clients", "Clients"),
    ("relationships", "Relationships"),
    ("advertising", "Advertising"),
    ("prospecting", "Prospecting"),
]

SUB_PILLARS = [
    ("clients", "Clients", "clients"),
    ("personal", "Relationships – Personal", "relationships"),
    ("professional", "Relationships – Professional", "relationships"),
    ("internet", "Advertising – Internet", "advertising"),
    ("traditional", "Advertising – Traditional", "advertising"),
    ("prospecting", "Prospecting", "prospecting"),
]
SUB_PILLAR_PILLAR = {s: p for s, _, p in SUB_PILLARS}

_CATEGORIES = {
    "clients": ["Past Client", "Current Client", "Prospective Client"],
    "personal": ["Family", "Friend", "Social Group", "Church", "School", "Sports", "Alumni Group"],
    "professional": ["Accountant", "Appraiser", "Architect", "Attorney", "Banker", "Business Coach",
                     "Consultant", "Contractor", "Dentist", "Designer", "Doctor", "Engineer",
                     "Escrow Officer", "Financial Planner", "Insurance Agent", "Insurance Company",
                     "Lender", "Realtor", "Salesperson", "Therapist", "Vendor"],
    "internet": ["Website-Personal", "Website-Blog", "Website-Free", "Website-Paid", "Website-Video Site"],
    "traditional": ["Article", "Billboard", "Car Wrap", "Door Hanger", "Flyer", "Lead Generator",
                    "Magazine", "Mailer/Farming", "Newsletter", "Newspaper", "Promotion", "Radio",
                    "Sign", "Sponsorship", "Swag", "TV"],
    "prospecting": ["Cold Calls", "Committee", "Door Knocking", "Expired Listings", "Floor Time",
                    "Office Visits", "Open House", "Organization", "Network-Open Group", "Seminar",
                    "Trade Show"],
}

_ACTIVITIES = {
    "clients": ["Past Client Interaction", "Current Client Interaction", "Marketing for Current Client",
                "Prospective Client Interaction", "Client Appreciation Party", "Database Marketing",
                "Email Campaigning", "Facebook Marketing", "Mail Campaigning", "Newsletter Campaigning",
                "Personal Visit", "Twitter Marketing"],
    "personal": ["Relationship Building-Personal", "Community Involvement-Personal", "Socializing"],
    "professional": ["Relationship Building-Professional", "Networking-Closed Group", "Partner Coaching",
                     "Committee Involvement", "Organization Involvement",
                     "Community Involvement-Professional"],
    "internet": ["Website Set Up", "Blog Development", "Website Ad Set Up-Free", "Website Ad Set Up-Paid",
                 "Video Production"],
    "traditional": ["Article Writing", "Billboard Ad Set Up", "Car Wrap Set Up", "Door Hanger Set Up",
                    "Flyer Set Up", "Lead Generation", "Magazine Ad Set Up", "Mail Campaigning",
                    "Newsletter Set Up", "Newspaper Ad Set Up", "Promotion Set Up", "Radio Ad Set Up",
                    "Sign Set Up", "Sponsorship Set Up", "Swag Set Up", "TV Ad Set Up"],
    "prospecting": ["Cold Calling", "Committee Involvement", "Door Knocking", "Expired Listings Calling",
                    "Floor Time", "Office Visits", "Open Houses", "Organization Involvement",
                    "Networking-Open Group", "Seminar", "Trade Show"],
}


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def _build(kind, table):
    prefix = "cat" if kind == "category" else "act"
    names = {}
    for sub, items in table.items():
        for n in items:
            names.setdefault(n, []).append(sub)
    out = []
    for sub, items in table.items():
        pillar = SUB_PILLAR_PILLAR[sub]
        for n in items:
            iid = f"{prefix}.{slug(n)}"
            if len(names[n]) > 1:  # duplicate names get a pillar suffix
                iid += "." + pillar
            out.append({"id": iid, "name": n, "pillar": pillar, "subPillar": sub})
    return out


CATEGORIES = _build("category", _CATEGORIES)
ACTIVITIES = _build("activity", _ACTIVITIES)
CATEGORY_BY_ID = {c["id"]: c for c in CATEGORIES}
ACTIVITY_BY_ID = {a["id"]: a for a in ACTIVITIES}

IRS_CATEGORIES = ["Advertising", "Car & Truck", "Commissions/Fees", "Insurance", "Interest-Other",
                  "Legal/Professional", "Office", "Meals/Entertainment", "Rent", "Repairs", "Supplies",
                  "Taxes", "Travel", "Utilities", "Wages", "Other"]

EXPENSE_GROUPS = [
    ("clients", "Clients", "clients"),
    ("relationships", "Relationships", "relationships"),
    ("ad_internet", "Advertising – Internet", "advertising"),
    ("ad_traditional", "Advertising – Traditional", "advertising"),
    ("prospecting", "Prospecting", "prospecting"),
    ("general", "General", None),
    ("self_improvement", "Self-Improvement", None),
    ("technology", "Technology", None),
    ("travel", "Travel", None),
]
EXPENSE_GROUP_PILLAR = {g: p for g, _, p in EXPENSE_GROUPS}
EXPENSE_GROUP_NAME = {g: n for g, n, _ in EXPENSE_GROUPS}

A, O, M = "Advertising", "Other", "Meals/Entertainment"
_EXPENSES = {
    "clients": [("Database Marketing", A), ("Client Appreciation Party", A), ("Client Refund", O),
                ("Closing Gift", A), ("Entertainment", M), ("Mailers", A), ("Meal", M), ("Newsletter", A),
                ("Printing", O), ("Referral Fee", A), ("Thank You Gifts", A)],
    "relationships": [("Database Marketing", A), ("Entertainment", M), ("Mailers", A), ("Meal", M),
                      ("Networking Dues", A), ("Newsletter", A), ("Printing", O), ("Referral Fee", A),
                      ("Thank You Gifts", A)],
    "ad_internet": [(n, A) for n in ["Domain Registration", "Internet Provider", "Website Ad",
                                     "Web Developer", "Web Hosting", "Video Production"]],
    "ad_traditional": [(n, A) for n in ["Billboard Ad", "Car Wrap", "Flyer Set Up", "Lead Generation",
                                        "Promotion Set Up", "Magazine Ad", "Mailers", "Mailing Cost",
                                        "Newsletter", "Newspaper Ad", "Radio Ad", "Signs", "Sponsorship",
                                        "Swag", "TV Ad"]] + [("Printing", O)],
    "prospecting": [("Leave Behind Material", A), ("Seminar Production", A), ("Staging", A),
                    ("Trade Show", A), ("Printing", O)],
    "general": [("Bank Charges", O), ("Clothing", O), ("Donation", O), ("Drycleaning", O), ("Dues", O),
                ("Equipment", "Office"), ("Insurance", "Insurance"), ("Legal", "Legal/Professional"),
                ("License", O), ("Membership", O), ("Office Fees", "Office"), ("Office Supplies", "Office"),
                ("Phone", O), ("Photography", A), ("Postage", O), ("Printing", O),
                ("Professional Services", "Legal/Professional"), ("Repairs", "Repairs"), ("Shipping", "Office"),
                ("Subscription", O), ("Tax Preparation", "Legal/Professional"), ("Wages", "Wages")],
    "self_improvement": [("Coaching Fees", "Legal/Professional"), ("Education", O), ("Event", O),
                         ("Marketing Consultant", "Legal/Professional"), ("Seminar", O), ("Training", O)],
    "technology": [("Data Storage", "Office"), ("Internet Provider", A), ("Software", O), ("Technology", O)],
    "travel": [("Car Expenses", "Car & Truck"), ("Car Wash", "Car & Truck"), ("Lodging", "Travel"),
               ("Meal", "Travel"), ("Transportation", "Travel")],
}
EXPENSE_CATEGORIES = [{"id": f"exp.{g}.{slug(n)}", "group": g, "name": n, "irs": irs}
                      for g, items in _EXPENSES.items() for n, irs in items]
EXPENSE_CATEGORY_BY_ID = {e["id"]: e for e in EXPENSE_CATEGORIES}

STRENGTH = [("red_hot", "Red Hot", "#C2412D"), ("hot", "Hot", "#E8792B"), ("medium", "Medium", "#C98A12"),
            ("cold", "Cold", "#3B6FB6"), ("no_go", "No Go", "#7A7A7A")]
STRENGTH_NAME = {k: n for k, n, _ in STRENGTH}
PLAN_OF_ACTION = ["Call", "Email", "Mail Business Cards", "Mail Letter", "Mail Information", "Mail Promotion",
                  "Mail Newsletter", "Add to Database", "Add to Email Campaign", "Add to Phone Campaign",
                  "Add to Mail Campaign", "Visit", "Refer to Other", "Refer to Notes", "Nothing Now"]
FOLLOW_UP_DAYS = [5, 7, 10, 15, 21, 30, 45, 60, 75, 90, 120, 180, 250, 365]
REFERRAL_REQUEST = [("yes", "Yes"), ("no", "No"), ("ask_7", "Ask in 7 days"), ("ask_14", "Ask in 14 days"),
                    ("ask_21", "Ask in 21 days"), ("ask_30", "Ask in 30 days"), ("ask_45", "Ask in 45 days")]
INCOME_TYPES = [("commission", "Commission"), ("consulting_fees", "Consulting Fees"),
                ("profit_sharing", "Profit Sharing"), ("bonuses", "Bonuses/Incentives"),
                ("base_wages", "Base Wages"), ("allowance", "Allowance"), ("referral_fees", "Referral Fees")]
INCOME_TYPE_NAME = dict(INCOME_TYPES)
PROFESSIONS = ["Accountant", "Appraiser", "Architect", "Attorney", "Banker", "Business Coach", "Consultant",
               "Contractor", "Dentist", "Designer", "Doctor", "Engineer", "Escrow Officer", "Financial Planner",
               "Insurance Agent", "Lender", "Realtor", "Salesperson", "Therapist", "Other"]
PHONE_TYPES = ["Mobile", "Work", "Home", "Other"]
MILEAGE_REASONS = ["Past Client Interaction", "Current Client Interaction", "Prospective Client Interaction",
                   "Personal Visit", "Relationship Building-Personal", "Relationship Building-Professional",
                   "Community Involvement-Personal", "Community Involvement-Professional", "Socializing",
                   "Networking-Closed Group", "Networking-Open Group", "Partner Coaching",
                   "Committee Involvement", "Organization Involvement", "Door Knocking", "Office Visits",
                   "Open Houses", "Seminar", "Trade Show", "Closing", "Title Company", "Office"]

# IRS standard mileage rates by date (dollars per mile).
MILEAGE_RATES = [
    (date(2025, 1, 1), date(2025, 12, 31), 0.70),
    (date(2026, 1, 1), date(2026, 6, 30), 0.725),
    (date(2026, 7, 1), date(2026, 12, 31), 0.76),
]


def mileage_rate(d):
    if isinstance(d, str):
        d = date.fromisoformat(d)
    for start, end, rate in MILEAGE_RATES:
        if start <= d <= end:
            return rate
    return MILEAGE_RATES[-1][2] if d > MILEAGE_RATES[-1][1] else MILEAGE_RATES[0][2]


def pillar_name(p):
    return dict(PILLARS).get(p, p or "")


def sub_pillar_name(s):
    return {k: n for k, n, _ in SUB_PILLARS}.get(s, s or "")


def as_json():
    return {
        "pillars": [{"id": k, "name": n} for k, n in PILLARS],
        "subPillars": [{"id": k, "name": n, "pillar": p} for k, n, p in SUB_PILLARS],
        "categories": CATEGORIES,
        "activities": ACTIVITIES,
        "expenseGroups": [{"id": g, "name": n, "pillar": p} for g, n, p in EXPENSE_GROUPS],
        "expenseCategories": EXPENSE_CATEGORIES,
        "irsCategories": IRS_CATEGORIES,
        "picklists": {
            "strength": [{"id": k, "name": n, "color": c} for k, n, c in STRENGTH],
            "planOfAction": PLAN_OF_ACTION,
            "followUpDays": FOLLOW_UP_DAYS,
            "referralRequest": [{"id": k, "name": n} for k, n in REFERRAL_REQUEST],
            "incomeTypes": [{"id": k, "name": n} for k, n in INCOME_TYPES],
            "professions": PROFESSIONS,
            "phoneTypes": PHONE_TYPES,
            "mileageReasons": MILEAGE_REASONS,
        },
    }
