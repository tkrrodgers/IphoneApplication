"""Starts the real HTTP server on a free port against a temporary seeded database and hits every endpoint."""
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ["SIM_TODAY"] = "2026-10-30"
os.environ["HERB_QUIET"] = "1"
TMP = tempfile.mkdtemp(prefix="herbsim")
os.environ["HERB_DB"] = os.path.join(TMP, "test.db")

import db  # noqa: E402
import reports  # noqa: E402
import seed  # noqa: E402
import server  # noqa: E402

BASE = None
SRV = None

WIDGET_FIELDS = {"stat": ["display"], "stats": ["items"], "table": ["columns", "rows"], "bar": ["items"],
                 "pie": ["items"], "donut": ["items"], "stack": ["items"], "progress": ["items"],
                 "index": ["display", "drivers"], "text": ["paragraphs"], "list": ["items"],
                 "columns": ["series", "items"]}


def setUpModule():
    global BASE, SRV
    conn = db.connect()
    seed.build(conn, date(2026, 10, 30))
    conn.close()
    SRV = server.make_server(0)
    BASE = f"http://127.0.0.1:{SRV.server_address[1]}"
    threading.Thread(target=SRV.serve_forever, daemon=True).start()


def tearDownModule():
    SRV.shutdown()
    SRV.server_close()


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode()), r.headers
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode()), e.headers


class ApiTests(unittest.TestCase):
    def check_widgets(self, widgets, where):
        self.assertIsInstance(widgets, list, where)
        for w in widgets:
            self.assertIn(w.get("type"), WIDGET_FIELDS, f"{where}: bad widget {w.get('type')}")
            self.assertIn("title", w, where)
            for f in WIDGET_FIELDS[w["type"]]:
                self.assertIn(f, w, f"{where}: {w['type']} '{w['title']}' missing {f}")
            if w["type"] == "table":
                keys = {c["key"] for c in w["columns"]}
                self.assertTrue(all("label" in c for c in w["columns"]))
                for row in w["rows"][:3]:
                    self.assertTrue(keys & set(row), f"{where}: table '{w['title']}' rows don't match columns")
            if w["type"] in ("bar", "pie", "donut", "stack"):
                for it in w["items"]:
                    self.assertIn("label", it)
                    self.assertIn("display", it)
                    self.assertIsInstance(it["value"], (int, float))
            json.dumps(w)

    def test_static_and_headers(self):
        req = urllib.request.Request(BASE + "/")
        with urllib.request.urlopen(req) as r:
            self.assertEqual(r.status, 200)
            self.assertIn("no-store", r.headers["Cache-Control"])

    def test_reference_endpoints(self):
        s, tx, _ = call("GET", "/api/taxonomy")
        self.assertEqual(s, 200)
        self.assertEqual(len(tx["categories"]), 63)
        self.assertEqual(len(tx["activities"]), 53)
        self.assertEqual(len(tx["pillars"]), 4)
        s, src, _ = call("GET", "/api/sources?q=ruth")
        self.assertEqual(src[0]["name"], "Ruth Alvarez")

    def test_account_never_stores_cards(self):
        s, acct, _ = call("PUT", "/api/account", {"title": "Broker", "cardNumber": "4111111111111111",
                                                   "securityCode": "123", "plan": "annual"})
        self.assertEqual(s, 200)
        self.assertEqual(acct["title"], "Broker")
        self.assertNotIn("cardNumber", json.dumps(acct))
        self.assertEqual(acct["subscription"]["via"], "Apple In-App Purchase (simulated)")
        self.assertEqual(acct["subscription"]["price"], "$500/year")

    def test_plan(self):
        s, p, _ = call("GET", "/api/plan")
        self.assertEqual(p["inputs"]["grossIncomeGoal"], 180000)
        s, p, _ = call("PUT", "/api/plan?year=2027", {"inputs": {"grossIncomeGoal": 150000, "netProfitGoal": 125000,
                                                                 "avgCommission": 6500, "avgTransactionSize": 335000,
                                                                 "hoursPerWeek": 40, "vacationWeeks": 0}})
        self.assertAlmostEqual(p["outputs"]["hourlyGross"], 72.115, places=2)

    def test_logs_crud(self):
        for log in db.LOG_TABLES:
            s, r, _ = call("GET", f"/api/{log}?period=ytd&limit=5")
            self.assertEqual(s, 200, log)
            self.assertIn("totals", r)
            self.assertLessEqual(len(r["rows"]), 5)
        s, r, _ = call("POST", "/api/prospects", {"firstNames": "Test", "lastName": "Person", "categoryId": "cat.realtor",
                                                  "activityId": "act.partner_coaching", "source": "Dana Ruiz"})
        self.assertEqual(s, 201)
        pid = r["row"]["id"]
        self.assertEqual(r["row"]["pillar"], "relationships")
        self.assertEqual(r["row"]["sourceName"], "Dana Ruiz")
        s, r, _ = call("POST", "/api/closings", {"prospectId": pid, "transactionSize": 400000, "income": 5200})
        self.assertEqual(s, 201)
        s, r, _ = call("POST", "/api/closings", {"prospectId": pid, "transactionSize": 1, "income": 1})
        self.assertEqual(s, 409)
        s, r, _ = call("POST", "/api/expenses", [{"vendor": "A", "amount": 10, "categoryId": "exp.general.postage"},
                                                 {"vendor": "B", "amount": "$1,200.50",
                                                  "categoryId": "exp.clients.client_appreciation_party"}])
        self.assertEqual(len(r["rows"]), 2)
        self.assertEqual(r["rows"][1]["amount"], 1200.5)
        self.assertEqual(r["rows"][1]["irs"], "Advertising")
        eid = r["rows"][0]["id"]
        s, r, _ = call("PUT", f"/api/expenses/{eid}", {"amount": 12})
        self.assertEqual(r["row"]["amount"], 12)
        s, r, _ = call("DELETE", f"/api/expenses/{eid}")
        self.assertEqual(s, 200)
        s, r, _ = call("POST", "/api/expenses", {"vendor": "X", "amount": 1, "categoryId": "exp.nope"})
        self.assertEqual(s, 400)

    def test_today_review_coach(self):
        s, t, _ = call("GET", "/api/today")
        self.assertEqual(len(t["kpis"]), 4)
        self.assertTrue(t["followUps"])
        self.assertGreaterEqual(t["reviewCount"], 8)
        s, items, _ = call("GET", "/api/review")
        first = items[0]["id"]
        s, r, _ = call("POST", f"/api/review/{first}", {"action": "confirm", "patch": {}})
        self.assertEqual(r["remaining"], len(items) - 1)
        s, c, _ = call("GET", "/api/coach")
        self.assertIn("drivers", c["index"])
        self.assertTrue(c["insights"])
        self.assertEqual(len(c["plan"]["items"]), 4)
        s, ch, _ = call("POST", "/api/coach/checkin", {})
        self.assertEqual(len(ch["steps"]), 6)

    def test_every_report(self):
        s, menu, _ = call("GET", "/api/reports")
        keys = [i["key"] for g in menu["groups"] for i in g["items"]]
        self.assertEqual(set(keys), set(reports.REPORTS))
        for key in keys:
            with self.subTest(report=key):
                s, r, _ = call("GET", f"/api/reports/{key}")
                self.assertEqual(s, 200, r)
                self.assertTrue(r["widgets"], key)
                self.check_widgets(r["widgets"], key)
        for period in ("month", "q:2026-2", "year:2025", "last30", "custom:2026-02-01:2026-03-15"):
            s, r, _ = call("GET", f"/api/reports/prospects?period={period}")
            self.assertEqual(s, 200, period)
            self.assertEqual(r["period"]["key"], period)
        s, r, _ = call("GET", "/api/reports/nope")
        self.assertEqual(s, 404)

    def test_annual_report(self):
        for version in ("complete", "streamlined", "ytd"):
            s, r, _ = call("GET", f"/api/annual-report?version={version}")
            self.assertEqual(s, 200)
            self.assertTrue(r["pages"])
            for p in r["pages"]:
                self.check_widgets(p["widgets"], f"annual {version} / {p['title']}")

    def test_autopilot(self):
        s, a, _ = call("GET", "/api/autopilot")
        self.assertEqual(len(a), 10)
        s, a, _ = call("PUT", "/api/autopilot", {"key": "mileage", "level": 4})
        self.assertEqual(next(x for x in a if x["key"] == "mileage")["level"], 4)
        s, a, _ = call("PUT", "/api/autopilot", {"key": "messages", "level": 4})
        self.assertEqual(s, 400)  # HERB never sends messages

    def test_herb_round_trip(self):
        s, r, _ = call("POST", "/api/herb", {"text": "Hi Herb, two hours of door knocking"})
        self.assertEqual(r["intent"], "log_activity")
        s, c, _ = call("POST", "/api/herb/confirm", {"draft": r["draft"]})
        self.assertTrue(c["ok"])
        self.assertEqual(c["row"]["minutes"], 120)
        s, r, _ = call("POST", "/api/herb", {"text": "What should I focus on this week?"})
        self.assertEqual(r["intent"], "focus")

    def test_herb_follow_up_conversation(self):
        """The dialog state round-trips through the API until the user says yes."""
        dialog, said = None, []
        for text in ("Hi Herb, new prospect Tess Walden, follow up next week", "phone number only",
                     "940-555-0177", "from Zillow", "yes"):
            s, r, _ = call("POST", "/api/herb", {"text": text, "dialog": dialog})
            self.assertEqual(s, 200)
            dialog = r.get("dialog")
            said.append(r["say"])
        self.assertIn("Do you want to add an address and phone number?", said[0])
        self.assertEqual(said[1], "What's the phone number?")
        self.assertTrue(said[3].endswith("Save it?"), said[3])
        self.assertIsNone(dialog)
        self.assertEqual(r["saved"], "prospects")
        s, rows, _ = call("GET", "/api/prospects?q=Walden")
        self.assertEqual(rows["rows"][0]["phone1"], "(940) 555-0177")
        s, a, _ = call("PUT", "/api/account", {"herbQuestions": "quick"})
        self.assertEqual(a["herbQuestions"], "quick")
        s, r, _ = call("POST", "/api/herb", {"text": "new prospect Uma Vance"})
        self.assertEqual(r["pending"]["slot"], "source")  # Quick mode still asks the source (D3)
        s, r, _ = call("POST", "/api/herb", {"text": "I don't know", "dialog": r["dialog"]})
        self.assertEqual(r["pending"]["type"], "confirm")
        self.assertEqual(r["draft"]["data"]["source"], "Unknown")
        call("PUT", "/api/account", {"herbQuestions": "balanced"})

    def test_scorecard(self):
        s, r, _ = call("GET", "/api/scorecard?log=closings&measure=income&dimension=category")
        self.assertEqual(s, 200)
        self.assertGreater(r["total"], 0)

    def test_unknown_route(self):
        s, r, _ = call("GET", "/api/nothing")
        self.assertEqual(s, 404)


if __name__ == "__main__":
    unittest.main()
