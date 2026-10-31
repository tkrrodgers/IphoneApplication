"""Print HERB conversations against a fresh in-memory copy of the synthetic data (dev aid)."""
import os
import sys
from datetime import date

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "herb-sim"))
os.environ["SIM_TODAY"] = "2026-10-30"

import db  # noqa: E402
import herb  # noqa: E402
import seed  # noqa: E402
import server  # noqa: E402

NOW = date(2026, 10, 30)
conn = db.connect(":memory:")
seed.build(conn, NOW)


def saver(log, data, rid=None):
    return server.update_log(conn, log, rid, data) if rid else server.save_log(conn, log, data)


SCRIPTS = [
    ["Hi Herb, new prospect Tom Rodgers, 216 Shadow Creek Lane, Hickory Creek Texas, 847-477-0619, Follow up next week",
     "Ruth Alvarez sent him", "yes"],
    ["Hi Herb, New Prospect, Tom Rodgers, 847-477-0619, Follow up next week", "yes",
     "216 Shadow Creek Lane, Hickory Creek, Texas", "skip", "yes"],
    ["Hi Herb, new prospect Tom Rodgers, follow up next week", "phone number only", "847 477 0619",
     "Sam Lee", "he's a realtor", "save it"],
    ["new prospect Tom Rodgers", "yes", "216 Shadow Creek Lane in Hickory Creek", "847-477-0619",
     "from an open house", "monday", "actually make it Tuesday", "yes"],
    ["new prospect Tom Rodgers", "847-477-0619", "no", "my neighbor", "yes", "yes"],
    ["new prospect Tom Rodgers", "no address, just the phone", "8474770619", "not sure", "no", "next week", "yes"],
    ["I spent 45 dollars", "lunch", "Dana Ruiz", "Cedar Grill", "yes"],
    ["I spent two hours door knocking and got two leads", "yes", "yes", "Maria Lopez 940-555-0101", "no",
     "tomorrow", "yes", "Ben Ortiz", "skip", "yes"],
    ["I called Priya Shah, she's not ready yet, follow up in two weeks", "yes"],
    ["I called Priya Shah, left a voicemail", "Thursday", "yes"],
    ["Kevin Morales's email is kevin.morales@example.com", "yes"],
    ["I have some leads to record", "Ana Torres, 940-555-0144, Dana Ruiz sent her", "no", "yes", "yes",
     "that's all"],
    ["got paid 3,000", "referral fee", "Lakeside Realty", "yes"],
    ["drove 12 miles", "to the title company", "yes"],
    ["new prospect Tom Rodgers 847-477-0619", "which sources never close?", "no", "Zillow", "yes", "yes"],
    ["the Morales loan closed", "520 thousand", "yes", "yes"],
    ["new prospect Kevin Morales", "same person", "940-555-0199", "yes"],
    ["new prospect Tom Rodgers, 847-477-0619", "new prospect Mary Jones", "yes"],
]

only = [int(a) for a in sys.argv[1:]]
for n, script in enumerate(SCRIPTS):
    if only and n not in only:
        continue
    print("=" * 40, n)
    seed.build(conn, NOW)
    dialog = None
    for line in script:
        r = herb.ask(conn, line, NOW, dialog=dialog, save=saver)
        dialog = r.get("dialog")
        pend = r.get("pending") or {}
        print(f"  YOU : {line}")
        print(f"  HERB: {r['say']}")
        tags = [a['label'] for a in r.get('actions', [])]
        print(f"        [{r['intent']}] pending={pend.get('type')}:{pend.get('slot') or pend.get('slots')} chips={tags}"
              + (f"  ERR {r['display']}" if r.get("display") else ""))
        if not dialog:
            if line != script[-1]:
                print("        (dialog ended)")
    if dialog:
        print("        (still open)")
