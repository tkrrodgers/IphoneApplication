"""HERB — the assistant, analyst and coach (design §6, §16, §17).

Deterministic stand-in for the on-device model: it parses what the user says into an intent and a draft,
runs the matching calc.py query, and phrases a short spoken answer. Code computes, HERB narrates —
every number in a reply comes from calc.py. Drafts are never saved until the user confirms.
"""
import difflib
import json
import re
from datetime import date, datetime, timedelta

import calc
import db
import taxonomy as tx
from calc import money, money_k, num, pct, ratio

# ======================================================================= text helpers

WAKE = re.compile(r"^\s*(?:(?:hey\s+)?siri\s*,?\s*ask\s+herb\b|(?:ok(?:ay)?\s+)?(?:(?:hi|hey|hello|yo)\s*,?\s*)?herb\b)"
                  r"[\s,.!:;-]*", re.I)
WORD_NUMS = {"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
             "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
             "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
             "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90}
MONTH_NAMES = ["january", "february", "march", "april", "may", "june", "july", "august", "september",
               "october", "november", "december"]
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
STOPWORDS = {"the", "and", "of", "co", "inc", "llc", "com", "a", "at", "in", "on", "to", "for"}


def strip_wake(text):
    return WAKE.sub("", text or "").strip()


def words_to_digits(text):
    """'two hours' -> '2 hours', 'forty five minutes' -> '45 minutes', 'a couple of' -> '2'."""
    t = re.sub(r"\ba couple of\b|\ba couple\b", "2", text, flags=re.I)

    def repl(m):
        parts = re.split(r"[\s-]+", m.group(0).lower())
        return str(sum(WORD_NUMS[p] for p in parts))
    keys = "|".join(sorted(WORD_NUMS, key=len, reverse=True))
    return re.sub(rf"\b(?:{keys})(?:[\s-](?:{keys}))?\b", repl, t, flags=re.I)


PHONE_RE = re.compile(r"(?:\+?1[\s.-]?)?\(?\b(\d{3})\)?[\s.-]?(\d{3})[\s.-]?(\d{4})\b")
AMT_RE = re.compile(r"(?<![\w.])(\$\s?)?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*"
                    r"(k\b|thousand\b|grand\b|million\b|mil\b|m\b|bucks\b|dollars?\b)?", re.I)
NON_MONEY_AFTER = re.compile(r"^\s*(?:am|pm|a\.m\.|p\.m\.|o'?clock|days?|weeks?|months?|years?|miles?|mi\b|"
                             r"minutes?|mins?|hours?|hrs?|h\b|leads?|prospects?|people|percent|%|:\d|st\b|nd\b|"
                             r"rd\b|th\b|transactions?|deals?|homes?|units?)", re.I)
NON_MONEY_BEFORE = re.compile(r"(?:after|at|around|by|before|until|till|room|suite|number|#|"
                              r"jan\w*|feb\w*|mar\w*|apr\w*|may|jun\w*|jul\w*|aug\w*|sep\w*|oct\w*|nov\w*|dec\w*)"
                              r"\s*$", re.I)


def phone(text):
    m = PHONE_RE.search(text)
    return (f"({m.group(1)}) {m.group(2)}-{m.group(3)}", m.span()) if m else (None, None)


def amounts(text):
    """All money-like numbers: [(value, start, end, explicit)] — explicit when it had $ or a money unit."""
    out = []
    for m in AMT_RE.finditer(text):
        before = text[:m.start()]
        if not m.group(1) and not m.group(3):
            if NON_MONEY_AFTER.match(text[m.end():]) or NON_MONEY_BEFORE.search(before):
                continue
        elif m.group(3) and not m.group(1) and NON_MONEY_AFTER.match(m.group(3)):
            continue
        v = float(m.group(2).replace(",", ""))
        unit = (m.group(3) or "").lower()
        if unit in ("k", "thousand", "grand"):
            v *= 1000
        elif unit in ("million", "mil", "m"):
            v *= 1_000_000
        out.append((v, m.start(), m.end(), bool(m.group(1) or unit)))
    return out


def duration_minutes(text):
    t = words_to_digits(text.lower())
    t = re.sub(r"\ban hour and a half\b|\b1 and a half hours?\b|\bhour and a half\b", "90 minutes", t)
    t = re.sub(r"\bhalf an hour\b|\ba half hour\b", "30 minutes", t)
    t = re.sub(r"\b(?:an|one) hour\b", "60 minutes", t)
    total = 0.0
    m = re.search(r"(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\b(?:\s*and\s*(?:a\s*)?half)?(?:\s*(?:and\s*)?(\d+)\s*(?:minutes?|mins?))?", t)
    if m:
        total = float(m.group(1)) * 60 + (30 if "half" in m.group(0) else 0) + (float(m.group(2) or 0))
    else:
        m = re.search(r"(\d+)\s*(?:minutes?|mins?)\b", t)
        if m:
            total = float(m.group(1))
    if not total:
        return None
    return int(max(15, round(total / 15) * 15))


def parse_when(text, now):
    t = text.lower()
    if re.search(r"\btoday\b|\btonight\b|\bthis (?:afternoon|evening)\b", t):
        return now
    if "tomorrow" in t:
        return now + timedelta(days=1)
    if "next week" in t:
        return now + timedelta(days=7 - now.weekday())
    m = re.search(r"\bin (\d+|a|an|one|two|three|four|five|six|seven|ten) (day|week|month)s?\b", t)
    if m:
        n = {"a": 1, "an": 1}.get(m.group(1)) or int(words_to_digits(m.group(1)))
        return now + timedelta(days=n * {"day": 1, "week": 7, "month": 30}[m.group(2)])
    for i, wd in enumerate(WEEKDAYS):
        if re.search(rf"\b{wd}\b", t):
            delta = (i - now.weekday()) % 7 or 7
            return now + timedelta(days=delta)
    m = re.search(r"\b(" + "|".join(n[:3] for n in MONTH_NAMES) + r")[a-z]*\.?\s+(\d{1,2})\b", t)
    if m:
        mo = [n[:3] for n in MONTH_NAMES].index(m.group(1)) + 1
        d = date(now.year, mo, min(int(m.group(2)), 28 if mo == 2 else 30 if mo in (4, 6, 9, 11) else 31))
        return d if d >= now else date(now.year + 1, mo, d.day)
    return None


def parse_time(text):
    m = re.search(r"\b(?:after|at|around|by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?", text, re.I)
    if not m:
        return None
    h, mi = int(m.group(1)), int(m.group(2) or 0)
    ap = (m.group(3) or "").lower().replace(".", "")
    if not ap:
        ap = "pm" if 1 <= h <= 7 else "am"
    return f"{h}:{mi:02d} {ap.upper()}"


def fmt_day(d, now):
    if d is None:
        return "—"
    if d == now:
        return "today"
    if d == now + timedelta(days=1):
        return "tomorrow"
    if d == now - timedelta(days=1):
        return "yesterday"
    if 0 < (d - now).days < 7:
        return d.strftime("%A")
    return f"{d:%b} {d.day}"


NAME_TOKEN = r"[A-Z][a-z'’\-]+"
NAME_RE = re.compile(rf"\b({NAME_TOKEN}(?:\s+(?:&|and)\s+{NAME_TOKEN})?(?:\s+{NAME_TOKEN}){{1,2}})\b")
NOT_NAMES = {"Hi", "Hey", "Herb", "New", "I", "The", "Got", "Log", "Lunch", "Dinner", "Coffee", "Thursday",
             "Monday", "Tuesday", "Wednesday", "Friday", "Saturday", "Sunday", "Open", "House", "Zillow",
             "LeadBoost", "Save", "Add", "Record", "Prospect", "Lead", "Closed", "Spent", "Drove", "Start",
             "Email", "Send", "What", "Which", "Who", "How", "Am", "My", "Our", "Started", "Yes", "No",
             "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
             "November", "December"}


def split_name(full):
    parts = full.split()
    if len(parts) >= 3 and parts[1] in ("&", "and"):
        return " ".join(parts[:-1]).replace(" and ", " & "), parts[-1]
    return " ".join(parts[:-1]), parts[-1]


def find_person_name(text, exclude=()):
    """Best guess at a new person's full name in the utterance."""
    m = re.search(rf"(?:lead|prospect|buyer|borrower|client|named|called)[,:]?\s+(?:is\s+|named\s+|called\s+)?"
                  rf"({NAME_TOKEN}(?:\s+(?:&|and)\s+{NAME_TOKEN})?(?:\s+{NAME_TOKEN}){{1,2}})", text)
    cands = [m.group(1)] if m else []
    cands += [c for c in NAME_RE.findall(text)]
    for c in cands:
        words = c.split()
        while words and words[0] in NOT_NAMES:
            words = words[1:]
        while words and words[-1] in NOT_NAMES:
            words = words[:-1]
        if len(words) < 2:
            continue
        c2 = " ".join(words)
        if any(c2.lower() in e.lower() or e.lower() in c2.lower() for e in exclude if e):
            continue
        return c2
    # lowercase fallback: "new lead kevin morales ..."
    m = re.search(r"(?:new lead|new prospect|lead|prospect)[,:]?\s+([a-z]+)\s+([a-z]+)", text, re.I)
    if m and m.group(1).lower() not in ("from", "for", "with", "to", "is", "named") \
            and m.group(2).lower() not in ("from", "referred", "sent", "at", "who", "wants"):
        return f"{m.group(1).title()} {m.group(2).title()}"
    return None


def tokens(text):
    return re.findall(r"[a-z0-9]+", (text or "").lower())


def match_source(conn, text, exclude_tokens=()):
    """Fuzzy-match a known source (person, company, venue) mentioned in the text."""
    toks = set(tokens(text)) - set(t.lower() for t in exclude_tokens)
    best, best_score = None, 0.0
    srcs = db.rows(conn.execute(
        "SELECT s.id, s.name, s.kind, (SELECT COUNT(*) FROM prospects p WHERE p.source_id = s.id) AS n "
        "FROM sources s"))
    for s in srcs:
        stoks = [t for t in tokens(s["name"]) if t not in STOPWORDS and len(t) > 2]
        if not stoks:
            continue
        hits = 0
        for t in stoks:
            if t in toks or (len(t) > 4 and difflib.get_close_matches(t, toks, 1, 0.88)):
                hits += 1
        if not hits:
            continue
        score = hits / len(stoks) + (0.25 if hits == len(stoks) else 0) + min(s["n"], 20) / 1000
        if s["kind"] == "venue" and hits < len(stoks):
            continue
        if score > best_score and hits / len(stoks) >= 0.5:
            best, best_score = s, score
    return best


# category/activity inference: (pattern, sub_pillar, category, activity)
CATEGORY_KEYWORDS = [
    (r"past client|former client|old client|closed with (?:me|us)", "clients", "cat.past_client", "act.past_client_interaction"),
    (r"current client", "clients", "cat.current_client", "act.current_client_interaction"),
    (r"zillow|realtor\.com|leadboost|lead boost|web lead|online lead|paid lead|internet lead", "internet",
     "cat.website_paid", "act.website_ad_set_up_paid"),
    (r"open house", "prospecting", "cat.open_house", "act.open_houses"),
    (r"door ?knock", "prospecting", "cat.door_knocking", "act.door_knocking"),
    (r"cold call", "prospecting", "cat.cold_calls", "act.cold_calling"),
    (r"seminar|workshop|class\b", "prospecting", "cat.seminar", "act.seminar"),
    (r"trade show|expo\b", "prospecting", "cat.trade_show", "act.trade_show"),
    (r"chamber|mixer|networking event", "prospecting", "cat.network_open_group", "act.networking_open_group"),
    (r"insurance", "professional", "cat.insurance_agent", "act.networking_closed_group"),
    (r"\bcpa\b|accountant", "professional", "cat.accountant", "act.relationship_building_professional"),
    (r"attorney|lawyer", "professional", "cat.attorney", "act.relationship_building_professional"),
    (r"builder|contractor", "professional", "cat.contractor", "act.relationship_building_professional"),
    (r"financial planner|advisor", "professional", "cat.financial_planner", "act.relationship_building_professional"),
    (r"realtor|real estate agent|listing agent|buyer'?s agent|agent at", "professional", "cat.realtor",
     "act.relationship_building_professional"),
    (r"brother|sister|\bmom\b|\bdad\b|cousin|family|uncle|aunt|in-law", "personal", "cat.family",
     "act.relationship_building_personal"),
    (r"friend|neighbor", "personal", "cat.friend", "act.relationship_building_personal"),
    (r"church", "personal", "cat.church", "act.community_involvement_personal"),
    (r"website|my site|\bblog\b", "internet", "cat.website_personal", "act.website_set_up"),
    (r"mailer|postcard|farm", "traditional", "cat.mailer_farming", "act.mail_campaigning.advertising"),
    (r"\bsign\b|yard sign", "traditional", "cat.sign", "act.sign_set_up"),
]

ACTIVITY_KEYWORDS = [
    (r"door ?knock", "act.door_knocking"), (r"open house", "act.open_houses"), (r"cold call", "act.cold_calling"),
    (r"seminar|workshop", "act.seminar"), (r"trade show|expo\b", "act.trade_show"),
    (r"chamber|mixer|networking event|open networking", "act.networking_open_group"),
    (r"bni|networking group|closed group|leads group|breakfast group", "act.networking_closed_group"),
    (r"past client|former client", "act.past_client_interaction"),
    (r"current client", "act.current_client_interaction"),
    (r"partner coaching|coaching (?:dana|ruth|kim|jared|realtor)", "act.partner_coaching"),
    (r"database", "act.database_marketing"), (r"email campaign", "act.email_campaigning"),
    (r"facebook", "act.facebook_marketing"), (r"newsletter", "act.newsletter_campaigning"),
    (r"\bblog\b", "act.blog_development"), (r"video", "act.video_production"),
    (r"zillow|leadboost|lead boost|paid leads|web leads", "act.website_ad_set_up_paid"),
    (r"website", "act.website_set_up"), (r"mailer|mail campaign|postcards", "act.mail_campaigning.advertising"),
    (r"floor time", "act.floor_time"), (r"office visit", "act.office_visits"),
    (r"expired", "act.expired_listings_calling"), (r"committee", "act.committee_involvement.relationships"),
    (r"volunteer|community|church", "act.community_involvement_personal"),
    (r"sociali[sz]|party|happy hour", "act.socializing"),
    (r"realtor|agent|lunch with|coffee with|breakfast with|meeting with|met with", "act.relationship_building_professional"),
]


def infer_from_keywords(text):
    t = text.lower()
    for pat, sub, cat, act in CATEGORY_KEYWORDS:
        if re.search(pat, t):
            return sub, cat, act
    return None


def infer_activity(text):
    t = text.lower()
    for pat, act in ACTIVITY_KEYWORDS:
        if re.search(pat, t):
            return act
    return None


def source_profile(conn, source_id):
    """Most common tags for prospects from this source; Clients when the source is a past client (rule R2)."""
    src = db.one(conn.execute("SELECT * FROM sources WHERE id = ?", (source_id,)))
    if src:
        parts = src["name"].split()
        if len(parts) >= 2:
            past = conn.execute(
                "SELECT 1 FROM prospects p JOIN closings c ON c.prospect_id = p.id "
                "WHERE lower(p.first_names) = ? AND lower(p.last_name) = ?",
                (" ".join(parts[:-1]).lower(), parts[-1].lower())).fetchone()
            if past:
                return "clients", "cat.past_client", "act.past_client_interaction"
    r = conn.execute("SELECT sub_pillar, category_id, activity_id, COUNT(*) n FROM prospects WHERE source_id = ? "
                     "GROUP BY 1,2,3 ORDER BY n DESC LIMIT 1", (source_id,)).fetchone()
    return (r["sub_pillar"], r["category_id"], r["activity_id"]) if r else None


def latest_source_for_activity(conn, act):
    r = conn.execute("SELECT s.name FROM activities a JOIN sources s ON s.id = a.source_id WHERE a.activity_id = ? "
                     "ORDER BY a.date DESC LIMIT 1", (act,)).fetchone()
    return r["name"] if r else None


def strength_from(text):
    t = text.lower()
    if re.search(r"red hot|urgent|asap|ready (?:now|today)|right away", t):
        return "red_hot"
    if re.search(r"no go|not interested", t):
        return "no_go"
    if re.search(r"\bhot\b|ready to (?:buy|go|move)|pre-?approved|serious|motivated|move-?up|wants to talk", t):
        return "hot"
    if re.search(r"just looking|not sure|maybe|someday|next year|\bcold\b", t):
        return "cold"
    return "medium"


def tag_names(sub, cat, act):
    return (tx.pillar_name(tx.SUB_PILLAR_PILLAR.get(sub)) if sub else "?",
            tx.CATEGORY_BY_ID.get(cat, {}).get("name", "?"),
            tx.ACTIVITY_BY_ID.get(act, {}).get("name", "?"))


# ======================================================================= intent detection

QUESTION_START = re.compile(r"^(?:what|which|who|whom|how|am|are|is|where|when|do|does|did|can|could|should|"
                            r"would|will|tell me|show me|give me|list)\b", re.I)

QUERY_INTENTS = [
    ("help", r"what can you do|\bhelp\b|how do i use"),
    ("review", r"need from me|review queue|anything to review|what needs review|needs? my review"),
    ("focus", r"\bfocus\b|what should i (?:do|work on)|make more money|priorit"),
    ("follow_ups", r"follow[ -]?ups?|follow up|who (?:do|should) i (?:call|contact|text)|overdue|who needs me"),
    ("report", r"\b(?:email|send|print)\b.*\breport\b|\breport\b"),
    ("pace", r"on track|on pace|\bpace\b|behind|ahead of|my goal|reach my goal"),
    ("index", r"\bindex\b|logsperity score|my score"),
    ("sources_no_close", r"never close|don'?t close|do not close|not converting|no closings|never convert"),
    ("conversion", r"convert|conversion|close rate|closing rate"),
    ("efficiency", r"wast\w* (?:my )?time|efficien|hours per|time per"),
    ("roi", r"\broi\b|return on|best return|most profitable|profitab"),
    ("top_sources", r"(?:which|top|best) (?:realtors?|agents?|agenc\w+|sources?|referr\w+|partners?)|"
                    r"who sends|made me the most|most money|most income"),
    ("income_summary", r"how much (?:have i|did i) (?:made|make|earn)|income|earned|commission"),
    ("expenses_summary", r"expenses?|spend(?:ing)?|spent|cost"),
    ("mileage_summary", r"mileage|how many miles|miles (?:have i|did i)"),
    ("plan", r"business plan|\bplan\b|\bgoals?\b"),
]

LOG_INTENTS = [
    ("log_trip", r"start (?:a |my )?(?:business )?trip|end (?:the |my )?trip|stop (?:the |my )?trip|"
                 r"\bi'?m here\b|\barrived\b|\bdrove\b|\bdriving to\b|\bmiles to\b"),
    ("log_closing", r"\bclosed\b|\bfunded\b|\bclosing\b|\bclosed on\b"),
    ("log_expense", r"scan (?:a |my )?receipt|\breceipt\b|\blunch\b|\bdinner\b|\bbreakfast\b|\bcoffee\b|"
                    r"\bbought\b|\bpaid (?:for|\$)|\bexpense\b|\bspent\b|\bgas\b|\bparking\b|\bgift\b"),
    ("log_income", r"referral fee|consulting fee|\bbonus\b|profit sharing|got paid|received (?:a |my )?|"
                   r"\bincome\b|commission check|\bgot (?:a |my )?(?:\$|\d)"),
    ("log_prospect", r"new (?:lead|prospect)|leads? to record|record (?:a |some )?leads?|log (?:a )?(?:lead|prospect)|"
                     r"referred|sent (?:him|her|them|me|over)|\bprospect\b|\blead\b"),
    ("log_activity", r"(?:\d|an?|one|two|three|four|five|half)\s*(?:hours?|hrs?|minutes?|mins?)\b"),
]


def detect_intent(text):
    t = text.lower().strip()
    if not t:
        return "unknown"
    is_q = bool(QUESTION_START.match(t)) or t.endswith("?")
    if re.fullmatch(r"(?:hi|hello|hey|thanks?|thank you|good (?:morning|afternoon|evening))[.!]?", t):
        return "smalltalk"
    order = (QUERY_INTENTS + LOG_INTENTS) if is_q else (LOG_INTENTS + QUERY_INTENTS)
    # "I spent two hours door knocking" is activity, not expense
    if not is_q and duration_minutes(t) and not re.search(r"\$|dollars|bucks", t) and \
            not re.search(r"\bclosed\b|\bfunded\b", t):
        if not re.search(r"start (?:a |my )?trip|drove", t):
            return "log_activity"
    for name, pat in order:
        if re.search(pat, t):
            return name
    return "unknown"


# ======================================================================= replies

def reply(intent, say, cards=None, draft=None, actions=None, display=None, follow_up=False):
    out = {"intent": intent, "say": say, "cards": cards or [], "actions": actions or []}
    if display:
        out["display"] = display
    if draft:
        out["draft"] = draft
    if follow_up:
        out["followUp"] = True
    return out


ACTIVE_TRIP = {}
LOG_FRAMES = {"log_prospect": "prospects", "log_closing": "closings", "log_income": "income",
              "log_activity": "activities"}


def ask(conn, text, now=None, dialog=None, save=None):
    """One turn with HERB. `dialog` is the state HERB returned when it asked a follow-up question (dialog.py)."""
    now = now or calc.today()
    t = strip_wake((text or "").strip())
    try:
        if dialog:
            return D.turn(conn, dialog, t, now, save or default_saver(conn))
        return route(conn, t, now)
    except Exception as e:  # never crash the voice loop
        out = reply("unknown", "Sorry, I hit a snag working that out. Try saying it another way.",
                    display=f"Error: {e}")
        out["dialog"] = dialog
        return out


def route(conn, t, now):
    """A fresh request (no follow-up pending)."""
    if not t:
        return reply("smalltalk", f"Hi {first_name(conn)}. What can I do for you?", follow_up=True)
    p = D.match_update(conn, t)
    if p:
        return D.start_update(conn, p, t, now)
    intent = detect_intent(t)
    if intent in LOG_FRAMES:
        return D.start(conn, LOG_FRAMES[intent], t, now)
    return HANDLERS.get(intent, h_unknown)(conn, t, now)


def default_saver(conn):
    import server  # local import: server imports herb
    return lambda log, data, rid=None: (server.update_log(conn, log, rid, data) if rid
                                        else server.save_log(conn, log, data))


def first_name(conn):
    return (db.get_account(conn).get("name") or "there").split()[0]


# ----------------------------------------------------------------------- logging intents
# Extraction and follow-up questions for every log live in dialog.py; these are the special cases.

INCOME_TYPE_WORDS = [(r"referral fee", "referral_fees"), (r"consult", "consulting_fees"), (r"bonus|incentive", "bonuses"),
                     (r"profit shar", "profit_sharing"), (r"wage|salary|paycheck", "base_wages"),
                     (r"allowance", "allowance"), (r"commission|comp\b", "commission")]

EXPENSE_KEYWORDS = [
    (r"closing gift", "clients", "exp.clients.closing_gift"),
    (r"gift", "clients", "exp.clients.thank_you_gifts"),
    (r"\bgas\b|fuel", "travel", "exp.travel.car_expenses"),
    (r"parking|uber|lyft|toll|taxi", "travel", "exp.travel.transportation"),
    (r"hotel|lodging|airbnb", "travel", "exp.travel.lodging"),
    (r"open house.*(?:flyer|print)|(?:flyer|print).*open house", "prospecting", "exp.prospecting.leave_behind_material"),
    (r"flyers?|printing|print\b", "general", "exp.general.printing"),
    (r"postage|stamps", "general", "exp.general.postage"),
    (r"\bups\b|fedex|shipping", "general", "exp.general.shipping"),
    (r"office supplies|supplies|paper|ink|toner|office depot|staples\b|folders", "general", "exp.general.office_supplies"),
    (r"software|subscription|\bapp\b|crm", "technology", "exp.technology.software"),
    (r"zillow|leadboost|lead boost|leads\b", "ad_internet", "exp.ad_internet.website_ad"),
    (r"mailers?|postcards?", "ad_traditional", "exp.ad_traditional.mailers"),
    (r"dues|membership", "relationships", "exp.relationships.networking_dues"),
    (r"training|course|continuing ed|\bce\b|class", "self_improvement", "exp.self_improvement.training"),
    (r"coaching", "self_improvement", "exp.self_improvement.coaching_fees"),
    (r"phone bill|cell phone|\bphone\b", "general", "exp.general.phone"),
    (r"license|nmls", "general", "exp.general.license"),
]
MEAL = re.compile(r"\blunch\b|\bdinner\b|\bbreakfast\b|\bcoffee\b|\bdrinks\b|\bmeal\b", re.I)


def h_log_expense(conn, t, now):
    if re.search(r"scan (?:a |my )?receipt|take a picture|photo of (?:a |my |the )?receipt", t, re.I):
        return reply("log_expense", "Opening the receipt scanner. Hold the receipt flat and I'll read it.",
                     actions=[{"label": "Scan receipt", "action": "open", "target": "expense:scan"}])
    return D.start(conn, "expenses", t, now)


def h_log_trip(conn, t, now):
    tl = t.lower()
    if re.search(r"start (?:a |my )?(?:business )?trip|driving to", tl):
        dest = None
        m = re.search(r"\bto\s+(.+?)(?:[.,!?]|$)", t)
        if m:
            dest = m.group(1).strip()
        ACTIVE_TRIP.clear()
        ACTIVE_TRIP.update({"started": datetime.now().isoformat(timespec="seconds"), "destination": dest})
        return reply("log_trip", "Trip started. I'm tracking the miles with simulated GPS. "
                                 "Say \"end trip\" when you get there.",
                     cards=[{"title": "Trip in progress", "subtitle": dest or "Destination not set", "chip": "GPS"}])
    if re.search(r"end (?:the |my )?trip|stop (?:the |my )?trip|i'?m here|arrived", tl):
        if not ACTIVE_TRIP:
            return reply("log_trip", "There's no trip running. Say \"start a trip\" when you leave.")
        started = datetime.fromisoformat(ACTIVE_TRIP["started"])
        mins = max(1, (datetime.now() - started).seconds // 60)
        m = re.search(r"(\d+(?:\.\d+)?)\s*(?:miles?|mi)\b", words_to_digits(tl))
        data, known = {"gpsMiles": float(m.group(1)) if m else round(min(45.0, max(2.4, mins * 0.6)), 1),
                       "capture": "gps"}, ["miles"]
        if ACTIVE_TRIP.get("destination"):
            data["destination"] = ACTIVE_TRIP["destination"]
            known.append("destination")
        ACTIVE_TRIP.clear()
        return D.start(conn, "trips", t, now, data=data, known=known)
    return D.start(conn, "trips", t, now)


def fmt_minutes(m):
    h, mm = divmod(int(m), 60)
    if h and mm:
        return f"{h} hour{'s' if h > 1 else ''} {mm} minutes"
    if h:
        return f"{h} hour{'s' if h > 1 else ''}"
    return f"{mm} minutes"


# ----------------------------------------------------------------------- query intents

def h_focus(conn, t, now):
    f = focus(conn, now)
    return reply("focus", f["say"], cards=[{"title": i["title"], "subtitle": i["why"], "value": i.get("value"),
                                            "chip": "focus"} for i in f["items"]] +
                 ([{"title": "Drop: " + f["drop"]["title"], "subtitle": f["drop"]["why"], "chip": "drop"}]
                  if f.get("drop") else []),
                 actions=[{"label": "Add to my calendar", "action": "say",
                           "target": "Done — I blocked time for these on your calendar (simulated)."}])


def h_follow_ups(conn, t, now):
    items = follow_ups(conn, now)
    if not items:
        return reply("follow_ups", "You're all caught up — no follow-ups due today.")
    urgent = [i for i in items if i["chip"] in ("late", "new")]
    say = f"{len(items)} today."
    if urgent:
        names = [i["name"] for i in urgent[:2]]
        say += f" {len(urgent)} {'is' if len(urgent) == 1 else 'are'} urgent: " + " and ".join(
            f"{i['name']} — {i['reason'].rstrip('.')}" for i in urgent[:2]) + "."
    timed = [i for i in items if i["chip"] == "today"]
    if timed:
        say += f" Also {timed[0]['name']}: {timed[0]['reason'].rstrip('.')}."
    if urgent:
        say += f" Want me to draft texts to {' and '.join(i['name'].split()[0] for i in urgent[:2])}?"
    return reply("follow_ups", say,
                 cards=[{"title": i["name"], "subtitle": i["reason"], "chip": i["chip"]} for i in items[:6]],
                 actions=[{"label": "Draft texts", "action": "say",
                           "target": "Drafts are ready in Messages — tap send when you're parked."},
                          {"label": "Open Today", "action": "open", "target": "today"}])


def h_pace(conn, t, now):
    tr = calc.plan_tracking(conn, now.year, now)
    it = {i["key"]: i for i in tr["items"]}
    inc, pro = it["income"], it["profit"]
    say = (f"Income is {pct(inc['pacePct'])} of pace: {money(inc['actual'])} against {money(inc['projected'])} "
           f"projected by today. Profit is at {pct(pro['pacePct'])} of pace.")
    fc = tr["forecast"]["value"]
    goal = inc["goal"]
    say += f" I forecast about {money_k(fc)} for the year against your {money_k(goal)} goal."
    if fc < goal:
        led = calc.ledger(conn, "ytd")
        gap = goal - fc
        n = gap / (led.avg_closing_income or 5000)
        say += f" Closing the gap takes about {num(n, 1)} more closings."
    return reply("pace", say, cards=[{"title": i["label"], "subtitle": f"{i['display']['actual']} of "
                                      f"{i['display']['projected']} projected · goal {i['display']['goal']}",
                                      "value": pct(i["pacePct"]),
                                      "chip": "win" if (i["pacePct"] or 0) >= 1 else "late"} for i in tr["items"]])


def h_conversion(conn, t, now):
    led = calc.ledger(conn, "ytd")
    rows = [r for r in led.breakdown("pillar") if r["prospects"]]
    rows.sort(key=lambda r: -(r["conversion"] or 0))
    best, worst = rows[0], rows[-1]
    say = (f"Overall you convert {pct(led.conversion)} — {led.n_closings} closings from {led.n_prospects} prospects. "
           f"{best['name']} converts best at {pct(best['conversion'])}, {best['closings']} of {best['prospects']}. "
           f"{worst['name']} is lowest at {pct(worst['conversion'])}.")
    cats = [r for r in led.breakdown("category") if r["prospects"] >= 4]
    if cats:
        c = max(cats, key=lambda r: r["conversion"] or 0)
        say += f" Your best category is {c['name']} at {pct(c['conversion'])}."
    return reply("conversion", say, cards=[{"title": r["name"], "subtitle": f"{r['closings']} of {r['prospects']}",
                                            "value": pct(r["conversion"])} for r in rows])


NO_SOURCE = ("Unknown", "Unassigned")  # prospects whose source isn't known yet — not a source to coach on


def no_close_sources(led, minimum=3):
    return sorted([r for r in led.breakdown("source") if r["prospects"] >= minimum and r["closings"] == 0
                   and r["name"] not in NO_SOURCE], key=lambda r: -r["prospects"])


def h_sources_no_close(conn, t, now):
    led = calc.ledger(conn, "ytd")
    rows = no_close_sources(led)
    if not rows:
        return reply("sources_no_close", "Every source with three or more prospects has closed at least once.")
    top = rows[:3]
    say = "These sources send prospects that never close: " + "; ".join(
        f"{r['name']}, {r['prospects']} prospects" for r in top) + "."
    spend = [r for r in top if r["expenses"]]
    if spend:
        say += f" You've spent {money(spend[0]['expenses'])} on {spend[0]['name']} this year."
    return reply("sources_no_close", say, cards=[{"title": r["name"], "subtitle": f"{r['prospects']} prospects, 0 closings"
                                                  + (f" · {money(r['expenses'])} spent" if r["expenses"] else ""),
                                                  "chip": "concern"} for r in rows[:6]])


def h_efficiency(conn, t, now):
    led = calc.ledger(conn, "ytd")
    rows = [r for r in led.breakdown("pillar") if r["closings"] and r["hours"]]
    rows.sort(key=lambda r: r["hoursPerClosing"])
    best, worst = rows[0], rows[-1]
    say = (f"{worst['name']} takes {num(worst['hoursPerClosing'], 1)} hours per closing; "
           f"{best['name']} takes {num(best['hoursPerClosing'], 1)}.")
    acts = [r for r in led.breakdown("activity") if r["hours"] >= 10]
    if acts:
        w = min(acts, key=lambda r: r["incomePerHour"] or 0)
        say += f" Your weakest use of time is {w['name']}: {num(w['hours'])} hours for {money(w['income'])}."
    return reply("efficiency", say, cards=[{"title": r["name"], "subtitle": f"{num(r['hoursPerProspect'], 1)} h per prospect",
                                            "value": f"{num(r['hoursPerClosing'], 1)} h/closing"} for r in rows])


def h_roi(conn, t, now):
    led = calc.ledger(conn, "ytd")
    rows = [r for r in led.pillar_roi() if r["key"] not in ("overhead", "total") and r["roiWithTime"] is not None]
    rows.sort(key=lambda r: -r["roiWithTime"])
    best, worst = rows[0], rows[-1]
    say = (f"Counting your time and money, {best['name']} returns {money(best['roiWithTime'] + 1, cents=True)} per dollar "
           f"invested, and {worst['name']} returns {money(worst['roiWithTime'] + 1, cents=True)}. "
           f"Your overall net ROI is {pct(led.net_roi)}.")
    return reply("roi", say, cards=[{"title": r["name"], "subtitle": f"Profit {money(r['profitWithTime'])}",
                                     "value": f"{r['roiWithTime']:.2f}×"} for r in rows])


def h_index(conn, t, now):
    led = calc.ledger(conn, "ytd")
    w = index_widget(led)
    drivers = sorted(w["drivers"], key=lambda d: d["ratio"] or 0)
    weakest = drivers[0]
    say = (f"Your Logsperity Index is {w['display']} — {w['label'].lower()}. 100 is a healthy business. "
           f"The biggest lever is {weakest['label'].lower()}: {weakest['display']} against a benchmark of "
           f"{weakest['benchmarkDisplay']}.")
    return reply("index", say, cards=[{"title": d["label"], "subtitle": f"Benchmark {d['benchmarkDisplay']}",
                                       "value": d["display"]} for d in w["drivers"]])


def h_top_sources(conn, t, now):
    led = calc.ledger(conn, "ytd")
    rows = led.breakdown("source")
    if re.search(r"realtor|agent", t, re.I):
        rows = [r for r in rows if r["key"] and conn.execute(
            "SELECT 1 FROM prospects WHERE source_id = ? AND category_id = 'cat.realtor' LIMIT 1", (r["key"],)).fetchone()]
    rows = sorted([r for r in rows if r["income"] and r["name"] not in NO_SOURCE], key=lambda r: -r["income"])[:3]
    if not rows:
        return reply("top_sources", "No income has been credited to a source yet this year.")
    say = "By income earned: " + "; ".join(f"{r['name']} {money(r['income'])} from {r['closings']} closings"
                                           for r in rows) + "."
    vol = max((r for r in led.breakdown("source") if r["name"] not in NO_SOURCE), key=lambda r: r["prospects"])
    if vol["key"] not in [r["key"] for r in rows]:
        say += f" {vol['name']} sent the most prospects — {vol['prospects']} — but only {vol['closings']} closed."
    return reply("top_sources", say, cards=[{"title": r["name"], "subtitle": f"{r['closings']} of {r['prospects']} closed",
                                             "value": money(r["income"])} for r in rows])


def h_income_summary(conn, t, now):
    led = calc.ledger(conn, "ytd")
    goal = led.plan["grossIncomeGoal"]
    say = (f"You've earned {money(led.income_total)} this year: {money(led.closing_income)} from "
           f"{led.n_closings} closings and {money(led.nontrans_income)} of other income. "
           f"That's {pct(ratio(led.income_total, goal))} of your {money_k(goal)} goal.")
    return reply("income_summary", say)


def h_expenses_summary(conn, t, now):
    led = calc.ledger(conn, "ytd")
    by = {}
    for e in led.expenses:
        by[e["group_id"]] = by.get(e["group_id"], 0) + e["amount"]
    top = sorted(by.items(), key=lambda kv: -kv[1])[:2]
    missing = [e for e in led.expenses if e["amount"] >= 75 and not e["has_receipt"]]
    say = (f"Expenses this year are {money(led.expenses_total)}, including {money(led.mileage_deduction)} of mileage. "
           f"The biggest groups are " + " and ".join(f"{tx.EXPENSE_GROUP_NAME[g]} at {money(v)}" for g, v in top) + ".")
    if missing:
        say += f" {len(missing)} expenses over 75 dollars are missing receipts."
    return reply("expenses_summary", say)


def h_mileage_summary(conn, t, now):
    led = calc.ledger(conn, "ytd")
    say = (f"{num(led.business_miles)} business miles this year, worth {money(led.mileage_deduction)} at the "
           f"IRS rates — 72.5 cents through June and 76 cents from July.")
    return reply("mileage_summary", say)


REPORT_WORDS = [(r"profit and loss|p ?& ?l|p and l", "pnl"), (r"conversion", "conversion"), (r"mileage|miles", "mileage"),
                (r"expense", "expenses"), (r"income", "income"), (r"prospect", "prospects"), (r"closing", "closings"),
                (r"business plan|plan", "business_plan"), (r"index", "index"), (r"activit", "activity"),
                (r"annual|year[- ]end|complete", "annual_complete"), (r"roi|return", "profit_roi"),
                (r"year to date|ytd", "ytd"), (r"coaching", "coaching_advice")]


def h_report(conn, t, now):
    tl = t.lower()
    key, title = None, None
    for i, mname in enumerate(MONTH_NAMES):
        if re.search(rf"\b{mname}\b", tl):
            key, title = f"month_{i + 1:02d}", f"{mname.capitalize()} report"
            break
    if not key and "last month" in tl:
        lm = (now.replace(day=1) - timedelta(days=1)).month
        key, title = f"month_{lm:02d}", f"{MONTH_NAMES[lm - 1].capitalize()} report"
    if not key and "this month" in tl:
        key, title = f"month_{now.month:02d}", f"{MONTH_NAMES[now.month - 1].capitalize()} report"
    if not key:
        for pat, k in REPORT_WORDS:
            if re.search(pat, tl):
                key = k
                break
    key = key or "ytd"
    import reports  # local import: reports imports herb
    title = title or reports.REPORT_TITLES.get(key, "report")
    emailing = bool(re.search(r"\bemail|send\b", tl))
    say = f"Here's your {title}." + (" Tap Email it and I'll open Mail with the report — you press send."
                                     if emailing else "")
    actions = [{"label": "Open report", "action": "open", "target": f"report:{key}"}]
    if emailing:
        actions.append({"label": "Email it", "action": "open", "target": f"email:{key}"})
    return reply("report", say, actions=actions)


def h_plan(conn, t, now):
    p = calc.plan_json(conn, now.year)
    i, o = p["inputs"], p["outputs"]
    say = (f"Your {now.year} plan: {money(i['grossIncomeGoal'])} gross and {money(i['netProfitGoal'])} net. "
           f"That takes {num(o['annualTransactions'], 1)} transactions, about {money_k(o['annualVolume'])} of volume, "
           f"and works out to {money(o['hourlyGross'])} an hour.")
    ext = p["extended"]
    if ext.get("prospectsNeeded"):
        say += (f" At your {pct(ext['conversion'])} conversion you need about {num(ext['prospectsNeeded'])} prospects — "
                f"{num(ext['prospectsPerWeek'], 1)} a week.")
    return reply("plan", say, actions=[{"label": "Open Business Plan", "action": "open", "target": "plan"}])


def h_review(conn, t, now):
    items = review_items(conn, now)
    if not items:
        return reply("review", "Nothing needs you right now — everything I logged has been reviewed.")
    say = f"{len(items)} quick questions. First: {items[0]['question']}"
    return reply("review", say, cards=[{"title": i["title"], "subtitle": i["question"], "chip": i["capture"]}
                                       for i in items[:6]],
                 actions=[{"label": "Open review", "action": "open", "target": "review"}])


def h_help(conn, t, now):
    say = ("I can log things for you — new prospects, closings, income, expenses, trips and activity time — just say "
           "them, and I'll ask about anything you leave out. I can update a contact too, like \"I called Priya Shah, "
           "follow up in two weeks.\" And I can answer questions like: what should I focus on this week, am I on "
           "track, which sources never close, or where am I wasting time.")
    return reply("help", say)


def h_smalltalk(conn, t, now):
    if re.search(r"thank", t, re.I):
        return reply("smalltalk", "Anytime.")
    hour = datetime.now().hour
    part = "morning" if hour < 12 else "afternoon" if hour < 17 else "evening"
    return reply("smalltalk", f"Good {part}, {first_name(conn)}. Ask me what to focus on this week, "
                              f"or tell me about a new lead.", follow_up=True)


def h_unknown(conn, t, now):
    return reply("unknown", "I'm not sure how to help with that yet. Try \"What should I focus on this week?\" "
                            "or \"New lead, Kevin Morales, Ruth Alvarez sent him.\"", follow_up=True)


HANDLERS = {"log_expense": h_log_expense, "log_trip": h_log_trip,
            "focus": h_focus, "follow_ups": h_follow_ups, "pace": h_pace, "conversion": h_conversion,
            "sources_no_close": h_sources_no_close, "efficiency": h_efficiency, "roi": h_roi, "index": h_index,
            "top_sources": h_top_sources, "income_summary": h_income_summary,
            "expenses_summary": h_expenses_summary, "mileage_summary": h_mileage_summary, "review": h_review,
            "report": h_report, "plan": h_plan, "help": h_help, "smalltalk": h_smalltalk, "unknown": h_unknown}


def confirm(conn, draft, save):
    """Save a confirmed draft via the server's log writer (`save(log, data[, id]) -> row`); a draft with an id
    updates that record."""
    log = draft.get("log")
    data = dict(draft.get("data") or {})
    row = save(log, data, draft["id"]) if draft.get("id") else save(log, data)
    if draft.get("id"):
        return {"ok": True, "say": "Updated.", "row": row}
    say = {"prospects": "Saved. I'll remind you to follow up.", "closings": "Saved, and added to your income log.",
           "income": "Income saved.", "expenses": "Expense saved.", "trips": "Trip saved.",
           "activities": "Activity saved."}.get(log, "Saved.")
    return {"ok": True, "say": say, "row": row}


# ======================================================================= coaching (§16)

def index_widget(led):
    v = led.index
    label = ("No data yet" if v is None else "Below the healthy baseline" if v < 90 else "Healthy" if v < 110
             else "Strong" if v < 150 else "Very strong")
    b = calc.INDEX_BENCHMARKS
    drivers = [
        {"key": "conversion", "label": "Conversion", "value": led.conversion, "display": pct(led.conversion),
         "benchmark": b["conversion"], "benchmarkDisplay": pct(b["conversion"]),
         "ratio": ratio(led.conversion or 0, b["conversion"])},
        {"key": "netRoi", "label": "Net ROI", "value": led.net_roi, "display": pct(led.net_roi),
         "benchmark": b["netRoi"], "benchmarkDisplay": pct(b["netRoi"]), "ratio": ratio(led.net_roi or 0, b["netRoi"])},
        {"key": "margin", "label": "Profit margin", "value": led.margin, "display": pct(led.margin),
         "benchmark": b["margin"], "benchmarkDisplay": pct(b["margin"]), "ratio": ratio(led.margin or 0, b["margin"])},
    ]
    return {"type": "index", "title": "Logsperity Index", "value": v, "display": num(v) if v is not None else "—",
            "label": label, "drivers": drivers}


def partner_drift(conn, now, days=30):
    """Referral partners with closings whose last touch is older than `days`."""
    out = []
    partners = db.rows(conn.execute(
        "SELECT s.id, s.name, COUNT(c.id) AS closings, SUM(c.income) AS income FROM sources s "
        "JOIN closings c ON c.source_id = s.id WHERE s.kind = 'person' AND c.sub_pillar = 'professional' "
        "AND c.date >= ? GROUP BY s.id", ((now - timedelta(days=365)).isoformat(),)))
    for p in partners:
        last = conn.execute(
            "SELECT MAX(d) FROM (SELECT MAX(date) d FROM activities WHERE source_id = :s UNION ALL "
            "SELECT MAX(date) FROM expenses WHERE source_id = :s UNION ALL "
            "SELECT MAX(date) FROM prospects WHERE source_id = :s)", {"s": p["id"]}).fetchone()[0]
        if last:
            gap = (now - date.fromisoformat(last)).days
            if gap > days:
                out.append({**p, "lastTouch": last, "daysSince": gap})
    return sorted(out, key=lambda p: -(p["income"] or 0))


def follow_ups(conn, now):
    items = []
    rows = db.rows(conn.execute(
        "SELECT p.*, s.name AS source_name FROM prospects p LEFT JOIN closings c ON c.prospect_id = p.id "
        "LEFT JOIN sources s ON s.id = p.source_id WHERE c.id IS NULL AND p.strength != 'no_go' "
        "AND p.follow_up BETWEEN ? AND ? ORDER BY p.follow_up",
        ((now - timedelta(days=14)).isoformat(), now.isoformat())))
    for p in rows:
        fu = date.fromisoformat(p["follow_up"])
        created = date.fromisoformat(p["date"])
        chip = "late" if fu < now else "today"
        if (now - created).days <= 7 and p["strength"] in ("hot", "red_hot") and fu < now:
            chip = "new"
        reason = p["notes"] or f"{tx.STRENGTH_NAME.get(p['strength'], '')} prospect · via {p['source_name'] or '—'}"
        score = (100 if fu < now else 40) + (30 if p["strength"] == "red_hot" else 15 if p["strength"] == "hot" else 0) \
            + (20 if chip == "new" else 0)
        items.append({"id": f"prospect:{p['id']}", "kind": "prospect", "prospectId": p["id"],
                      "name": f"{p['first_names']} {p['last_name']}", "reason": reason, "due": p["follow_up"],
                      "chip": chip, "strength": p["strength"], "score": score})
    for d in partner_drift(conn, now)[:2]:
        items.append({"id": f"partner:{d['id']}", "kind": "partner", "prospectId": None, "name": d["name"],
                      "reason": f"Referral partner · {d['daysSince']} days since last contact "
                                f"({d['closings']} closings, {money(d['income'])} this year)",
                      "due": now.isoformat(), "chip": "soon", "score": 20 + min(40, (d["income"] or 0) / 1000)})
    for c in db.rows(conn.execute(
            "SELECT c.*, p.first_names, p.last_name FROM closings c JOIN prospects p ON p.id = c.prospect_id "
            "WHERE c.referral_request LIKE 'ask_%'")):
        due = date.fromisoformat(c["date"]) + timedelta(days=int(c["referral_request"].split("_")[1]))
        if now - timedelta(days=7) <= due <= now:
            items.append({"id": f"closing:{c['id']}", "kind": "review", "prospectId": c["prospect_id"],
                          "name": f"{c['first_names']} {c['last_name']}",
                          "reason": f"Ask for a review or referral — closed {fmt_day(date.fromisoformat(c['date']), now)}",
                          "due": due.isoformat(), "chip": "today", "score": 30})
    items.sort(key=lambda i: -i["score"])
    return items


def insights(conn, now=None, period="ytd"):
    """Coaching rules §16.3 fired on the user's own numbers."""
    now = now or calc.today()
    led = calc.ledger(conn, period)
    out = []

    def add(key, level, title, text, numbers=None, sample=None, impact=0.0):
        out.append({"key": key, "level": level, "title": title, "text": text, "numbers": numbers or {},
                    "sample": sample, "impact": impact})

    avg_inc = led.avg_closing_income or led.plan["avgCommission"]
    # plan pace
    tr = calc.plan_tracking(conn, now.year, now)
    for it in tr["items"]:
        if it["key"] in ("income", "profit") and it["pacePct"] is not None:
            if it["pacePct"] < 0.95:
                gap = it["projected"] - it["actual"]
                add(f"pace.{it['key']}", "concern", f"{it['label']} is behind pace",
                    f"You're {pct(1 - it['pacePct'])} behind {it['label'].lower()} pace "
                    f"({it['display']['actual']} vs {it['display']['projected']} projected). "
                    f"The smallest fix: about {num(max(1, gap / avg_inc), 1)} more closings.",
                    {"actual": it["actual"], "projected": it["projected"]}, None, gap)
            elif it["pacePct"] >= 1.05:
                add(f"pace.{it['key']}", "win", f"{it['label']} is ahead of pace",
                    f"{it['label']} is at {pct(it['pacePct'])} of pace — {it['display']['actual']} vs "
                    f"{it['display']['projected']} projected by today.", {"pacePct": it["pacePct"]}, None, 0)
    # conversion watch / concern by category and activity
    for dim in ("category", "activity"):
        for r in led.breakdown(dim):
            if r["closings"] == 0 and r["prospects"] >= 4:
                add(f"conv.{dim}.{r['key']}", "concern", f"{r['name']}: {r['prospects']} prospects, 0 closings",
                    f"{r['name']} has produced {r['prospects']} prospects and no closings. Four or more with none "
                    f"is a concern — consider dropping it or changing your approach.",
                    {"prospects": r["prospects"], "closings": 0}, r["prospects"], r["hours"] * 50 + r["prospects"] * 100)
            elif r["closings"] == 0 and r["prospects"] >= 2:
                add(f"conv.{dim}.{r['key']}", "watch", f"Watch {r['name']}",
                    f"{r['name']}: {r['prospects']} prospects, no closings yet (early signal — keep an eye on it).",
                    {"prospects": r["prospects"]}, r["prospects"], r["prospects"] * 20)
    # sources that never convert
    for r in no_close_sources(led, 4):
        add(f"source.{r['key']}", "concern", f"{r['name']} never converts",
            f"{r['name']} sent {r['prospects']} prospects and none closed"
            + (f", and cost you {money(r['expenses'])} this year" if r["expenses"] else "")
            + ". Time to move on, or coach the source.", {"prospects": r["prospects"], "spent": r["expenses"]},
            r["prospects"], r["expenses"] + r["prospects"] * 100)
    # zombie recurring expense: ≥3 charges and no closings from that source
    for v in db.rows(conn.execute(
            "SELECT vendor, source_id, COUNT(*) n, SUM(amount) total FROM expenses WHERE date BETWEEN ? AND ? "
            "AND group_id IN ('ad_internet','ad_traditional','technology','prospecting') GROUP BY vendor "
            "HAVING n >= 3", (led.period.frm.isoformat(), led.period.to.isoformat()))):
        if v["source_id"]:
            closes = conn.execute("SELECT COUNT(*) FROM closings WHERE source_id = ? AND date BETWEEN ? AND ?",
                                  (v["source_id"], led.period.frm.isoformat(), led.period.to.isoformat())).fetchone()[0]
            if closes == 0:
                add(f"zombie.{v['vendor']}", "concern", f"{v['vendor']} isn't paying off",
                    f"You've paid {money(v['total'])} for {v['vendor']} this year ({v['n']} charges) with no closings "
                    f"from it. Consider cancelling.", {"spent": v["total"], "charges": v["n"]}, None, v["total"])
    # closings: biggest average deal by pillar
    pil = [r for r in led.breakdown("pillar") if r["closings"] >= 2]
    if pil:
        b = max(pil, key=lambda r: r["avgVolume"] or 0)
        add("closings.volume", "info", f"{b['name']} closes your biggest deals",
            f"{b['name']} averages {money_k(b['avgVolume'])} per closing vs {money_k(led.avg_volume)} overall. "
            f"Bigger deals mean more income per closing.", {"avgVolume": b["avgVolume"]}, b["closings"], 0)
    # income: best income per closing by category
    cats = [r for r in led.breakdown("category") if r["closings"] >= 2]
    if cats:
        c = max(cats, key=lambda r: r["avgIncome"] or 0)
        add("income.category", "win", f"{c['name']} pays best per closing",
            f"{c['name']} brought {money(c['closingIncome'])} from {c['closings']} closings — "
            f"{money(c['avgIncome'])} each.", {"avgIncome": c["avgIncome"]}, c["closings"], 0)
    # efficiency: hours per closing > 2x best
    eff = [r for r in led.breakdown("pillar") if r["closings"] and r["hours"]]
    if len(eff) >= 2:
        best = min(eff, key=lambda r: r["hoursPerClosing"])
        worst = max(eff, key=lambda r: r["hoursPerClosing"])
        if worst["hoursPerClosing"] > 2 * best["hoursPerClosing"]:
            moved = 4 * 52 / best["hoursPerClosing"] - 4 * 52 / worst["hoursPerClosing"]
            add("efficiency.pillar", "concern", f"{worst['name']} takes too long per closing",
                f"{worst['name']} takes {num(worst['hoursPerClosing'], 1)} hours per closing vs "
                f"{num(best['hoursPerClosing'], 1)} for {best['name']}. Moving 4 hours a week could add about "
                f"{num(moved, 1)} closings a year.", {"worst": worst["hoursPerClosing"], "best": best["hoursPerClosing"]},
                worst["closings"], moved * avg_inc)
    # time sink activity: lots of hours, little income
    target = led.plan_out["hourlyGross"]
    for r in led.breakdown("activity"):
        if r["hours"] >= 20 and (r["incomePerHour"] or 0) < target:
            add(f"timesink.{r['key']}", "concern", f"{r['name']} is a time sink",
                f"{num(r['hours'])} hours on {r['name']} this year produced {money(r['income'])} — "
                f"{money(r['incomePerHour'] or 0)} an hour against your {money(target)} target.",
                {"hours": r["hours"], "income": r["income"]}, r["prospects"], r["hours"] * target)
    # ROI with time
    roi = [r for r in led.pillar_roi() if r["key"] not in ("overhead", "total") and r["roiWithTime"] is not None]
    if roi:
        w = min(roi, key=lambda r: r["roiWithTime"])
        b = max(roi, key=lambda r: r["roiWithTime"])
        if w["roiWithTime"] < 1.5:
            add("roi.pillar", "watch", f"{w['name']} has the lowest return",
                f"{w['name']} returns {money(w['roiWithTime'] + 1, cents=True)} per dollar of time and money; "
                f"{b['name']} returns {money(b['roiWithTime'] + 1, cents=True)}.", {"roi": w["roiWithTime"]}, None, 0)
    # partner drift
    for d in partner_drift(conn, now)[:2]:
        add(f"drift.{d['id']}", "watch", f"Reconnect with {d['name']}",
            f"{d['name']} sent {d['closings']} closings ({money(d['income'])}) in the last year, but it's been "
            f"{d['daysSince']} days since you were in touch.", {"days": d["daysSince"]}, d["closings"],
            (d["income"] or 0) / 4)
    # prospects with no known source (D3): they count, but nothing can be learned from them
    blind = sum(r["prospects"] for r in led.breakdown("source") if r["name"] in NO_SOURCE)
    if blind:
        add("source.unknown", "info", f"{num(blind)} prospect{'s' if blind != 1 else ''} with no source",
            f"{num(blind)} prospect{'s' if blind != 1 else ''} this period {'have' if blind != 1 else 'has'} no known "
            f"source, so they can't show which sources pay. Fill them in from the Review queue.",
            {"prospects": blind}, None, blind * 10)
    # missing receipts
    missing = [e for e in led.expenses if e["amount"] >= 75 and not e["has_receipt"]]
    if missing:
        add("receipts.missing", "info", f"{len(missing)} receipts missing",
            f"{len(missing)} expenses of $75 or more have no receipt. Snap them so they hold up in an audit.",
            {"count": len(missing)}, None, 10)
    # logging gap
    last = conn.execute("SELECT MAX(date) FROM activities").fetchone()[0]
    if last and (now - date.fromisoformat(last)).days > 3:
        add("logging.gap", "info", "Nothing logged lately",
            f"No business-building time logged since {fmt_day(date.fromisoformat(last), now)}.", {}, None, 5)
    dismissed = {r[0] for r in conn.execute("SELECT rule_key FROM insight_dismissals")}
    out = [i for i in out if i["key"] not in dismissed]
    rank = {"concern": 0, "watch": 1, "win": 2, "info": 3}
    out.sort(key=lambda i: (rank[i["level"]], -i["impact"]))
    return out


def focus(conn, now=None):
    """§16.4: top 3 actions by expected value per hour, plus one thing to drop."""
    now = now or calc.today()
    led = calc.ledger(conn, "ytd")
    avg_inc = led.avg_closing_income or led.plan["avgCommission"]
    cands = []
    hot = db.rows(conn.execute(
        "SELECT p.* FROM prospects p LEFT JOIN closings c ON c.prospect_id = p.id WHERE c.id IS NULL "
        "AND p.strength IN ('red_hot','hot') AND p.follow_up <= ? AND p.date >= ? "
        "ORDER BY CASE p.strength WHEN 'red_hot' THEN 0 ELSE 1 END, p.follow_up",
        ((now + timedelta(days=3)).isoformat(), (now - timedelta(days=60)).isoformat())))
    if hot:
        value = sum(calc.STRENGTH_PROBABILITY[p["strength"]] for p in hot) * avg_inc
        names = ", ".join(p["first_names"] + " " + p["last_name"] for p in hot[:3])
        cands.append({"title": f"Call your {len(hot)} hot prospects", "why": f"{names} — about {money_k(value)} of "
                      f"likely income.", "value": money_k(value), "hours": 0.25 * len(hot), "ev": value,
                      "boost": 2.0})
    acts = [r for r in led.breakdown("activity") if r["hours"] >= 5 and r["incomePerHour"]]
    if acts:
        b = max(acts, key=lambda r: r["incomePerHour"])
        cands.append({"title": f"2 hours of {b['name']}", "why": f"Your best return on time — {money(b['incomePerHour'])} "
                      f"an hour, {pct(b['conversion'])} conversion.", "value": money(b["incomePerHour"] * 2),
                      "hours": 2, "ev": b["incomePerHour"] * 2 * 0.5, "boost": 1.0, "activityId": b["key"]})
    for d in partner_drift(conn, now)[:1]:
        cands.append({"title": f"Coffee with {d['name']}", "why": f"{d['closings']} closings ({money(d['income'])}) "
                      f"in the last year, but {d['daysSince']} days since you talked.", "value": money(d["income"] / 12),
                      "hours": 1.5, "ev": (d["income"] or 0) / 12, "boost": 1.2,
                      "activityId": "act.relationship_building_professional"})
    reviews = [i for i in follow_ups(conn, now) if i["kind"] == "review"]
    if reviews:
        cands.append({"title": f"Ask {reviews[0]['name']} for a review", "why": "Your closing follow-up is due — "
                      "past clients are your best source.", "value": None, "hours": 0.25, "ev": avg_inc * 0.1,
                      "boost": 1.0})
    for c in cands:
        c["score"] = c["ev"] / max(0.25, c["hours"]) * c["boost"]
    items = sorted(cands, key=lambda c: -c["score"])[:3]
    drop = None
    weak = [r for r in led.breakdown("activity") if r["hours"] >= 10 and r["closings"] <= 1]
    if weak:
        w = min(weak, key=lambda r: r["incomePerHour"] or 0)
        drop = {"title": w["name"], "why": f"{num(w['hours'])} hours this year, {w['closings']} closing"
                f"{'' if w['closings'] == 1 else 's'} — {money(w['incomePerHour'] or 0)} an hour.",
                "activityId": w["key"]}
    say = "Three things this week: " + " ".join(f"{i + 1}. {c['title']} — {c['why']}" for i, c in enumerate(items))
    if drop:
        say += f" One to drop: {drop['title']}. {drop['why']}"
    for c in items:
        for k in ("score", "ev", "boost"):
            c.pop(k, None)
    return {"say": say, "items": items, "drop": drop}


def last_week_range(now):
    this_monday = now - timedelta(days=now.weekday())
    return this_monday - timedelta(days=7), this_monday - timedelta(days=1)


def checkin(conn, body=None, now=None):
    """§16.2 weekly check-in. Posting commitments saves a new check-in."""
    now = now or calc.today()
    body = body or {}
    a, b = last_week_range(now)
    week = calc.Ledger(conn, calc.Period("custom", "Last week", a, b), now)
    plan = calc.plan_json(conn, now.year)
    weeks = 52 - float(plan["inputs"]["vacationWeeks"] or 0)
    tgt_closings = plan["outputs"]["annualTransactions"] / weeks
    tgt_income = plan["inputs"]["grossIncomeGoal"] / weeks
    ext = plan["extended"]
    tgt_prospects = ext.get("prospectsPerWeek") or 0
    tgt_hours = ext.get("bbHoursPerWeek") or 0
    steps = []
    score = (f"Last week: {week.n_prospects} prospects (goal {num(tgt_prospects, 1)}), {week.n_closings} closings "
             f"(goal {num(tgt_closings, 1)}), {money(week.income_total)} income (goal {money(tgt_income)}), "
             f"{num(week.bb_hours, 1)} business-building hours (goal {num(tgt_hours, 1)}).")
    steps.append({"title": "Score vs plan", "text": score, "say": score})
    acts = sorted(week.breakdown("activity"), key=lambda r: (-r["prospects"], -r["hours"]))
    win_row = acts[0] if acts else None
    if win_row and win_row["prospects"]:
        win = f"{win_row['name']} produced {win_row['prospects']} prospects from {num(win_row['hours'], 1)} hours."
    elif week.n_closings:
        win = f"You closed {week.n_closings} {'deal' if week.n_closings == 1 else 'deals'} for {money(week.closing_income)}."
    else:
        win = f"You put in {num(week.bb_hours, 1)} hours of business-building time."
    steps.append({"title": "One win", "text": win, "say": win})
    gaps = [("prospects", week.n_prospects, tgt_prospects), ("closings", week.n_closings, tgt_closings),
            ("business-building hours", week.bb_hours, tgt_hours)]
    gaps = [(n, v, t, ratio(v, t) or 0) for n, v, t in gaps if t]
    g = min(gaps, key=lambda x: x[3]) if gaps else None
    gap = (f"Biggest gap: {g[0]} — {num(g[1], 1)} against {num(g[2], 1)}." if g and g[3] < 1
           else "No gaps last week — you hit every weekly target.")
    steps.append({"title": "Biggest gap", "text": gap, "say": gap})
    last = db.one(conn.execute("SELECT * FROM checkins ORDER BY date DESC, id DESC LIMIT 1"))
    review_lines = []
    if last:
        for c in db.rows(conn.execute("SELECT * FROM commitments WHERE checkin_id = ?", (last["id"],))):
            mins = conn.execute("SELECT COALESCE(SUM(minutes),0) FROM activities WHERE activity_id = ? AND date >= ?",
                                (c["activity_id"], last["date"])).fetchone()[0] if c["activity_id"] else 0
            achieved = mins / 60
            if "jared" in (c["text"] or "").lower():
                achieved = conn.execute("SELECT COUNT(*) FROM activities a JOIN sources s ON s.id = a.source_id "
                                        "WHERE s.name = 'Jared Cole' AND a.date >= ?", (last["date"],)).fetchone()[0]
            done = achieved >= (c["target"] or 1)
            review_lines.append(f"{'✓' if done else '✗'} {c['text']} ({num(achieved, 1)} of {c['target']})")
    commit_text = ("Last week's commitments: " + "; ".join(review_lines) + ".") if review_lines else \
        "No commitments from last week."
    steps.append({"title": "Last week's commitments", "text": commit_text,
                  "say": commit_text.replace("✓", "done:").replace("✗", "not done:")})
    f = focus(conn, now)
    steps.append({"title": "This week's focus", "text": f["say"], "say": f["say"]})
    led = calc.ledger(conn, "ytd")
    prev = json.loads(last["json"]).get("index") if last and last["json"] else None
    idx = led.index
    idx_text = f"Your Logsperity Index is {num(idx)}" + (
        f", {'up' if idx >= prev else 'down'} {num(abs(idx - prev), 1)} since the last check-in." if prev else ".")
    steps.append({"title": "Logsperity Index", "text": idx_text, "say": idx_text})
    proposed = [{"text": c["title"], "activityId": c.get("activityId"), "target": int(round(c["hours"])) or 1}
                for c in f["items"]]
    if body.get("commitments") is not None:
        cid = conn.execute("INSERT INTO checkins(date, json) VALUES(?, ?)",
                           (now.isoformat(), json.dumps({"index": idx}))).lastrowid
        for c in body["commitments"]:
            conn.execute("INSERT INTO commitments(checkin_id, text, activity_id, target, due) VALUES(?,?,?,?,?)",
                         (cid, c.get("text"), c.get("activityId") or c.get("activity_id"), c.get("target") or 1,
                          (now + timedelta(days=6)).isoformat()))
        conn.commit()
    return {"steps": steps, "commitments": proposed}


def coach(conn, now=None):
    now = now or calc.today()
    led = calc.ledger(conn, "ytd")
    w = index_widget(led)
    tr = calc.plan_tracking(conn, now.year, now)
    last = db.one(conn.execute("SELECT date FROM checkins ORDER BY date DESC LIMIT 1"))
    return {"index": {"value": w["value"], "display": w["display"], "label": w["label"], "drivers": w["drivers"],
                      "trend": calc.index_trend(conn, now.year, now)},
            "plan": {"items": tr["items"], "elapsedFraction": tr["elapsedFraction"], "forecast": tr["forecast"]},
            "insights": [{k: v for k, v in i.items() if k != "impact"} for i in insights(conn, now)],
            "focus": focus(conn, now), "lastCheckin": last["date"] if last else None}


def today_view(conn, now=None):
    now = now or calc.today()
    led = calc.ledger(conn, "ytd")
    tr = calc.plan_tracking(conn, now.year, now)
    inc = next(i for i in tr["items"] if i["key"] == "income")
    hour = datetime.now().hour
    part = "morning" if hour < 12 else "afternoon" if hour < 17 else "evening"
    ins = insights(conn, now)
    return {
        "date": now.isoformat(),
        "greeting": f"Good {part}, {first_name(conn)}",
        "kpis": [
            {"key": "income", "label": "Income YTD", "value": led.income_total, "display": money_k(led.income_total),
             "sub": f"{pct(inc['pacePct'])} of pace"},
            {"key": "closings", "label": "Closings YTD", "value": led.n_closings, "display": str(led.n_closings),
             "sub": f"{money_k(led.volume)} volume"},
            {"key": "prospects", "label": "Prospects YTD", "value": led.n_prospects, "display": str(led.n_prospects),
             "sub": f"{pct(led.conversion)} convert"},
            {"key": "index", "label": "Logsperity Index", "value": led.index, "display": num(led.index),
             "sub": index_widget(led)["label"]},
        ],
        "focus": focus(conn, now)["items"],
        "followUps": follow_ups(conn, now),
        "reviewCount": len(review_items(conn, now)),
        "insight": {"text": ins[0]["text"], "level": ins[0]["level"], "title": ins[0]["title"]} if ins else None,
        "index": {"value": led.index},
    }


# ----------------------------------------------------------------------- review queue (§6.4)

def review_items(conn, now=None):
    now = now or calc.today()
    items = []
    srcs = {r["id"]: r["name"] for r in conn.execute("SELECT id, name FROM sources")}
    for t in db.rows(conn.execute("SELECT * FROM trips WHERE reviewed = 0 ORDER BY date DESC, id")):
        miles = calc.trip_miles(t)
        items.append({"id": f"trips:{t['id']}", "log": "trips", "capture": t["capture"],
                      "title": f"{miles:.1f} mi → {t['destination']}",
                      "subtitle": f"{fmt_day(date.fromisoformat(t['date']), now).capitalize()} · detected by GPS",
                      "question": f"Business trip to {t['destination']}?",
                      "fields": {"isBusiness": bool(t["is_business"]), "reason": t["reason"],
                                 "destination": t["destination"], "miles": miles},
                      "suggestions": {"reason": t["reason"],
                                      "deduction": money(miles * tx.mileage_rate(t["date"]), cents=True)}})
    for e in db.rows(conn.execute("SELECT * FROM expenses WHERE reviewed = 0 ORDER BY date DESC, id")):
        meta = tx.EXPENSE_CATEGORY_BY_ID.get(e["category_id"], {})
        how = {"bank": "Card transaction", "receipt": "Receipt photo"}.get(e["capture"], "Captured")
        q = f"{tx.EXPENSE_GROUP_NAME.get(e['group_id'], '')} · {meta.get('name', '?')}"
        if e["with_whom"]:
            q += f" with {e['with_whom']}"
        items.append({"id": f"expenses:{e['id']}", "log": "expenses", "capture": e["capture"],
                      "title": f"{money(e['amount'], cents=True)} · {e['vendor']}",
                      "subtitle": f"{how} · {fmt_day(date.fromisoformat(e['date']), now)}",
                      "question": q + "?",
                      "fields": {"groupId": e["group_id"], "categoryId": e["category_id"], "purpose": e["purpose"],
                                 "withWhom": e["with_whom"], "hasReceipt": bool(e["has_receipt"])},
                      "suggestions": {"categoryName": meta.get("name"), "irs": meta.get("irs"),
                                      "needsReceipt": e["amount"] >= 75 and not e["has_receipt"]}})
    for a in db.rows(conn.execute("SELECT * FROM activities WHERE reviewed = 0 ORDER BY date DESC, id")):
        name = tx.ACTIVITY_BY_ID.get(a["activity_id"], {}).get("name", "?")
        items.append({"id": f"activities:{a['id']}", "log": "activities", "capture": a["capture"],
                      "title": f"{fmt_minutes(a['minutes'])} · {name}",
                      "subtitle": (a["notes"] or "From your calendar") + f" · {fmt_day(date.fromisoformat(a['date']), now)}",
                      "question": f"Log this as {name}" + (f" with {srcs.get(a['source_id'])}" if a["source_id"] else "")
                                  + "?",
                      "fields": {"activityId": a["activity_id"], "minutes": a["minutes"], "pillar": a["pillar"]},
                      "suggestions": {"pillarName": tx.pillar_name(a["pillar"])}})
    for p in db.rows(conn.execute("SELECT * FROM prospects WHERE reviewed = 0 ORDER BY date DESC, id")):
        parked = re.search(r"HERB: still need (.+?)\.", p["notes"] or "")  # "finish later" from a conversation
        items.append({"id": f"prospects:{p['id']}", "log": "prospects", "capture": p["capture"],
                      "title": f"New prospect: {p['first_names']} {p['last_name']}",
                      "subtitle": p["notes"] or "Captured by voice",
                      "question": (f"Where did {p['first_names']} {p['last_name']} come from?"
                                   if parked.group(1) == "the source" else
                                   f"Finish {p['first_names']} {p['last_name']} — add {parked.group(1)}?") if parked else
                                  f"Save {p['first_names']} {p['last_name']} from {srcs.get(p['source_id'], '—')} "
                                  f"as a {tx.CATEGORY_BY_ID.get(p['category_id'], {}).get('name', '')} prospect?",
                      "fields": {"categoryId": p["category_id"], "activityId": p["activity_id"],
                                 "strength": p["strength"], "followUp": p["follow_up"]},
                      "suggestions": {"source": srcs.get(p["source_id"])}})
    for table in ("closings", "income"):
        for r in db.rows(conn.execute(f"SELECT * FROM {table} WHERE reviewed = 0 ORDER BY date DESC, id")):
            amt = r.get("income") if table == "closings" else r.get("amount")
            items.append({"id": f"{table}:{r['id']}", "log": table, "capture": r["capture"],
                          "title": f"{'Closing' if table == 'closings' else 'Deposit'} · {money(amt)}",
                          "subtitle": fmt_day(date.fromisoformat(r["date"]), now),
                          "question": "Confirm this " + ("closing?" if table == "closings" else "income?"),
                          "fields": {}, "suggestions": {}})
    return items


import dialog as D  # noqa: E402  (at the end: dialog.py imports this module)
