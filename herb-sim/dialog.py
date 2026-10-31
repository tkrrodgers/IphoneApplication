"""HERB conversation engine: follow-up questions for data entry (design §17.6).

Every log has a frame of slots. HERB fills what it can from what the user said, then asks for what is still
missing, one short question per turn:
  required     always asked; the record can't be saved without it
  recommended  asked in Balanced and Thorough modes
  thorough     asked only in Thorough mode
Optional contact fields are offered together ("Do you want to add an address and phone number?"). The user can
answer yes, no, "phone only", or just give the value. Anything can be corrected at any point ("make the
follow-up Friday"), and nothing is saved until the user says so.

The dialog state travels with each request (`dialog` in, `dialog` out), so the server stays stateless and the
iPhone app can keep it on the device. Extraction here is rule-based; on the iPhone the on-device model fills the
same frame, and this policy still decides what to ask next.
"""
import re
from datetime import date, timedelta

import calc
import db
import herb as H
import taxonomy as tx
from calc import money, pct, ratio


def _rx(p):
    return re.compile(p, re.I)


# ======================================================================= answer classification

YES = _rx(r"^(?:yes|yeah|yea|yep|yup|sure|ok(?:ay)?|please|absolutely|definitely|of course|go ahead|sounds good|"
          r"correct|right|that'?s right|do it|let'?s do it|uh[- ]?huh|both|all of (?:them|it)|why not|y)\b")
NO = _rx(r"^(?:no|nope|nah|not now|not really|not yet|skip(?: it| that)?|pass|none|negative|no thanks|"
         r"(?:i )?don'?t (?:have|know)(?: (?:it|that|one))?|leave it(?: blank)?|(?:i'?m )?not sure|unknown|nothing|"
         r"n)\b")
SAVE = _rx(r"^(?:save|yes|yeah|yep|yup|sure|ok(?:ay)?|correct|right|perfect|great|good|looks (?:good|right|great)|"
           r"sounds good|that'?s (?:it|all|right|correct|everything|good)|all good|done|confirm|go ahead|do it|y)\b")
CANCEL = _rx(r"^(?:cancel|never ?mind|forget (?:it|that|about it)|scratch that|discard(?: it)?|delete (?:it|that)|"
             r"don'?t save|stop|start over)\b")
EDIT = _rx(r"^(?:edit|open (?:the |it in the )?form|let me (?:fix|edit|type|change it myself)|i'?ll type)")
UNKNOWN = _rx(r"\b(?:don'?t know|do not know|no idea|not sure|unknown|can'?t remember|don'?t remember|no clue|"
              r"not certain|forgot|nobody|no one|called me|called in)\b")
UNKNOWN_SOURCE = "Unknown"
LATER = _rx(r"^(?:later|finish (?:it |this )?later|(?:save|hold|park) (?:it |this )?for later|remind me later|"
            r"i'?m driving|can'?t talk|i'?ll finish (?:it )?later)\b")
REPEAT = _rx(r"^(?:what\??|sorry\??|pardon(?: me)?\??|say (?:that|it) again|repeat(?: that)?|come again|huh\??)$")
DONE = _rx(r"^(?:no|nope|nah|that'?s (?:it|all|everything)|(?:i'?m |all )?done|no more|finished|not now)\b")
FILLER = _rx(r"^(?:(?:um+|uh+|er+|so|well|oh|okay so|ok so|alright|and)[,\s]+)+")
NEW_ENTRY = _rx(r"^(?:new (?:lead|prospect|client|contact)|another (?:lead|prospect)|"
                r"(?:log|record|add) (?:a |an |another )?(?:new )?(?:lead|prospect|expense|trip|activity|income|closing))\b")
BATCH = _rx(r"leads? to (?:record|add|log|enter)|(?:record|add|log|enter) (?:some |a few |my )?(?:new )?leads|"
            r"(?:some|a few|several|a couple of) (?:new )?leads|^new (?:leads|prospects)$")
ONLY = _rx(r"\b(?:only|just)\b")
NEG_WORD = _rx(r"\b(?:no|skip|without|don'?t (?:need|want|have)|not the)\b")


def clean(text):
    t = H.strip_wake(text or "")
    t = FILLER.sub("", t.strip())
    return t.strip().rstrip(".!").strip()


def is_question(t):
    return bool(H.QUESTION_START.match(t)) or t.endswith("?")


def cap(w):
    return w[:1].upper() + w[1:].lower() if (w.islower() or (w.isupper() and len(w) > 3)) else w


def caps(s):
    return " ".join(cap(w) for w in s.split())


def join_and(items):
    items = [i for i in items if i]
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1] if items else ""


def day_text(iso, now, time=None):
    if not iso:
        return "no follow-up"
    d = date.fromisoformat(iso)
    s = H.fmt_day(d, now)
    if 1 < (d - now).days < 7:
        s += f", {d:%b} {d.day}"
    return s + (f" {time}" if time else "")


# ======================================================================= names and places

PERSON = rf"{H.NAME_TOKEN}(?:\s+(?:&|and)\s+{H.NAME_TOKEN})?(?:\s+{H.NAME_TOKEN}){{1,2}}"
NAME_STOP = {"from", "referred", "sent", "phone", "cell", "mobile", "at", "who", "wants", "she", "he", "they", "is",
             "was", "lives", "follow", "call", "email", "number", "address", "with", "via", "through", "by", "on",
             "in", "for", "please", "thanks", "she's", "he's", "they're"}
LEAD_IN = _rx(r"^(?:it'?s|its|it is|this is|that'?s|the name is|name is|(?:his|her|their) name is|name'?s|"
              r"(?:his|her|their|the) (?:last|first) name is|(?:last|first) name is|it was|i think|"
              r"(?:he|she|they) (?:is|are|was|were)|from|by|at|the|an?|my|our)\s+")
SOLO = _rx(r"\b(?:just me|by myself|myself|alone|nobody|no one|solo|on my own)\b")


def lead_in(t):
    prev = None
    while prev != t:
        prev, t = t, LEAD_IN.sub("", t.strip(" ,"))
    return t


def bare_name(t, max_words=3):
    """A short free answer read as a name: 'sam lee' -> 'Sam Lee'."""
    if NO.match(t) or YES.match(t) or DONE.match(t):
        return None
    words = []
    for w in re.findall(r"[A-Za-z][A-Za-z'’.-]*|&", lead_in(t).split(",")[0]):
        if w.lower() in NAME_STOP:
            break
        words.append(w)
        if len(words) >= max_words:
            break
    return " ".join(cap(w) for w in words) or None


def clean_person(c):
    words = c.split()
    while words and words[0] in H.NOT_NAMES:
        words = words[1:]
    while words and words[-1] in H.NOT_NAMES:
        words = words[:-1]
    return " ".join(words) if len(words) >= 2 else None


def name_from(t, focus):
    out = {}
    m = re.search(r"\blast name(?:\s+is|'s|\s+should be)?\s+([A-Za-z'’-]+)", t, re.I)
    if m:
        out["lastName"] = cap(m.group(1))
    m = re.search(r"\bfirst name(?:\s+is|'s|\s+should be)?\s+([A-Za-z'’-]+)", t, re.I)
    if m:
        out["firstNames"] = cap(m.group(1))
    m = re.search(r"\bspell(?:ed|s)?(?: it)?\s+((?:[A-Za-z][\s.,-]+){2,}[A-Za-z])\b", t, re.I)
    if m:
        letters = re.findall(r"[A-Za-z]", m.group(1))
        out["firstNames" if focus == "name" and not out else "lastName"] = "".join(letters).capitalize()
    if out:
        return out
    if focus == "lastName":
        w = bare_name(t, 1)
        return {"lastName": w} if w else {}
    if focus == "name":
        n = bare_name(t)
        if not n:
            return {}
        if len(n.split()) == 1:
            return {"firstNames": n}
        first, last = H.split_name(n)
        return {"firstNames": first, "lastName": last}
    full = H.find_person_name(t)
    if full:
        first, last = H.split_name(full)
        return {"firstNames": first, "lastName": last}
    return {}


STATES = dict(zip(
    ("alabama alaska arizona arkansas california colorado connecticut delaware florida georgia hawaii idaho illinois "
     "indiana iowa kansas kentucky louisiana maine maryland massachusetts michigan minnesota mississippi missouri "
     "montana nebraska nevada new_hampshire new_jersey new_mexico new_york north_carolina north_dakota ohio oklahoma "
     "oregon pennsylvania rhode_island south_carolina south_dakota tennessee texas utah vermont virginia washington "
     "west_virginia wisconsin wyoming district_of_columbia").replace("_", "~").split(),
    ("AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR "
     "PA RI SC SD TN TX UT VT VA WA WV WI WY DC").split()))
STATES = {k.replace("~", " "): v for k, v in STATES.items()}
assert len(STATES) == 51
STATE_ABBRS = set(STATES.values())
STREET = (r"(?:lane|ln|street|st|drive|dr|road|rd|avenue|ave|court|ct|circle|cir|boulevard|blvd|way|place|pl|trail|"
          r"trl|parkway|pkwy|highway|hwy|loop|terrace|ter|cove|cv|crossing|xing|square|sq|plaza)")
ADDR_RE = re.compile(rf"\b(\d{{1,6}}[A-Za-z]?\s+(?:[A-Za-z0-9'’.-]+\s+){{0,4}}{STREET}\b\.?"
                     rf"(?:\s*,?\s*(?:apt|apartment|unit|suite|ste|#)\.?\s*[\w-]+)?)", re.I)
ADDR_LOOSE = re.compile(r"\b(\d{1,6}[A-Za-z]?(?:\s+[A-Za-z0-9'’.#-]+){1,5}?)\s*(?=,|\s+in\s|$)", re.I)
PLACE_TOKEN = re.compile(r"\s*([A-Za-z][A-Za-z'’.-]*|\d+|[,;])")
CITY_STOP = {"follow", "followup", "call", "phone", "cell", "mobile", "email", "wants", "referred", "sent", "next",
             "from", "he", "she", "they", "his", "her", "their", "and", "the", "to", "a", "an", "for", "is", "was",
             "on", "at", "by", "met", "lead", "prospect", "buyer", "looking", "tomorrow", "today", "tonight",
             "please", "with", "about", "who", "that", "loan", "purchase", "refinance", "refi", "hot", "cold",
             "warm", "zip", "it's", "he's", "she's", "they're", *H.WEEKDAYS}


def _state_at(toks, k):
    """(abbr, tokens used) when a state name starts at token k."""
    if k >= len(toks):
        return None
    w = toks[k][0]
    if w in STATE_ABBRS and w.isupper():
        return w, 1
    if k + 1 < len(toks) and f"{w} {toks[k + 1][0]}".lower() in STATES:
        return STATES[f"{w} {toks[k + 1][0]}".lower()], 2
    if w.lower() in STATES:
        return STATES[w.lower()], 1
    return None


def parse_address(text, focus=False, home_state=None):
    m = ADDR_RE.search(text) or (ADDR_LOOSE.search(text) if focus else None)
    if not m:
        return None
    street = " ".join(cap(w) if w.isalpha() else w for w in re.sub(r"\s+", " ", m.group(1)).strip(" ,").split())
    toks, i = [], m.end()
    while len(toks) < 12:
        mt = PLACE_TOKEN.match(text, i)
        if not mt:
            break
        toks.append((mt.group(1), mt.end()))
        i = mt.end()
    k, sep, end = 0, False, m.end()
    while k < len(toks) and (toks[k][0] in (",", ";") or toks[k][0] == "in"):
        sep, k = True, k + 1
    city_words, j = [], k
    while j < len(toks) and len(city_words) < 3:
        w = toks[j][0]
        if not w[0].isalpha() or w.lower() in CITY_STOP or _state_at(toks, j):
            break
        if not (w[0].isupper() or focus):
            break
        city_words.append(w)
        j += 1
    city = state = zip_ = None
    jj = j + 1 if j < len(toks) and toks[j][0] == "," else j
    s = _state_at(toks, jj)
    if city_words and (sep or s):
        city = " ".join(cap(w) for w in city_words)
        end = toks[j - 1][1]
        if s:
            state, end, jj = s[0], toks[jj + s[1] - 1][1], jj + s[1]
    elif not city_words:
        s = _state_at(toks, k)
        if s and sep:
            state, end, jj = s[0], toks[k + s[1] - 1][1], k + s[1]
    if state or city:
        jz = jj + 1 if jj < len(toks) and toks[jj][0] == "," else jj
        if jz < len(toks) and re.fullmatch(r"\d{5}", toks[jz][0]):
            zip_, end = toks[jz][0], toks[jz][1]
    if city and not state:
        state = home_state
    return {"address": street, "city": city, "state": state, "zip": zip_, "span": (m.start(), end)}


def addr_text(d):
    parts = [d.get("address"), d.get("city"), " ".join(x for x in (d.get("state"), d.get("zip")) if x)]
    return ", ".join(p for p in parts if p)


EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
SPOKEN_EMAIL = _rx(r"\b([\w.+-]+(?:\s+(?:dot|underscore|dash)\s+[\w+-]+)*)\s+at\s+([\w-]+(?:\s+dot\s+[\w-]+)+)\b")


def _spoken(s):
    s = re.sub(r"\s+dot\s+", ".", s, flags=re.I)
    s = re.sub(r"\s+underscore\s+", "_", s, flags=re.I)
    return re.sub(r"\s+(?:dash|hyphen)\s+", "-", s, flags=re.I)


def find_email(t, focus):
    m = EMAIL_RE.search(t)
    if m:
        return m.group(0).lower(), m.span()
    m = SPOKEN_EMAIL.search(t)
    if m:
        cand = f"{_spoken(m.group(1))}@{_spoken(m.group(2))}".lower()
        if EMAIL_RE.fullmatch(cand):
            return cand, m.span()
    if focus and re.search(r"\sat\s", t, re.I):
        s = re.sub(r"^(?:the )?e-?mail(?: address)?(?: is)?\s+", "", lead_in(t.strip()), flags=re.I)
        local, domain = re.split(r"\s+at\s+", _spoken(s), maxsplit=1, flags=re.I)
        cand = (local.replace(" ", "") + "@" + (domain.split() or [""])[0]).lower().strip(".,")
        if EMAIL_RE.fullmatch(cand):
            return cand, (0, len(t))
    return None, None


def cut(t, span):
    return t[:span[0]] + " " + t[span[1]:]


def contact(conn, t, focus):
    """Phone, email and address in any order; returns (data, slots, text with those removed)."""
    data, got = {}, set()
    ph, span = H.phone(t)
    if ph:
        kind = re.search(r"\b(cell|mobile|work|office|home)\b", t, re.I)
        data.update(phone1=ph, phone1Type={"cell": "Mobile", "mobile": "Mobile", "work": "Work", "office": "Work",
                                           "home": "Home"}[kind.group(1).lower()] if kind else "Mobile")
        got.add("phone")
        t = cut(t, span)
    em, span = find_email(t, focus == "email")
    if em:
        data["email1"] = em
        got.add("email")
        t = cut(t, span)
    a = parse_address(t, focus == "address", home_state(conn))
    if a:
        data.update({k: v for k, v in a.items() if k != "span" and v})
        got.add("address")
        t = cut(t, a["span"])
    return data, got, t


def home_state(conn):
    return db.get_account(conn).get("state") or None


def number_answer(t):
    t2 = H.words_to_digits(t).replace(",", "")
    a = H.amounts(t2)
    if a:
        return a[0][0]
    m = re.search(r"(\d+(?:\.\d+)?)", t2)
    return float(m.group(1)) if m else None


def past_date(t, now):
    tl = t.lower()
    if re.search(r"\byesterday\b", tl):
        return now - timedelta(days=1)
    m = re.search(r"\b(?:last|on|this past)\s+(" + "|".join(H.WEEKDAYS) + r")\b", tl)
    if m:
        return now - timedelta(days=(now.weekday() - H.WEEKDAYS.index(m.group(1))) % 7 or 7)
    m = re.search(r"\b(\d+) days ago\b", H.words_to_digits(tl))
    return now - timedelta(days=int(m.group(1))) if m else None


# ======================================================================= frames

R, REC, T = "required", "recommended", "thorough"
LEVELS = {"quick": (R,), "balanced": (R, REC), "thorough": (R, REC, T)}
OFFER_A = {"address": "an address", "phone": "a phone number", "email": "an email address"}
OFFER_THE = {"address": "the address", "phone": "the phone number", "email": "the email address"}
SHORT = {"address": "Address", "phone": "Phone", "email": "Email"}
SLOT_PAT = {"address": r"address|street|lives", "phone": r"phone|number|cell|mobile", "email": r"e-?mail"}
SLOT_WORDS = {k: _rx(v) for k, v in SLOT_PAT.items()}
SLOT_NEG = {k: _rx(rf"\b(?:no|skip|without|not the|don'?t (?:need|want|have) (?:the|an?))\s+(?:the\s+|an?\s+)?(?:{v})")
            for k, v in SLOT_PAT.items()}
LOG_INTENTS = {"log_prospect", "log_closing", "log_income", "log_expense", "log_trip", "log_activity"}
LEARNABLE = {"address": "addresses", "phone": "phone numbers", "email": "email addresses", "vendor": "the store name",
             "withWhom": "who a meal was with", "payer": "who paid", "destination": "trip destinations",
             "purpose": "the business purpose", "strength": "lead strength", "loan": "loan details"}
INTENT = {"prospects": "log_prospect", "update": "update_prospect", "expenses": "log_expense",
          "activities": "log_activity", "income": "log_income", "trips": "log_trip", "closings": "log_closing"}
PEOPLE_ACTS = ("relationship_building", "partner_coaching", "past_client", "current_client", "prospective_client",
               "personal_visit", "socializing")


def _s(key, level, kind="value", group=None, when=None):
    return {"key": key, "level": level, "kind": kind, "group": group, "when": when}


FRAMES = {
    "prospects": [
        _s("name", R),
        _s("lastName", R, when=lambda st: st["data"].get("firstNames") and not st["data"].get("lastName")),
        _s("dup", R, "choice", when=lambda st: st["meta"].get("dupId")),
        _s("address", REC, group="contact"), _s("phone", REC, group="contact"), _s("email", T, group="contact"),
        _s("source", R),  # D3: always asked; "I don't know" records Unknown and flags it for review
        _s("relation", REC, "choice", when=lambda st: st["meta"].get("sourceNew") and "source" in st["known"]),
        _s("followUp", REC, "default"),
        _s("strength", T, "choice"),
        _s("loan", T),
    ],
    "update": [_s("followUp", REC, "default", when=lambda st: st["meta"].get("touched"))],
    "expenses": [_s("amount", R), _s("category", R, "choice"),
                 _s("withWhom", REC, when=lambda st: st["meta"].get("mealish")),
                 _s("vendor", REC),
                 _s("purpose", T, when=lambda st: st["meta"].get("meal") and st["data"].get("withWhom"))],
    "activities": [_s("activity", R, "choice"), _s("minutes", R),
                   _s("withWhom", REC, when=lambda st: any(k in (st["data"].get("activityId") or "")
                                                           for k in PEOPLE_ACTS))],
    "income": [_s("amount", R), _s("type", R, "choice"), _s("payer", REC)],
    "trips": [_s("miles", R), _s("destination", REC), _s("reason", R, "choice")],
    "closings": [_s("client", R), _s("pick", R, "choice", when=lambda st: st["meta"].get("candidates")),
                 _s("size", R), _s("income", R, "default")],
}


def new_state(log, frame=None, data=None, known=(), meta=None):
    return {"v": 1, "log": log, "frame": frame or log, "id": None, "data": dict(data or {}), "meta": dict(meta or {}),
            "known": list(known), "skipped": [], "queue": [], "offered": [], "pending": None, "turns": 0,
            "tries": 0, "chain": None, "queued": None}


def load_state(st):
    if not isinstance(st, dict) or st.get("frame") not in FRAMES:
        return None
    base = new_state(st.get("log") or "prospects")
    base.update(st)
    return base


def prefs(conn):
    a = db.get_account(conn)
    return a.get("herbQuestions") or "balanced", set(a.get("herbNeverAsk") or [])


def learn(conn, keys, filled=False):
    """Adaptive questions: after three skips in a row HERB stops offering that field (Balanced mode)."""
    keys = [k for k in keys if k in LEARNABLE]
    if not keys:
        return None
    a = db.get_account(conn)
    skips, never, msg = dict(a.get("herbSkips") or {}), list(a.get("herbNeverAsk") or []), None
    for k in keys:
        if filled:
            skips[k] = 0
            continue
        skips[k] = skips.get(k, 0) + 1
        if skips[k] >= 3 and k not in never and (a.get("herbQuestions") or "balanced") != "thorough":
            never.append(k)
            msg = f"I notice you usually skip {LEARNABLE[k]}, so I'll stop asking. You can turn it back on in HERB Autopilot."
    if skips != (a.get("herbSkips") or {}) or never != list(a.get("herbNeverAsk") or []):
        a["herbSkips"], a["herbNeverAsk"] = skips, never
        db.set_account(conn, a)
        conn.commit()
    return msg


def who(st, full=False):
    d, m = st["data"], st["meta"]
    if st["frame"] in ("update", "closings"):
        n = m.get("name") or " ".join(x for x in (d.get("firstNames"), d.get("lastName")) if x)
        return (n.split()[0] if n and not full and st["frame"] == "update" else n) or "the client"
    f, l = d.get("firstNames"), d.get("lastName")
    if full:
        return " ".join(x for x in (f, l) if x) or "the prospect"
    return f or l or "the prospect"


# ======================================================================= extraction

SOURCE_CUE = _rx(r"referr|\bsent (?:him|her|them|me|over|by)\b|\bfrom\b|\bsource\b|came from|comes from|"
                 r"\bmet (?:him|her|them|at)\b|\bthrough\b|\bvia\b|open house|zillow|lead ?boost|website|online|"
                 r"facebook|instagram|door ?knock|cold call|seminar|past client|realtor|"
                 r"my (?:brother|sister|mom|dad|friend|neighbor|cousin)")
FOLLOW_CUE = _rx(r"follow[- ]?up|\bfollow\b|call (?:him|her|them|back)|check (?:back|in)|touch base|reach out|"
                 r"remind me|wants to (?:talk|meet|chat)|talk (?:on|again)|call on|meet on|make it|change it to|"
                 r"move it to|push it to|instead")
STRENGTH_CUE = _rx(r"red hot|\bhot\b|\bwarm\b|\bcold\b|no go|not interested|\bmedium\b")
EXTRA_CATEGORY = [
    (r"facebook|instagram|social media|tiktok|linkedin", ("internet", "cat.website_free", "act.website_ad_set_up_free")),
    (r"google|online|internet|web lead", ("internet", "cat.website_paid", "act.website_ad_set_up_paid")),
    (r"walk[- ]?in|came into the office|office visit", ("prospecting", "cat.office_visits", "act.office_visits")),
]
RELATION = [
    (r"family|brother|sister|\bmom\b|\bdad\b|cousin|uncle|aunt|in-law|\bson\b|daughter|wife|husband|relative",
     ("personal", "cat.family", "act.relationship_building_personal")),
    (r"friend|neighbor|buddy", ("personal", "cat.friend", "act.relationship_building_personal")),
    (r"\bagent\b|real estate|broker", ("professional", "cat.realtor", "act.relationship_building_professional")),
    (r"lender|loan officer|banker|\bbank\b", ("professional", "cat.banker", "act.relationship_building_professional")),
    (r"professional|business|colleague|co-?worker|vendor|partner",
     ("professional", "cat.consultant", "act.relationship_building_professional")),
    (r"client|customer", ("clients", "cat.past_client", "act.past_client_interaction")),
    (r"other|else|stranger|nobody|just met|don'?t know",
     ("clients", "cat.prospective_client", "act.prospective_client_interaction")),
]
TAG_FROM_ACTIVITY = ("act.open_houses", "act.seminar", "act.networking_open_group", "act.door_knocking")


def keyword_tags(t):
    kw = H.infer_from_keywords(t)
    if kw:
        return kw
    for pat, tags in EXTRA_CATEGORY:
        if re.search(pat, t, re.I):
            return tags
    return None


def relation_from(t):
    kw = H.infer_from_keywords(t)
    if kw:
        return kw
    for pat, tags in RELATION:
        if re.search(pat, t, re.I):
            return tags
    return None


def tag_update(tags):
    sub, cat, act = tags
    return {"pillar": tx.SUB_PILLAR_PILLAR[sub], "subPillar": sub, "categoryId": cat, "activityId": act}


def source_from(conn, t, cur, focus, first):
    if not (focus == "source" or first or SOURCE_CUE.search(t)):
        return {}, set()
    if focus == "source" and (NO.match(t) or DONE.match(t) or UNKNOWN.search(t)):
        return {}, set()  # the caller records it as Unknown
    exclude = H.tokens(f"{cur.get('firstNames') or ''} {cur.get('lastName') or ''}")
    src = H.match_source(conn, t, exclude)
    if src and src["name"] == UNKNOWN_SOURCE:  # "unknown caller" is not the Unknown source
        src = None
    tags = H.source_profile(conn, src["id"]) if src else None
    kw = keyword_tags(t)
    if kw and (not tags or kw[1] in ("cat.open_house", "cat.website_paid", "cat.door_knocking", "cat.seminar")
               and not src):
        tags = kw
    name = src["name"] if src else None
    if tags and not name:
        if tags[2] in TAG_FROM_ACTIVITY:
            name = H.latest_source_for_activity(conn, tags[2])
        elif re.search(r"zillow", t, re.I):
            name = "Zillow"
        elif re.search(r"lead ?boost", t, re.I):
            name = "LeadBoost"
    if not src:
        m = (re.search(rf"(?:referred by|referral from|sent (?:over )?by|came from|from|through|via)\s+({PERSON})", t)
             or re.search(rf"\b({PERSON})\s+(?:sent|referred)\b", t))
        new = clean_person(m.group(1)) if m else None
        if new and set(H.tokens(new)) & set(exclude):
            new = None
        if not new and focus == "source" and not tags:
            new = bare_name(t)
        if new:
            name = new
    if not name and not tags:
        return {}, set()
    upd, got = ({"source": name} if name or not cur.get("source") else {}), {"source"}
    upd["_sourceUnknown"] = False
    if tags:
        upd.update(tag_update(tags))
        upd["_sourceNew"] = False
        got.add("relation")
    else:
        upd["_sourceNew"] = True
    return upd, got


def follow_from(t, now, loose):
    if re.search(r"\bno follow[- ]?up\b|don'?t (?:need to )?follow|no need to follow", t, re.I):
        return {"followUp": None, "_followTime": None}, {"followUp"}
    m = FOLLOW_CUE.search(t)
    if m:
        seg = t[m.start():]
    elif loose:
        seg = re.sub(r"\b(?:today|tonight|this (?:afternoon|evening|morning))\b", "", t, flags=re.I)
    else:
        return {}, set()
    seg = re.sub(r"\b(\w+day)['’]s\b", "", seg)
    d = H.parse_when(seg, now)
    if not d:
        return {}, set()
    upd = {"followUp": d.isoformat()}
    tm = H.parse_time(seg)
    if tm:
        upd["_followTime"] = tm
    return upd, {"followUp"}


def strength_from(t, focus, first):
    if focus == "strength" or STRENGTH_CUE.search(t) or (first and H.strength_from(t) != "medium"):
        s = "medium" if re.search(r"\bwarm\b|\bmedium\b|lukewarm", t, re.I) else H.strength_from(t)
        if focus == "strength" or s != "medium" or re.search(r"\bwarm\b|\bmedium\b", t, re.I):
            return {"strength": s}, {"strength"}
    return {}, set()


def loan_from(t, focus, first):
    if not (focus == "loan" or first or re.search(r"loan|purchase|refi|\$|thousand|\bk\b", t, re.I)):
        return {}, set()
    upd, approx = {}, None
    amts = H.amounts(t)
    if amts:
        v = max(a[0] for a in amts)
        approx = v * 1000 if 100 <= v < 5000 else v
        if approx >= 20000:
            upd["_loanAmount"] = approx
    if re.search(r"refi|refinanc", t, re.I):
        upd["_loanPurpose"] = "refinance"
    elif re.search(r"purchase|\bbuy", t, re.I) or upd.get("_loanAmount"):
        upd["_loanPurpose"] = "purchase"
    return (upd, {"loan"}) if upd else ({}, set())


def notes_from(t):
    upd = {}
    m = re.search(r"\b(?:add (?:a )?note|note)\b(?:\s+(?:to|for|on)\s+(?:him|her|them|it))?[:,]?\s+(?:that\s+)?(.+)$",
                  t, re.I)
    if m:
        upd["_addNote"] = m.group(1).strip().rstrip(".") + "."
    m = re.search(r"(move-?up buyer|first-?time (?:home )?buyer|investor|downsiz\w+|relocat\w+|va loan|fha)", t, re.I)
    if m:
        upd["_tag"] = m.group(1)
    return upd


def ex_prospect(conn, st, t, now, focus):
    known, first = set(st["known"]), st["turns"] == 0
    upd, got, rest = contact(conn, t, focus)
    if focus in ("name", "lastName") or "name" not in known or re.search(r"\b(?:first|last) name\b|\bspell", rest, re.I):
        n = name_from(rest, focus)
        if n:
            upd.update(n)
            got.add("name")
            if n.get("lastName") or (n.get("firstNames") and st["data"].get("lastName")):
                got.add("lastName")
    cur = {**st["data"], **upd}
    for part in (source_from(conn, rest, cur, focus, first), follow_from(rest, now, first or focus == "followUp"),
                 strength_from(rest, focus, first), loan_from(rest, focus, first)):
        upd.update(part[0])
        got |= part[1]
    if focus == "relation":
        tags = relation_from(rest)
        if tags:
            upd.update(tag_update(tags))
            upd["_sourceNew"] = False
            got.add("relation")
    if focus == "dup":
        if re.search(r"\bsame\b|\byes\b|that'?s (?:him|her|them)|existing|update|merge", rest, re.I):
            upd["_dupAnswer"] = "same"
            got.add("dup")
        elif re.search(r"\bnew\b|different|\bno\b|another|not the same", rest, re.I):
            upd["_dupAnswer"] = "new"
            got.add("dup")
    upd.update(notes_from(rest))
    return upd, got


TOUCH = _rx(r"\b(called|talked to|talked with|spoke (?:to|with)|texted|emailed|met with|"
            r"left (?:a )?(?:message|voicemail|vm)(?: for| with)?|heard (?:back )?from)\b")
TOUCH_VERB = [("call", "Called"), ("talk", "Talked"), ("spoke", "Talked"), ("text", "Texted"), ("email", "Emailed"),
              ("met", "Met"), ("left", "Left a message"), ("heard", "Heard back")]


def ex_update(conn, st, t, now, focus):
    upd, got, rest = contact(conn, t, focus)
    for part in (follow_from(rest, now, focus == "followUp" or bool(re.search(r"\b(?:move|change|push|reschedule)\b",
                                                                              rest, re.I))),
                 strength_from(rest, focus, False)):
        upd.update(part[0])
        got |= part[1]
    upd.update(notes_from(rest))
    return upd, got


EXPENSE_ANSWERS = [
    (r"\bfood\b|restaurant|\beat\b", "relationships", "exp.relationships.meal"),
    (r"\bcar\b|oil change|tires?", "travel", "exp.travel.car_expenses"),
    (r"(?:online|facebook|google|web|internet).*(?:ad|marketing)|(?:ad|marketing).*(?:online|facebook|google|web)",
     "ad_internet", "exp.ad_internet.website_ad"),
    (r"marketing|advertis|\bads?\b|promo", "ad_traditional", "exp.ad_traditional.promotion_set_up"),
    (r"education|seminar ticket|conference", "self_improvement", "exp.self_improvement.education"),
    (r"donat", "general", "exp.general.donation"),
    (r"photo", "general", "exp.general.photography"),
]
MEALISH_CATS = ("meal", "entertainment", "thank_you_gifts", "closing_gift")
VENDOR_CUE = _rx(r"\b(?:at|from)\s+[A-Z]|\bvendor\b|\bstore\b|\brestaurant\b|\bplace was\b")
WITH_CUE = _rx(r"\bwith\b|\bfor (?:my |a )?(?:client|realtor|partner)")


def classify_expense(conn, t, vendor):
    if H.MEAL.search(t):
        return "relationships", "exp.relationships.meal"
    for pat, g, c in H.EXPENSE_KEYWORDS:
        if re.search(pat, t, re.I):
            return g, c
    for pat, g, c in EXPENSE_ANSWERS:
        if re.search(pat, t, re.I):
            return g, c
    if vendor:
        r = conn.execute("SELECT group_id, category_id FROM expenses WHERE lower(vendor) = ? ORDER BY date DESC LIMIT 1",
                         (vendor.lower(),)).fetchone()
        if r:
            return r["group_id"], r["category_id"]
    return None


def ex_expense(conn, st, t, now, focus):
    known, first = set(st["known"]), st["turns"] == 0
    upd, got = {}, set()
    if focus == "amount" or "amount" not in known or re.search(r"\$|dollars?|bucks|make it|it was|total|amount", t, re.I):
        a = H.amounts(t)
        pick = [x for x in a if x[3]] or (a if focus == "amount" or "amount" not in known else [])
        v = pick[0][0] if pick else (number_answer(t) if focus == "amount" else None)
        if v:
            upd["amount"] = v
            got.add("amount")
    short = len(t.split()) <= 3 and focus not in ("vendor", "purpose")
    person = H.match_source(conn, t) if (first or focus == "withWhom" or WITH_CUE.search(t) or short) else None
    if person and person["kind"] == "person":
        upd.update(withWhom=person["name"], source=person["name"], _solo=False, _personId=person["id"])
        got.add("withWhom")
    elif focus == "withWhom":
        if SOLO.search(t):
            upd.update(withWhom=None, source=None, _solo=True)
            got.add("withWhom")
        else:
            n = bare_name(t)
            if n:
                upd.update(withWhom=n, source=n, _solo=False)
                got.add("withWhom")
    vendor = None
    if focus == "vendor" or "vendor" not in known or VENDOR_CUE.search(t):
        m = re.search(r"\b(?:at|from)\s+((?:[A-Z][\w'&\.]*|&)(?:\s+(?:[A-Z][\w'&\.]*|&|and|of))*)", t)
        w = upd.get("withWhom") or st["data"].get("withWhom") or ""
        if m and m.group(1).lower() not in w.lower():
            vendor = m.group(1).strip()
        if not vendor:
            tl = t.lower()
            for v in sorted((r["vendor"] for r in conn.execute(
                    "SELECT DISTINCT vendor FROM expenses WHERE vendor IS NOT NULL")), key=len, reverse=True):
                if v.lower() in tl:
                    vendor = v
                    break
        if not vendor and focus == "vendor":
            vendor = bare_name(re.sub(r"^(?:it was |we went )?(?:at|to)\s+", "", t, flags=re.I), 4)
        if vendor:
            upd["vendor"] = vendor
            got.add("vendor")
    if focus == "category" or "category" not in known or re.search(r"\b(?:category|it was for|it'?s for|actually)\b", t, re.I):
        c = classify_expense(conn, t, vendor or st["data"].get("vendor"))
        if c:
            upd.update(groupId=c[0], categoryId=c[1])
            got.add("category")
            mw = H.MEAL.search(t)
            upd["_meal"] = mw.group(0).lower() if mw else ("meal" if c[1].endswith(".meal") else None)
    m = re.search(r"(?:to discuss|discussed|talked about|talking about|went over|to talk about|about)\s+(.+)$", t, re.I)
    if focus == "purpose" and not (NO.match(t) or DONE.match(t)):
        upd["purpose"] = (m.group(1) if m else lead_in(t)).strip().rstrip(".")
        got.add("purpose")
    elif m and (upd.get("_meal") or st["meta"].get("meal")) and not re.match(r"[\d$]", m.group(1)):
        upd["purpose"] = m.group(1).strip().rstrip(".")
        got.add("purpose")
    pd = past_date(t, now)
    if pd:
        upd["date"] = pd.isoformat()
    return upd, got


EXTRA_ACTIVITY = [(r"meeting|met with|lunch|coffee|breakfast", "act.relationship_building_professional"),
                  (r"phone calls?|calling|calls\b", "act.cold_calling"), (r"social media", "act.facebook_marketing"),
                  (r"follow[- ]?ups?|prospect", "act.prospective_client_interaction"),
                  (r"network", "act.networking_open_group")]


def activity_from(t):
    a = H.infer_activity(t)
    if a:
        return a
    for pat, act in EXTRA_ACTIVITY:
        if re.search(pat, t, re.I):
            return act
    return None


def ex_activity(conn, st, t, now, focus):
    known, first = set(st["known"]), st["turns"] == 0
    upd, got = {}, set()
    src = H.match_source(conn, t) if (first or focus == "withWhom" or WITH_CUE.search(t)) else None
    if focus == "activity" or "activity" not in known:
        a = activity_from(t)
        if not a and src:
            prof = H.source_profile(conn, src["id"])
            a = prof[2] if prof else None
        if a:
            meta = tx.ACTIVITY_BY_ID[a]
            upd.update(activityId=a, pillar=meta["pillar"], subPillar=meta["subPillar"])
            got.add("activity")
    mins = H.duration_minutes(t)
    if not mins and focus == "minutes":
        n = number_answer(t)
        if n:
            mins = int(max(15, round((n * 60 if n <= 12 else n) / 15) * 15))
    if mins:
        upd["minutes"] = mins
        got.add("minutes")
    if src and src["kind"] == "person":
        upd["source"] = src["name"]
        got.add("withWhom")
    elif focus == "withWhom":
        n = bare_name(t)
        if n:
            upd["source"] = n
            got.add("withWhom")
    m = re.search(r"(\d+)\s+(?:new\s+)?(?:leads?|prospects?)", H.words_to_digits(t.lower()))
    if m:
        upd["_leads"] = int(m.group(1))
    pd = past_date(t, now)
    if pd:
        upd["date"] = pd.isoformat()
    return upd, got


def ex_income(conn, st, t, now, focus):
    known = set(st["known"])
    upd, got = {}, set()
    if focus == "amount" or "amount" not in known or re.search(r"\$|dollars?|bucks|make it", t, re.I):
        a = H.amounts(t)
        v = max(x[0] for x in a) if a else (number_answer(t) if focus == "amount" else None)
        if v:
            upd["amount"] = v
            got.add("amount")
    typ = next((v for pat, v in H.INCOME_TYPE_WORDS if re.search(pat, t, re.I)), None)
    if typ:
        upd["type"] = typ
        got.add("type")
    m = re.search(r"\bfrom\s+(.+?)(?:\s+for\b|[.,!?]|$)", t, re.I)
    payer = m.group(1).strip() if m else (bare_name(t, 4) if focus == "payer" else None)
    if payer:
        payer = re.sub(r"^the\s+", "", payer, flags=re.I)
        upd["payer"] = " ".join(w if w.isupper() else w[:1].upper() + w[1:] for w in payer.split())
        got.add("payer")
    pd = past_date(t, now)
    if pd:
        upd["date"] = pd.isoformat()
    return upd, got


TRIP_REASONS = [(r"closing", "Closing"), (r"title", "Title Company"), (r"open house", "Open Houses"),
                (r"door ?knock", "Door Knocking"), (r"seminar", "Seminar"), (r"network|chamber|mixer", "Networking-Open Group"),
                (r"realtor|agent|partner", "Relationship Building-Professional"),
                (r"past client", "Past Client Interaction"), (r"prospect|new client|lead", "Prospective Client Interaction"),
                (r"client|meeting|appointment", "Current Client Interaction"), (r"\boffice\b", "Office")]


def reason_from(t):
    for pat, name in TRIP_REASONS:
        if re.search(pat, t, re.I):
            return name
    a = H.infer_activity(t)
    return tx.ACTIVITY_BY_ID[a]["name"] if a and tx.ACTIVITY_BY_ID[a]["name"] in tx.MILEAGE_REASONS else None


def ex_trip(conn, st, t, now, focus):
    known, first = set(st["known"]), st["turns"] == 0
    upd, got = {}, set()
    m = re.search(r"(\d+(?:\.\d+)?)\s*(?:miles?|mi)\b", H.words_to_digits(t.lower()))
    v = float(m.group(1)) if m else (number_answer(t) if focus == "miles" else None)
    if v:
        upd["gpsMiles"] = v
        got.add("miles")
    dest = None
    if first or focus == "destination" or re.search(r"\b(?:drove|went|destination|headed)\b", t, re.I):
        m = re.search(r"\b(?:to|at)\s+(?:the\s+)?(.+?)(?:\s+(?:and|for|about|it was|today|\d)|[.,!?]|$)", t)
        dest = m.group(1).strip() if m else None
        if not dest and focus == "destination" and not NO.match(t):
            dest = lead_in(re.sub(r"^(?:i )?(?:drove|went) (?:to )?", "", t, flags=re.I)).strip()
        if dest:
            upd["destination"] = " ".join(w.capitalize() if w.islower() and w not in ("of", "and", "the", "at")
                                          else w for w in dest.split())
            got.add("destination")
    reason = reason_from(t) or (reason_from(dest) if dest else None)
    if reason and (focus == "reason" or "reason" not in known):
        act = next((a["id"] for a in tx.ACTIVITIES if a["name"] == reason), None)
        upd.update(reason=reason, activityId=act)
        got.add("reason")
    pd = past_date(t, now)
    if pd:
        upd["date"] = pd.isoformat()
    return upd, got


def prospect_candidates(conn, t, first_name_ok=False):
    toks = set(H.tokens(t))
    out = []
    for p in db.rows(conn.execute("SELECT p.*, c.id AS closing_id FROM prospects p LEFT JOIN closings c "
                                  "ON c.prospect_id = p.id ORDER BY p.date DESC")):
        last = (p["last_name"] or "").lower()
        score = (2 if last and last in toks else 0) + sum(1 for f in H.tokens(p["first_names"]) if f in toks and f != "and")
        if score >= 2 or (first_name_ok and score >= 1):
            out.append((score - (0.5 if p["closing_id"] else 0), p))
    out.sort(key=lambda sp: -sp[0])
    return out


def closing_yield(conn):
    led = calc.ledger(conn, "ytd")
    return ratio(led.closing_income, led.volume) or 0.0135


def ex_closing(conn, st, t, now, focus):
    known = set(st["known"])
    upd, got = {}, set()
    if focus in ("client", "pick") or "client" not in known:
        cands = prospect_candidates(conn, t, first_name_ok=focus in ("client", "pick"))
        if focus == "pick" and st["meta"].get("candidates"):
            ids = [c["id"] for c in st["meta"]["candidates"]]
            m = re.search(r"\b(first|second|third|1st|2nd|3rd|one|two|three)\b", t, re.I)
            if m:
                i = {"first": 0, "1st": 0, "one": 0, "second": 1, "2nd": 1, "two": 1, "third": 2, "3rd": 2,
                     "three": 2}[m.group(1).lower()]
                cands = [(9, {"id": ids[i]})] if i < len(ids) else []
            else:
                cands = [c for c in cands if c[1]["id"] in ids]
        top = [c for c in cands if c[0] == cands[0][0]] if cands else []
        if len(top) > 1 and focus != "pick" and len({c[1]["id"] for c in top}) > 1:
            upd["_candidates"] = [{"id": c[1]["id"], "name": f"{c[1]['first_names']} {c[1]['last_name']}",
                                   "date": c[1]["date"]} for c in top[:3]]
            got.add("client")
        elif top:
            p = db.one(conn.execute("SELECT p.*, c.id AS closing_id FROM prospects p LEFT JOIN closings c "
                                    "ON c.prospect_id = p.id WHERE p.id = ?", (top[0][1]["id"],)))
            upd.update(prospectId=p["id"], _name=f"{p['first_names']} {p['last_name']}", _candidates=None,
                       _repeat=bool(p["closing_id"]))
            got |= {"client", "pick"}
        elif focus == "client" or "client" not in known:
            n = H.find_person_name(t) or (bare_name(t) if focus == "client" else None)
            if n and len(n.split()) >= 2:
                first, last = H.split_name(n)
                upd.update(firstNames=first, lastName=last, _name=n)
                got.add("client")
    income = size = None
    m = re.search(r"(?:made|earned|comp(?:ensation)? (?:of|was)?|commission (?:of|was)?|income (?:of|was)?|"
                  r"i get|paid me)\s*\$?\s*([\d,\.]+\s*(?:k|thousand|grand)?)", t, re.I)
    if m:
        v = H.amounts(m.group(1) + (" dollars" if not re.search(r"k|thousand|grand", m.group(1)) else ""))
        income = v[0][0] if v else None
    for v, s, e, explicit in sorted(H.amounts(t), key=lambda a: -a[0]):
        if income is not None and abs(v - income) < 0.5:
            continue
        val = v * 1000 if (100 <= v < 5000 and not explicit) else v
        if val >= 50000 and size is None:
            size = val
    if focus == "size" and not size:
        n = number_answer(t)
        size = (n * 1000 if n and n < 5000 else n) or None
    if focus == "income" and not income and not size:
        n = number_answer(t)
        income = (n * 1000 if n and n < 100 else n) or None
    if size:
        upd["transactionSize"] = size
        got.add("size")
    if income:
        upd["income"] = income
        got.add("income")
    return upd, got


EXTRACTORS = {"prospects": ex_prospect, "update": ex_update, "expenses": ex_expense, "activities": ex_activity,
              "income": ex_income, "trips": ex_trip, "closings": ex_closing}


def extract(conn, st, t, now, focus=None):
    return EXTRACTORS[st["frame"]](conn, st, t, now, focus)


def apply(conn, st, upd, got, now):
    for k, v in upd.items():
        if k == "_addNote":
            st["meta"].setdefault("notes", []).append(v)
        elif k == "_tag":
            tags = st["meta"].setdefault("tags", [])
            if v.lower() not in (x.lower() for x in tags):
                tags.append(v)
        elif k.startswith("_"):
            st["meta"][k[1:]] = v
        else:
            st["data"][k] = v
    for g in got:
        if g not in st["known"]:
            st["known"].append(g)
        for lst in ("skipped", "queue"):
            if g in st[lst]:
                st[lst].remove(g)
    learn(conn, got, filled=True)
    settle(conn, st, now)


def settle(conn, st, now):
    """Derived state after each change: duplicates, meal categories, closing estimates."""
    d, m = st["data"], st["meta"]
    if st["frame"] == "prospects":
        if d.get("lastName") and not m.get("dupChecked"):
            m["dupChecked"] = True
            r = conn.execute("SELECT id, date FROM prospects WHERE lower(first_names) = ? AND lower(last_name) = ? "
                             "ORDER BY date DESC LIMIT 1",
                             ((d.get("firstNames") or "").lower(), d["lastName"].lower())).fetchone()
            if r:
                m.update(dupId=r["id"], dupDate=r["date"])
        if m.get("dupAnswer") == "new":
            m["dupId"] = None
        elif m.get("dupAnswer") == "same" and m.get("dupId"):
            to_update(conn, st)
    if st["frame"] == "expenses" and d.get("categoryId"):
        cat = d["categoryId"]
        m["mealish"] = any(cat.endswith(x) for x in MEALISH_CATS)
        if cat.endswith(".meal"):
            g, c = "relationships", "exp.relationships.meal"
            if m.get("solo"):
                g, c = "travel", "exp.travel.meal"
            elif m.get("personId"):
                prof = H.source_profile(conn, m["personId"])
                if prof and prof[0] == "clients":
                    g, c = "clients", "exp.clients.meal"
            d.update(groupId=g, categoryId=c)
    if st["frame"] == "closings" and d.get("transactionSize"):
        m["estimate"] = round(d["transactionSize"] * closing_yield(conn))


def to_update(conn, st):
    """'Same person' on a duplicate: fold the new details into the existing prospect instead."""
    p = db.one(conn.execute("SELECT * FROM prospects WHERE id = ?", (st["meta"]["dupId"],)))
    d = st["data"]
    patch = {k: d[k] for k in ("phone1", "phone1Type", "email1", "address", "city", "state", "zip", "followUp",
                               "strength") if d.get(k)}
    meta = {"name": f"{p['first_names']} {p['last_name']}", "existingNotes": p["notes"],
            "notes": st["meta"].get("notes", []), "followTime": st["meta"].get("followTime"),
            "strengthWas": p["strength"]}
    if st["meta"].get("loanAmount"):
        meta["notes"].append(f"About {money(st['meta']['loanAmount'])} {st['meta'].get('loanPurpose') or 'purchase'}.")
    st.update(frame="update", id=p["id"], data=patch, meta=meta, queue=[], offered=[],
              known=[k for k in ("phone", "email", "address", "followUp", "strength") if k in st["known"]])


# ======================================================================= defaults and final records

FOLLOW_DAYS = {"red_hot": 1, "hot": 1, "medium": 3, "cold": 14, "no_go": None}


def default_follow(st, now):
    days = FOLLOW_DAYS.get(st["data"].get("strength") or st["meta"].get("strengthWas") or "medium", 3)
    if days is None:
        return None
    d = now + timedelta(days=days)
    while d.weekday() >= 5:  # business days only
        d += timedelta(days=1)
    return d.isoformat()


def default_value(conn, st, key, now):
    if key == "followUp":
        return default_follow(st, now)
    if key == "income":
        return st["meta"].get("estimate")
    return None


def compose_notes(st, now):
    m, d = st["meta"], st["data"]
    out = []
    if m.get("loanAmount"):
        out.append(f"About {money(m['loanAmount'])} {m.get('loanPurpose') or 'purchase'}.")
    elif m.get("loanPurpose"):
        out.append(f"{m['loanPurpose'].capitalize()}.")
    out += [t[:1].upper() + t[1:] + "." for t in m.get("tags", [])]
    if m.get("followTime") and d.get("followUp"):
        out.append(f"Wants to talk {H.fmt_day(date.fromisoformat(d['followUp']), now)} after {m['followTime']}.")
    out += m.get("notes", [])
    return " ".join(out) or None


def final_data(conn, st, now):
    d, m = dict(st["data"]), st["meta"]
    frame = st["frame"]
    d.setdefault("date", now.isoformat())
    if frame == "prospects":
        if not d.get("categoryId"):
            d.update(tag_update(("clients", "cat.prospective_client", "act.prospective_client_interaction")))
        d.setdefault("strength", "medium")
        d.setdefault("planOfAction", "Call")
        if "followUp" not in st["known"] and not d.get("followUp"):
            d["followUp"] = default_follow(st, now)
        d["notes"] = compose_notes(st, now)
        if m.get("sourceUnknown") and not d.get("source"):  # D3: visible in reports, waiting in the Review queue
            d.update(source=UNKNOWN_SOURCE, reviewed=False)
            if "HERB: still need" not in (d["notes"] or ""):
                d["notes"] = " ".join(x for x in (d["notes"], "HERB: still need the source.") if x)
        d["capture"] = "voice"
    elif frame == "update":
        d.pop("date", None)
        if m.get("touched") and "followUp" not in st["known"]:
            d["followUp"] = default_follow(st, now)
        new = compose_notes(st, now)
        if new:
            d["notes"] = (m.get("existingNotes") + " | " if m.get("existingNotes") else "") + new
    elif frame == "expenses":
        if not d.get("categoryId"):
            d.update(groupId="general", categoryId="exp.general.office_supplies", reviewed=False)
        meal = m.get("meal")
        d.setdefault("vendor", None)
        d["vendor"] = d["vendor"] or (meal.capitalize() if meal else "Unknown vendor")
        if meal and d.get("withWhom") and not d.get("purpose"):
            d["purpose"] = f"{meal.capitalize()} with {d['withWhom']} — business discussion"
        d["relationshipSubPillar"] = "professional" if d.get("groupId") == "relationships" else None
        d.update(hasReceipt=False, capture="voice")
    elif frame == "activities":
        if m.get("leads"):
            d["notes"] = f"Said: {m['leads']} leads."
        d["capture"] = "voice"
    elif frame == "income":
        d.setdefault("type", "commission")
        d.update(mode="type", expect1099=True, capture="voice")
    elif frame == "trips":
        d.setdefault("destination", "Unknown")
        d.setdefault("reason", "Office Visits")
        d["isBusiness"] = True
        d.setdefault("capture", "voice")
    elif frame == "closings":
        if "income" not in st["known"]:
            d["income"] = m.get("estimate")
        if m.get("repeat"):
            p = db.one(conn.execute("SELECT * FROM prospects WHERE id = ?", (d["prospectId"],)))
            return {"date": d["date"], "mode": "transaction", "lastName": p["last_name"], "transactionSize":
                    d.get("transactionSize"), "amount": d.get("income"), "pillar": p["pillar"],
                    "subPillar": p["sub_pillar"], "categoryId": p["category_id"], "activityId": p["activity_id"],
                    "sourceId": p["source_id"], "type": "commission", "notes": "Repeat transaction (rule R4)",
                    "capture": "voice"}
        d.update(addToIncome=True, referralRequest="ask_14", capture="voice")
        if not d.get("prospectId"):
            d.update(tag_update(("clients", "cat.prospective_client", "act.prospective_client_interaction")))
    return d


def save_log(st):
    if st["frame"] == "closings" and st["meta"].get("repeat"):
        return "income"
    return st["log"]


def summary(conn, st, now, pending):
    d, m = final_data(conn, st, now), st["meta"]
    asking = set([pending.get("slot")] if pending.get("slot") else []) | set(pending.get("slots") or [])
    rows = []

    def row(slot, label, value):
        r = {"label": label, "value": value if value not in (None, "") else "—"}
        if slot in asking:
            r["ask"] = True
        rows.append(r)

    frame = st["frame"]
    if frame in ("prospects", "update"):
        if frame == "update":
            row(None, "Updating", m.get("name"))
        else:
            row("name", "Name", who(st, full=True) if st["data"].get("lastName") or st["data"].get("firstNames") else "?")
        if frame == "prospects" or d.get("phone1"):
            row("phone", d.get("phone1Type") or "Mobile", d.get("phone1"))
        if frame == "prospects" or d.get("address"):
            row("address", "Address", addr_text(d))
        if d.get("email1") or "email" in asking:
            row("email", "Email", d.get("email1"))
        if frame == "prospects":
            names = H.tag_names(d.get("subPillar"), d.get("categoryId"), d.get("activityId"))
            row("source", "Source", "Unknown — to review" if m.get("sourceUnknown") else d.get("source"))
            row("relation", "Pillar · Category", f"{names[0]} · {names[1]}" if "relation" in st["known"] or
                "source" in st["known"] else f"{names[0]} · {names[1]} (default)")
        if frame == "prospects" or d.get("strength"):
            row("strength", "Strength", tx.STRENGTH_NAME.get(d.get("strength") or "medium"))
        if frame == "prospects" or "followUp" in d:
            row("followUp", "Follow-up", day_text(d.get("followUp"), now, m.get("followTime")) if d.get("followUp")
                else "—" if frame == "update" else "None")
        if m.get("loanAmount") or m.get("loanPurpose"):
            row("loan", "Loan", f"{(m.get('loanPurpose') or 'purchase').capitalize()}"
                + (f" · ~{money(m['loanAmount'])}" if m.get("loanAmount") else ""))
        if frame == "update" and d.get("notes"):
            row(None, "Note added", compose_notes(st, now))
        if m.get("dupId") and "dup" not in st["known"]:
            row("dup", "Possible duplicate", f"Existing prospect from {m.get('dupDate')}")
    elif frame == "expenses":
        meta = tx.EXPENSE_CATEGORY_BY_ID.get(d["categoryId"], {})
        row("amount", "Amount", money(d["amount"], cents=True) if d.get("amount") else None)
        row("category", "Category", f"{tx.EXPENSE_GROUP_NAME[d['groupId']]} · {meta.get('name')}"
            if "category" in st["known"] else None)
        row("vendor", "Vendor", st["data"].get("vendor"))
        if m.get("mealish"):
            row("withWhom", "With", "Just me" if m.get("solo") else d.get("withWhom"))
        if d.get("purpose") and m.get("meal"):
            row("purpose", "Purpose", d["purpose"])
        if "category" in st["known"]:
            row(None, "IRS category", meta.get("irs"))
    elif frame == "activities":
        a = tx.ACTIVITY_BY_ID.get(d.get("activityId") or "", {})
        mins = d.get("minutes")
        row("activity", "Activity", a.get("name"))
        row(None, "Pillar", tx.pillar_name(a.get("pillar")) if a else None)
        row("minutes", "Time", (f"{mins // 60} h {mins % 60:02d} min" if mins >= 60 else f"{mins} min") if mins else None)
        if d.get("source") or "withWhom" in asking:
            row("withWhom", "With", d.get("source"))
    elif frame == "income":
        row("amount", "Amount", money(d["amount"]) if d.get("amount") else None)
        row("type", "Type", tx.INCOME_TYPE_NAME.get(d["type"]) if "type" in st["known"] else None)
        row("payer", "Payer", d.get("payer"))
    elif frame == "trips":
        rate = tx.mileage_rate(d["date"])
        mi = d.get("gpsMiles")
        row("destination", "Destination", st["data"].get("destination"))
        row("miles", "Miles", f"{mi:.1f}" if mi else None)
        row("reason", "Reason", st["data"].get("reason"))
        if mi:
            row(None, "Deduction", f"{money(mi * rate, cents=True)} at {rate * 100:.1f}¢/mi")
    elif frame == "closings":
        row("client", "Client", m.get("name"))
        if m.get("candidates"):
            row("pick", "Which one?", " or ".join(c["name"] for c in m["candidates"]))
        row("size", "Transaction size", money(d.get("transactionSize")) if d.get("transactionSize") else None)
        inc = st["data"].get("income") or m.get("estimate")
        row("income", "Income", (money(inc) + ("" if "income" in st["known"] else " (estimate)")) if inc else None)
        if m.get("repeat"):
            row(None, "Logged as", "Income (repeat client, rule R4)")
        else:
            row(None, "Add to income log", "Yes")
            row(None, "Referral / review request", "Ask in 14 days")
    return rows


def readback(conn, st, now):
    d, m, frame = final_data(conn, st, now), st["meta"], st["frame"]
    if frame == "prospects":
        parts = [who(st, full=True)]
        if d.get("phone1"):
            parts.append(f"{(d.get('phone1Type') or 'mobile').lower()} {d['phone1']}")
        if d.get("address"):
            parts.append(addr_text(d))
        if d.get("email1"):
            parts.append(d["email1"])
        if d.get("source"):
            parts.append("source unknown" if m.get("sourceUnknown") else f"from {d['source']}")
        elif "relation" in st["known"]:
            parts.append(H.tag_names(d["subPillar"], d["categoryId"], d["activityId"])[1])
        if m.get("loanAmount"):
            parts.append(f"{m.get('loanPurpose') or 'purchase'} around {money(m['loanAmount'])}")
        parts.append(f"follow-up {day_text(d.get('followUp'), now, m.get('followTime'))}" if d.get("followUp")
                     else "no follow-up")
        lead = f"Lead {st['chain']['i']} of {st['chain']['total']}: " if (st.get("chain") or {}).get("total") else ""
        return lead + ", ".join(parts) + ". Save it?"
    if frame == "update":
        ch = []
        if d.get("phone1"):
            ch.append(f"phone {d['phone1']}")
        if d.get("email1"):
            ch.append(f"email {d['email1']}")
        if d.get("address"):
            ch.append(f"address {addr_text(d)}")
        if d.get("strength"):
            ch.append(f"strength {tx.STRENGTH_NAME[d['strength']].lower()}")
        if "followUp" in d:
            ch.append(f"follow-up {day_text(d['followUp'], now, m.get('followTime'))}" if d["followUp"]
                      else "no follow-up")
        note = compose_notes(st, now)
        if note:
            ch.append(f"note: {note}")
        return f"Update {m.get('name')}: " + ("; ".join(ch) or "no changes").rstrip(".") + ". Save it?"
    if frame == "expenses":
        meta = tx.EXPENSE_CATEGORY_BY_ID[d["categoryId"]]
        amt = d.get("amount") or 0
        s = money(amt, cents=amt % 1 != 0)
        if st["data"].get("vendor"):
            s += f" at {d['vendor']}"
        if d.get("withWhom"):
            s += f" with {d['withWhom']}"
        s += f", as {meta['name']}."
        if m.get("solo") and m.get("meal"):
            s += " Heads up: meals on your own usually aren't deductible unless you're traveling overnight."
        if amt >= 75:
            s += " It's over 75 dollars, so snap the receipt when you can."
        if d["categoryId"] == "exp.travel.car_expenses":
            s += " Note: if you use the standard mileage rate, gas usually isn't deductible separately."
        return s + " Save it?"
    if frame == "activities":
        a = tx.ACTIVITY_BY_ID[d["activityId"]]
        s = f"{H.fmt_minutes(d['minutes'])} of {a['name']}" + (f" with {d['source']}" if d.get("source") else "") + "."
        if m.get("leads"):
            s += f" You mentioned {m['leads']} leads — I'll help you add them after this."
        return s + " Save it?"
    if frame == "income":
        return (f"{money(d['amount'])} {tx.INCOME_TYPE_NAME[d['type']].lower()}"
                + (f" from {d['payer']}" if d.get("payer") else "") + ". Save it?")
    if frame == "trips":
        rate = tx.mileage_rate(d["date"])
        dest = st["data"].get("destination")
        why = "" if dest and d["reason"].lower() in dest.lower() else f" for {d['reason']}"
        return (f"{d['gpsMiles']:g} business miles" + (f" to {dest}" if dest else "") + why
                + f" — worth {money(d['gpsMiles'] * rate, cents=True)}. Save it?")
    if frame == "closings":
        if m.get("repeat"):
            return (f"{m.get('name')} already has a closing, so I'll log this one as income to keep your conversion "
                    f"rate honest: {money(d.get('amount'))}. Save it?")
        return (f"{m.get('name')} closed: {money(d.get('transactionSize'))}, and you earned {money(d.get('income'))}. "
                f"Save it and ask for a review in 14 days?")
    return "Save it?"


def echo(st, keys, now):
    """Short spoken confirmation of what was just captured (implicit confirmation)."""
    d, m = st["data"], st["meta"]
    order = [s["key"] for s in FRAMES[st["frame"]]] + ["phone", "email", "address", "followUp", "strength"]
    out = []
    for k in sorted(set(keys), key=lambda k: order.index(k) if k in order else 99):
        if k == "name" and st["frame"] == "prospects":
            out.append(who(st, full=True))
        elif k == "phone" and d.get("phone1"):
            out.append(f"{(d.get('phone1Type') or 'mobile').lower()} {d['phone1']}")
        elif k == "address" and d.get("address"):
            out.append(addr_text(d))
        elif k == "email" and d.get("email1"):
            out.append(d["email1"])
        elif k == "source" and st["frame"] == "prospects":
            if m.get("sourceUnknown"):
                out.append("source unknown")
            elif d.get("source"):
                out.append(f"from {d['source']}")
            elif d.get("categoryId"):
                out.append(H.tag_names(d["subPillar"], d["categoryId"], d["activityId"])[1])
        elif k == "relation" and "source" not in keys and d.get("categoryId"):
            out.append(f"{d.get('source') or 'that source'} as {H.tag_names(d['subPillar'], d['categoryId'], d['activityId'])[1].lower()}")
        elif k == "followUp":
            out.append(f"follow-up {day_text(d['followUp'], now, m.get('followTime'))}" if d.get("followUp")
                       else "no follow-up")
        elif k == "strength" and d.get("strength"):
            out.append(tx.STRENGTH_NAME[d["strength"]].lower())
        elif k == "loan" and (m.get("loanAmount") or m.get("loanPurpose")):
            out.append((m.get("loanPurpose") or "purchase") + (f" around {money(m['loanAmount'])}" if m.get("loanAmount") else ""))
        elif k == "amount" and d.get("amount"):
            out.append(money(d["amount"], cents=d["amount"] % 1 != 0))
        elif k == "category" and d.get("categoryId"):
            out.append(tx.EXPENSE_CATEGORY_BY_ID[d["categoryId"]]["name"].lower())
        elif k == "vendor" and d.get("vendor"):
            out.append(f"at {d['vendor']}")
        elif k == "withWhom":
            out.append("just you" if m.get("solo") else f"with {d.get('withWhom') or d.get('source')}")
        elif k == "purpose":
            out.append("purpose noted")
        elif k == "activity" and d.get("activityId"):
            out.append(tx.ACTIVITY_BY_ID[d["activityId"]]["name"])
        elif k == "minutes" and d.get("minutes"):
            out.append(H.fmt_minutes(d["minutes"]))
        elif k == "type" and d.get("type"):
            out.append(tx.INCOME_TYPE_NAME[d["type"]].lower())
        elif k == "payer" and d.get("payer"):
            out.append(f"from {d['payer']}")
        elif k == "miles" and d.get("gpsMiles"):
            out.append(f"{d['gpsMiles']:g} miles")
        elif k == "destination" and d.get("destination"):
            out.append(f"to {d['destination']}")
        elif k == "reason" and d.get("reason") and d["reason"].lower() not in (d.get("destination") or "").lower():
            out.append(f"for {d['reason']}")
        elif k == "client" and m.get("name"):
            out.append(m["name"])
        elif k == "size" and d.get("transactionSize"):
            out.append(f"{money(d['transactionSize'])} loan")
        elif k == "income" and d.get("income"):
            out.append(f"you earned {money(d['income'])}")
    return ", ".join(out)


# ======================================================================= questions

def question(conn, st, q, now, prev):
    typ, k = q["type"], q.get("slot")
    d, m = st["data"], st["meta"]
    nm, frame = who(st), st["frame"]
    if typ == "confirm":
        return readback(conn, st, now), []
    if typ == "offer":
        ks = q["slots"]
        again = any(x in st["offered"] for x in ks)
        labels = [(OFFER_THE if again else OFFER_A)[x] for x in ks]
        labels = labels[:1] + [re.sub(r"^(?:an?|the) ", "", x) for x in labels[1:]]
        return f"Do you want to add {join_and(labels)}?", ["Yes", "No"] + (
            [f"{SHORT[x]} only" for x in ks] if len(ks) > 1 else [])
    skip = [] if any(s["key"] == k and s["level"] == R for s in FRAMES[frame]) else ["Skip"]
    if typ == "default":
        v = q["value"]
        if k == "followUp":
            nxt = " next" if frame == "update" else ""
            return (f"When should you follow up with {nm}{nxt} — {day_text(v, now)}?",
                    ["Yes", "Next week", "In 2 weeks", "No follow-up"])
        if k == "income":
            return (f"What did you earn on it? At your usual {closing_yield(conn) * 100:.2f}% that's about {money(v)}.",
                    [f"Yes, {money(v)}", "Different amount"])
    if k in ("address", "phone", "email"):
        if (prev or {}).get("type") == "value" and prev.get("slot") in ("address", "phone", "email") \
                and prev.get("slot") != k:
            return f"And {OFFER_THE[k]}?", skip
        return {"address": "What's the address?", "phone": "What's the phone number?",
                "email": "What's the email address?"}[k], skip
    ch = st.get("chain") or {}
    if frame == "prospects":
        if k == "name":
            if ch.get("total"):
                return f"Lead {ch['i']} of {ch['total']} — what's the name?", ["That's all"]
            if ch:
                return "Go ahead — what's the name?", ["That's all"]
            return "What's the new prospect's name?", []
        if k == "lastName":
            return f"And {nm}'s last name?", []
        if k == "dup":
            when = H.fmt_day(date.fromisoformat(m["dupDate"]), now) if m.get("dupDate") else "before"
            return (f"You already have a {who(st, full=True)} from {when}. Is this the same person?",
                    ["Same person", "New prospect"])
        if k == "source":
            return f"Who referred {nm}, or where did the lead come from?", ["Open house", "Online", "Don't know"]
        if k == "relation":
            return (f"{d.get('source')} is new to me. Who is {d.get('source')} to you — a realtor, a past client, "
                    f"a friend or family member, or another professional?",
                    ["Realtor", "Past client", "Friend or family", "Other professional"])
        if k == "followUp":
            return f"When should you follow up with {nm}?", ["Tomorrow", "Next week", "In 2 weeks", "No follow-up"]
        if k == "strength":
            return f"How hot is {nm} — hot, warm or cold?", ["Hot", "Warm", "Cold"]
        if k == "loan":
            return "Do you know the loan yet — purchase or refinance, and roughly how much?", ["Skip"]
    if frame == "update" and k == "followUp":
        return f"When should you follow up with {nm} next?", ["Tomorrow", "Next week", "In 2 weeks", "No follow-up"]
    if frame == "expenses":
        meal = m.get("meal") or "meal"
        if k == "amount":
            return "How much was it?", []
        if k == "category":
            if m.get("elseAsked"):
                return "In a few words, what was it for?", []
            return ("What was it for — a meal, gas, office supplies, marketing, or something else?",
                    ["Meal", "Gas", "Office supplies", "Marketing", "Gift", "Something else"])
        if k == "withWhom":
            if not m.get("meal"):
                return "Who was the gift for?", skip
            return f"Who was the {meal} with?", ["Just me"] + skip
        if k == "vendor":
            return ("Which restaurant?" if m.get("meal") else "Where did you buy it?"), skip
        if k == "purpose":
            return "What was the business purpose — what did you talk about?", skip
    if frame == "activities":
        if k == "activity":
            mins = f" — {H.fmt_minutes(d['minutes'])}" if d.get("minutes") else ""
            if m.get("elseAsked"):
                return "In a few words, what was it?", []
            return (f"What kind of activity was that{mins}? For example door knocking, an open house, a realtor "
                    "meeting or cold calls.", ["Door knocking", "Open house", "Realtor meeting", "Cold calls",
                                               "Something else"])
        if k == "minutes":
            return f"How long did you spend on {tx.ACTIVITY_BY_ID[d['activityId']]['name']}?", \
                ["30 minutes", "1 hour", "2 hours"]
        if k == "withWhom":
            return "Who was it with?", skip
    if frame == "income":
        if k == "amount":
            return "How much was it?", []
        if k == "type":
            return ("What kind of income — a commission, a referral fee, a bonus, or a consulting fee?",
                    ["Commission", "Referral fee", "Bonus", "Consulting fee"])
        if k == "payer":
            return "Who paid it?", skip
    if frame == "trips":
        if k == "miles":
            return f"How many miles was the drive{' to ' + d['destination'] if d.get('destination') else ''}?", []
        if k == "destination":
            return "Where did you drive to?", skip
        if k == "reason":
            return ("What was the business purpose — a client meeting, a closing, a realtor visit, or an open house?",
                    ["Client meeting", "Closing", "Realtor visit", "Open house", "Office"])
    if frame == "closings":
        if k == "client":
            return "Congratulations! Which client closed?", []
        if k == "pick":
            names = [c["name"] for c in m["candidates"]]
            return f"Which one — {join_and(names).replace(' and ', ' or ')}?", names
        if k == "size":
            return "What was the loan amount?", []
        if k == "income":
            return "What did you earn on it?", []
    return "Can you tell me more?", skip


RETRY_HINT = {"phone": "I didn't catch a phone number — say it like 847 477 0619, or say skip.",
              "email": "I didn't catch an email — say it like tom at gmail dot com, or say skip.",
              "address": "I didn't catch an address — say the street number and name, like 216 Shadow Creek Lane.",
              "amount": "I didn't catch an amount — say it like 45 dollars.",
              "minutes": "How long — for example 30 minutes or 2 hours?",
              "miles": "How many miles — for example 14?",
              "size": "What was the loan amount — for example 520 thousand?",
              "income": "How much did you earn — for example 6,500?"}


# ======================================================================= the dialog

def has_content(st):
    return bool(st["known"]) or bool(st.get("id"))


def has_entry(st):
    """Something worth saving (chain defaults alone don't count)."""
    if st["frame"] == "prospects":
        return "name" in st["known"]
    return has_content(st)


def ask_change(conn, st, now, say, chips=()):
    st["pending"] = {"type": "change"}
    pending = {"type": "change"}
    draft = {"log": save_log(st), "data": final_data(conn, st, now), "summary": summary(conn, st, now, pending)}
    if st.get("id"):
        draft["id"] = st["id"]
    out = H.reply(INTENT[st["frame"]], say, draft=draft, follow_up=True,
                  actions=[{"label": c, "action": "reply", "target": c} for c in chips] +
                          [{"label": "Edit", "action": "edit_draft"},
                           {"label": "Cancel", "action": "reply", "target": "Cancel"}])
    out.update(dialog=st, pending=pending)
    return out


def respond(conn, st, now, lead="", extra=(), soft=""):
    """Ask the next question. `soft` is an echo of what was just captured — dropped when the next step is the
    full readback, which repeats it anyway."""
    prev = st.get("pending") or {}
    q = next_question(conn, st, now)
    same = (q.get("type"), q.get("slot"), tuple(q.get("slots") or ())) == \
        (prev.get("type"), prev.get("slot"), tuple(prev.get("slots") or ()))
    if not same:
        st["tries"] = 0
    text, opts = question(conn, st, q, now, prev)
    if q["type"] == "offer":
        st["offered"] = sorted(set(st["offered"]) | set(q["slots"]))
    q["say"] = text
    st["pending"] = q
    if q["type"] == "confirm":
        actions = [{"label": "Save", "action": "reply", "target": "Save"}, {"label": "Edit", "action": "edit_draft"},
                   {"label": "Cancel", "action": "reply", "target": "Cancel"}]
        if st["frame"] == "expenses" and (st["data"].get("amount") or 0) >= 75:
            actions.append({"label": "Add receipt photo", "action": "open", "target": "expense:scan"})
    else:
        actions = [{"label": o, "action": "reply", "target": o} for o in opts]
        if has_content(st):
            actions.append({"label": "Edit", "action": "edit_draft"})
    pending = {"type": q["type"], "slot": q.get("slot"), "slots": q.get("slots")}
    draft = None
    if has_content(st):
        draft = {"log": save_log(st), "data": final_data(conn, st, now), "summary": summary(conn, st, now, pending)}
        if st.get("id"):
            draft["id"] = st["id"]
    if soft and q["type"] != "confirm":
        lead = " ".join(x for x in (lead, soft) if x)
    out = H.reply(INTENT[st["frame"]], " ".join(x for x in (lead, text) if x), draft=draft,
                  actions=actions + list(extra), follow_up=True)
    out.update(dialog=st, pending=pending)
    return out


def next_question(conn, st, now):
    mode, never = prefs(conn)
    allowed = LEVELS.get(mode, LEVELS["balanced"])
    slots = [s for s in FRAMES[st["frame"]] if not s["when"] or s["when"](st)]

    def is_open(s):
        k = s["key"]
        if k in st["known"] or k in st["skipped"]:
            return False
        return s["level"] == R or k in st["queue"] or (s["level"] in allowed and k not in never)

    todo = [s for s in slots if is_open(s)]
    for k in list(st["queue"]):
        if any(s["key"] == k for s in todo):
            return {"type": "value", "slot": k}
        st["queue"].remove(k)
    if not todo:
        return {"type": "confirm"}
    s = todo[0]
    if s["group"]:
        return {"type": "offer", "slots": [x["key"] for x in todo if x["group"] == s["group"]]}
    if s["kind"] == "default":
        v = default_value(conn, st, s["key"], now)
        if v is not None and not st["meta"].get("noDefault"):
            return {"type": "default", "slot": s["key"], "value": v}
        return {"type": "value", "slot": s["key"]}
    return {"type": s["kind"], "slot": s["key"]}


def end(intent, say, extra_actions=None):
    out = H.reply(intent, say, actions=extra_actions or [])
    out["dialog"] = None
    return out


def ack(st):
    return ("Got it.", "Okay.", "Thanks.", "Great.")[st["turns"] % 4]


def lead_for(st, keys, now, first=False):
    e = echo(st, keys, now)
    if first:
        return f"Got it — {e}." if e else ""
    return (e[:1].upper() + e[1:] + ".") if e else ack(st)


def start(conn, log, text, now, data=None, known=(), meta=None, chain=None, lead=""):
    """First turn: extract everything from the utterance, then ask for what's missing."""
    st = new_state(log, data=data, known=known, meta=meta)
    st["chain"] = chain
    t = clean(text)
    batch = log == "prospects" and BATCH.search(t)
    upd, got = extract(conn, st, t, now)
    if batch:
        upd = {k: v for k, v in upd.items() if k not in ("firstNames", "lastName")}
        got.discard("name")
        got.discard("lastName")
        st["chain"] = st["chain"] or {"total": None, "i": 1, "saved": 0, "defaults": {}, "known": []}
    apply(conn, st, upd, got, now)
    st["turns"] = 1
    if log == "closings" and not lead:
        lead = "Congratulations!" if "client" in st["known"] else ""
    first_lead = lead_for(st, got, now, first=True)
    q = next_question(conn, st, now)
    if q["type"] == "confirm":
        return respond(conn, st, now, lead)
    return respond(conn, st, now, " ".join(x for x in (lead, first_lead) if x))


def match_update(conn, t):
    """'I called Priya Shah, not ready yet' / 'Kevin Morales's email is …' → an existing prospect to update."""
    if re.search(r"\bnew (?:lead|prospect|client|contact)\b|\bclosed\b|\bfunded\b|\breceipt\b", t, re.I):
        return None
    if is_question(t):
        return None
    cue = re.search(r"(?:'s|s')\s+(?:phone|number|cell|mobile|email|address|follow[- ]?up)|"
                    r"\b(?:his|her|their)\s+(?:phone|number|cell|email|address)\b|add (?:a )?note|\bnote (?:for|to|on)\b|"
                    r"\b(?:phone(?: number)?|number|cell|e-?mail|address)\s+(?:is|should be)\b|"
                    r"\bnew (?:phone|number|cell|e-?mail|address) for\b|"
                    r"\b(?:move|change|push|reschedule|set|update)\b.*\bfollow[- ]?up|\bmark\b.*\bas\b|\bupdate\b|"
                    r"\bis (?:now )?(?:red hot|hot|cold|warm|a no go|not interested)\b", t, re.I) or TOUCH.search(t)
    if not cue:
        return None
    cands = prospect_candidates(conn, t)
    if not cands:
        src = H.match_source(conn, t)
        if src and src["kind"] == "person" and len(H.tokens(src["name"])) > 1 and \
                all(x in H.tokens(t) for x in H.tokens(src["name"])):
            return None
        firsts = [c for c in prospect_candidates(conn, t, first_name_ok=True) if not c[1]["closing_id"]]
        if len({c[1]["id"] for c in firsts}) == 1:
            cands = firsts
    return cands[0][1] if cands else None


def start_update(conn, p, text, now):
    t = clean(text)
    name = f"{p['first_names']} {p['last_name']}"
    st = new_state("prospects", "update", meta={"name": name, "existingNotes": p["notes"], "strengthWas": p["strength"]})
    st["id"] = p["id"]
    upd, got = extract(conn, st, t, now)
    m = TOUCH.search(t)
    if m:
        verb = next(v for k, v in TOUCH_VERB if m.group(1).lower().startswith(k))
        after = t[m.end():]
        for tok in name.split():
            after = re.sub(rf"^\W*{re.escape(tok)}\b", "", after, flags=re.I)
        f = FOLLOW_CUE.search(after)
        outcome = (after[:f.start()] if f else after).strip(" ,.;-")
        outcome = re.sub(r"\s*,?\s*(?:and|so)$", "", outcome, flags=re.I).strip(" ,.")
        upd["_addNote"] = f"{now:%b} {now.day}: {verb}" + (f" — {outcome}" if outcome else "") + "."
        upd["_touched"] = True
    apply(conn, st, upd, got, now)
    st["turns"] = 1
    if not got and not m and not st["meta"].get("notes"):
        st["pending"] = {"type": "change"}
        return {**H.reply("update_prospect", f"What would you like to update for {name} — the phone, email, address, "
                                             "follow-up date, or a note?", follow_up=True,
                          actions=[{"label": "Follow-up date", "action": "reply", "target": "Change the follow-up"},
                                   {"label": "Add a note", "action": "reply", "target": "Add a note"}]),
                "dialog": st, "pending": {"type": "change"}}
    return respond(conn, st, now)


def chain_defaults(conn, st):
    act = st["data"].get("activityId")
    tags = next(((sub, cat, a) for _, sub, cat, a in H.CATEGORY_KEYWORDS if a == act), None)
    if not tags:
        return {}, []
    d = tag_update(tags)
    src = st["data"].get("source") or (H.latest_source_for_activity(conn, act) if act in TAG_FROM_ACTIVITY else None)
    if src:
        d["source"] = src
    return d, ["source", "relation"]


def saved_say(st, draft, now):
    d, frame = draft["data"], st["frame"]
    if frame == "prospects":
        s = f"Saved {who(st, full=True)}."
        if d.get("followUp"):
            s += f" I'll remind you to follow up {day_text(d['followUp'], now)}."
        return s
    if frame == "update":
        return f"Updated {st['meta'].get('name')}."
    if frame == "closings":
        return ("Saved as income." if st["meta"].get("repeat") else
                "Saved — congratulations! It's on your income log, and I'll remind you to ask for a review in 14 days.")
    return {"expenses": "Expense saved.", "activities": "Activity saved.", "income": "Income saved.",
            "trips": "Trip saved."}[frame]


def save_now(conn, st, now, save):
    pending = st.get("pending") or {}
    draft = {"log": save_log(st), "data": final_data(conn, st, now), "summary": summary(conn, st, now, pending)}
    if st.get("id"):
        draft["id"] = st["id"]
    try:
        H.confirm(conn, draft, save)
    except Exception as e:  # noqa: BLE001 — surface the validation message and keep the draft
        msg = getattr(e, "message", None) or str(e)
        out = respond(conn, st, now, f"I couldn't save that: {msg}")
        return out
    out = after_save(conn, st, now, save, draft)
    out["saved"] = draft["log"]
    return out


def after_save(conn, st, now, save, draft):
    """What comes next: the leads the user mentioned, the next lead in a batch, or an utterance that was waiting."""
    lead = saved_say(st, draft, now)
    intent = INTENT[st["frame"]]
    ch = st.get("chain")
    if st["frame"] == "activities" and st["meta"].get("leads"):
        n = st["meta"]["leads"]
        nst = new_state("prospects")
        defaults, kn = chain_defaults(conn, st)
        nst["chain"] = {"total": n, "i": 1, "saved": 0, "defaults": defaults, "known": kn}
        nst["pending"] = {"type": "chainOffer"}
        act = tx.ACTIVITY_BY_ID[st["data"]["activityId"]]["name"]
        out = H.reply(intent, f"{lead} You mentioned {n} lead{'s' if n != 1 else ''} from {act} — "
                              f"want to add {'them' if n != 1 else 'it'} now?", follow_up=True,
                      actions=[{"label": "Yes", "action": "reply", "target": "Yes"},
                               {"label": "Later", "action": "reply", "target": "Not now"}])
        out.update(dialog=nst, pending={"type": "chainOffer"})
        return out
    if st["frame"] == "prospects" and ch:
        ch = {**ch, "saved": ch.get("saved", 0) + 1}
        if ch.get("total") and ch["i"] >= ch["total"]:
            return then_queued(conn, st, now, end(intent, f"{lead} That's all {ch['total']} leads."), save)
        nst = new_state("prospects", data=ch.get("defaults"), known=ch.get("known") or [])
        nst["chain"] = {**ch, "i": ch["i"] + 1}
        if ch.get("total"):
            return respond(conn, nst, now, lead)
        nst["pending"] = {"type": "next"}
        out = H.reply(intent, f"{lead} Next lead?", follow_up=True,
                      actions=[{"label": "Yes", "action": "reply", "target": "Yes"},
                               {"label": "That's all", "action": "reply", "target": "That's all"}])
        out.update(dialog=nst, pending={"type": "next"})
        return then_queued(conn, st, now, out, save)
    out = end(intent, lead, [{"label": "Add receipt photo", "action": "open", "target": "expense:scan"}]
              if st["frame"] == "expenses" and (draft["data"].get("amount") or 0) >= 75 else None)
    return then_queued(conn, st, now, out, save)


def then_queued(conn, st, now, out, save):
    """Run an utterance the user said while a draft was waiting ('new prospect …' before saving the last one)."""
    if not st.get("queued"):
        return out
    nxt = H.route(conn, st["queued"], now)
    nxt["say"] = f"{out['say']} {nxt['say']}"
    return nxt


def side_answer(conn, st, t, now):
    intent = H.detect_intent(t)
    if intent in LOG_INTENTS or intent in ("unknown", "smalltalk"):
        return None
    r = H.route(conn, t, now)
    st["pending"] = None
    q = respond(conn, st, now)  # re-ask where we were, with its buttons and the draft card
    q.update(intent=r["intent"], say=f"{r['say']} Back to {who(st, full=True)}: {q['say']}",
             cards=r.get("cards") or [], actions=q["actions"] + [a for a in r.get("actions", [])
                                                                if a.get("action") == "open"])
    return q


def turn(conn, st, text, now, save):
    st = load_state(st)
    if st is None:
        return H.route(conn, clean(text), now)
    t = clean(text)
    p = st.get("pending") or {}
    typ, k = p.get("type"), p.get("slot")
    intent = INTENT.get(st["frame"], "log_prospect")
    st["turns"] += 1
    if not t or REPEAT.match(t):
        return respond(conn, st, now) if typ not in ("next", "chainOffer") else \
            {**H.reply(intent, "Want to add another one?", follow_up=True), "dialog": st, "pending": p}
    if CANCEL.match(t):
        ch = st.get("chain") or {}
        say = "Okay, I won't save that." if has_content(st) and typ not in ("next", "chainOffer") else "Okay."
        if ch.get("saved"):
            say += f" {ch['saved']} lead{'s' if ch['saved'] != 1 else ''} saved."
        return then_queued(conn, st, now, end(intent, say), save)
    if EDIT.match(t) and has_content(st):
        out = respond(conn, st, now, "Opening the form.")
        out.update(dialog=None, openForm=True)
        return out
    if LATER.match(t) and has_entry(st) and typ not in ("next", "chainOffer"):
        return park(conn, st, now, save, t)

    # batch / chain prompts between records
    if typ == "chainOffer":
        if YES.match(t):
            ch = st["chain"]
            nst = new_state("prospects", data=ch.get("defaults"), known=ch.get("known") or [])
            nst["chain"] = ch
            return respond(conn, nst, now)
        return end(intent, "Okay — you can add them from the Log tab any time.")
    if typ == "next":
        ch = st.get("chain") or {}
        if DONE.match(t) or NO.match(t):
            n = ch.get("saved", 0)
            return end("log_prospect", f"All set — {n} lead{'s' if n != 1 else ''} saved.")
        if YES.match(t):
            st["pending"] = None
            return respond(conn, st, now)
        return start(conn, "prospects", t, now, data=ch.get("defaults"), known=ch.get("known") or [], chain=ch)

    # a new entry while this one waits: finish this one first
    if NEW_ENTRY.match(t):
        if has_entry(st):
            st["queued"] = t
            st["pending"] = None
            return respond(conn, st, now, "Sure. Before we start the next one:") if \
                next_question(conn, st, now)["type"] == "confirm" else \
                ask_change(conn, st, now, f"Sure. Should I save {who(st, full=True)} as it is first?", ["Yes", "No"])
        t = NEW_ENTRY.sub("", t).strip(" ,:")
    if st["frame"] == "prospects" and k == "name" and st.get("chain") and DONE.match(t):
        n = st["chain"].get("saved", 0)
        return end("log_prospect", f"All set — {n} lead{'s' if n != 1 else ''} saved.")
    if typ == "change" and st["meta"].pop("noteNext", None):
        apply(conn, st, {"_addNote": t[:1].upper() + t[1:] + "."}, set(), now)
        return respond(conn, st, now, "Noted.")

    upd, got = extract(conn, st, t, now, focus=k if typ in ("value", "choice", "default") else None)

    if typ in ("confirm", "change"):
        if got or any(x in upd for x in ("_addNote", "_tag")):
            apply(conn, st, upd, got, now)
            return respond(conn, st, now, "Got it." if got else "Noted.")
        if SAVE.match(t) and (typ == "confirm" or st.get("queued")):
            return save_now(conn, st, now, save)
        if typ == "change" and (SAVE.match(t) or NO.match(t)):
            if st.get("queued"):  # "no, don't save it" — drop it and move on
                return then_queued(conn, st, now, end(intent, "Okay, I won't save it."), save)
            return respond(conn, st, now, "Okay.")
        if NO.match(t):
            return ask_change(conn, st, now, "What should I change? For example \"the phone is …\" or "
                                             "\"follow up Friday\".")
        if re.search(r"\bfollow[- ]?up\b", t, re.I) and st["frame"] in ("prospects", "update"):
            st["queue"] = ["followUp"]
            if "followUp" in st["known"]:
                st["known"].remove("followUp")
            st["meta"].update(noDefault=True, touched=True)
            return respond(conn, st, now)
        if re.search(r"^(?:add|write|make) (?:a )?note$", t, re.I):
            st["meta"]["noteNext"] = True
            return ask_change(conn, st, now, "What's the note?")
        side = side_answer(conn, st, t, now) if is_question(t) else None
        if side:
            return side
        return respond(conn, st, now, "Sorry, I didn't catch a change. Say yes to save, or tell me what to change —"
                                      " or say Edit to open the form.")

    if typ == "offer":
        S = p.get("slots") or []
        named = [s for s in S if SLOT_WORDS[s].search(t)]
        negated = [s for s in named if SLOT_NEG[s].search(t)]
        chosen = [s for s in named if s not in negated]
        filled = [s for s in S if s in got]
        neg = bool(NO.match(t) or NEG_WORD.search(t))
        if upd:
            apply(conn, st, upd, got, now)
        if filled:
            rest = [s for s in S if s not in got]
            drop = [s for s in rest if s in negated or (ONLY.search(t) and s not in chosen) or (neg and not chosen)]
            msg = decline(conn, st, drop) if drop else None
            return respond(conn, st, now, msg or "", soft=lead_for(st, got, now))
        if named:
            msg = decline(conn, st, negated) if negated else None
            if chosen:
                st["queue"] = chosen
                if ONLY.search(t):
                    decline(conn, st, [s for s in S if s not in named])
            return respond(conn, st, now, msg or ("Okay." if negated and not chosen else ""))
        if YES.match(t):
            st["queue"] = list(S)
            return respond(conn, st, now)
        if neg:
            msg = decline(conn, st, S)
            return respond(conn, st, now, msg or "Okay.")
        if got:
            return respond(conn, st, now, soft=lead_for(st, got, now))
        side = side_answer(conn, st, t, now) if is_question(t) else None
        if side:
            return side
        st["tries"] += 1
        if st["tries"] < 2:
            return respond(conn, st, now, "Sorry — you can say yes, no, or just tell me.")
        decline(conn, st, S)
        return respond(conn, st, now, "I'll skip that for now.")

    # value / choice / default
    if k in got:
        apply(conn, st, upd, got, now)
        if k == "dup":
            if st["frame"] == "update":
                if not st["data"] and not st["meta"].get("notes"):
                    return ask_change(conn, st, now, f"Okay — what would you like to update for {who(st)}: the "
                                                     "phone, email, address, follow-up date, or a note?")
                return respond(conn, st, now, "Okay — I'll update the one you have.")
            return respond(conn, st, now, "Okay — a new prospect.")
        return respond(conn, st, now, soft=lead_for(st, got, now))
    if typ == "default" and YES.match(t):
        if k == "followUp":
            upd["followUp"] = p["value"]
        elif k == "income":
            upd["income"] = p["value"]
        apply(conn, st, upd, got | {k}, now)
        return respond(conn, st, now, soft=lead_for(st, {k}, now))
    if typ == "default" and (NO.match(t) or re.search(r"different|another|pick a day|other", t, re.I)):
        st["meta"]["noDefault"] = True
        if upd:
            apply(conn, st, upd, got, now)
        return respond(conn, st, now, "Okay.")
    required = any(s["key"] == k and s["level"] == R for s in FRAMES[st["frame"]])
    if k == "source" and st["frame"] == "prospects" and (NO.match(t) or DONE.match(t) or UNKNOWN.search(t)):
        apply(conn, st, {"_sourceUnknown": True, "_sourceNew": False}, {"source"}, now)
        return respond(conn, st, now, f"Okay — I'll mark the source unknown and put {who(st)} in your Review queue "
                                      "so you can fill it in later.")
    if typ == "choice" and re.search(r"something else|\bother\b|else", t, re.I) and k in ("category", "activity") \
            and not st["meta"].get("elseAsked"):
        st["meta"]["elseAsked"] = True
        return respond(conn, st, now)
    if (NO.match(t) or DONE.match(t)) and not got:
        if required:
            return respond(conn, st, now, f"I need that one to save it. Or say Edit to use the form, or cancel.")
        msg = decline(conn, st, [k])
        return respond(conn, st, now, msg or "No problem.")
    if got:
        apply(conn, st, upd, got, now)
        return respond(conn, st, now, soft=lead_for(st, got, now))
    side = side_answer(conn, st, t, now) if is_question(t) else None
    if side:
        return side
    st["tries"] += 1
    if st["tries"] < 2:
        return respond(conn, st, now, RETRY_HINT.get(k) or "Sorry, I didn't catch that.")
    if k == "dup":  # don't block on it: keep it as a new prospect
        apply(conn, st, {"_dupAnswer": "new"}, {"dup"}, now)
        return respond(conn, st, now, "I'll keep it as a new prospect.")
    if k in ("category", "activity") and st["meta"].get("elseAsked"):
        if k == "category":
            apply(conn, st, {"groupId": "general", "categoryId": "exp.general.office_supplies", "reviewed": False},
                  {"category"}, now)
            return respond(conn, st, now, "I'll file it under General for now and put it in your Review queue.")
    if required:
        out = respond(conn, st, now, "Let's do this one on the form.")
        return out
    decline(conn, st, [k])
    return respond(conn, st, now, "I'll leave that blank — you can add it later.")


MISSING_LABEL = {"name": "the name", "lastName": "the last name", "address": "the address", "phone": "the phone number",
                 "email": "the email", "source": "the source", "relation": "who the source is", "followUp": "a follow-up date",
                 "strength": "lead strength", "loan": "the loan", "amount": "the amount", "category": "the category",
                 "withWhom": "who it was with", "vendor": "the vendor", "purpose": "the business purpose",
                 "activity": "the activity", "minutes": "the time", "type": "the income type", "payer": "the payer",
                 "miles": "the miles", "destination": "the destination", "reason": "the business purpose",
                 "size": "the loan amount", "income": "what you earned", "client": "the client", "dup": "duplicate check"}


def park(conn, st, now, save, text=""):
    """'Finish later': save what we have, unreviewed, so it waits in the Review queue instead of getting lost."""
    mode, never = prefs(conn)
    allowed = LEVELS.get(mode, LEVELS["balanced"])
    missing = [s["key"] for s in FRAMES[st["frame"]] if (not s["when"] or s["when"](st)) and s["key"] not in st["known"]
               and s["key"] not in st["skipped"] and (s["level"] in allowed or s["level"] == R) and s["key"] not in never]
    if st["meta"].get("sourceUnknown"):
        missing.append("source")
    if any(s["key"] in missing and s["level"] == R for s in FRAMES[st["frame"]]) and \
            st["frame"] not in ("prospects", "update"):
        return respond(conn, st, now, "I need a bit more before I can hold it — or say cancel.")
    st["data"]["reviewed"] = False
    if missing:
        st["meta"].setdefault("notes", []).append(
            "HERB: still need " + join_and([MISSING_LABEL.get(k, k) for k in missing if k != "dup"]) + ".")
    draft = {"log": save_log(st), "data": final_data(conn, st, now)}
    if st.get("id"):
        draft["id"] = st["id"]
    try:
        H.confirm(conn, draft, save)
    except Exception as e:  # noqa: BLE001
        return respond(conn, st, now, f"I couldn't hold it: {getattr(e, 'message', None) or e}")
    say = "Saved to your Review queue" + (f" — I'll ask about {join_and([MISSING_LABEL.get(k, k) for k in missing if k != 'dup'])} later."
                                           if missing else ".") + (" Drive safe." if "driv" in text.lower() else "")
    out = end(INTENT[st["frame"]], say)
    out["saved"] = draft["log"]
    return out


def decline(conn, st, keys):
    for k in keys:
        if k not in st["skipped"]:
            st["skipped"].append(k)
        if k in st["queue"]:
            st["queue"].remove(k)
    return learn(conn, keys)
