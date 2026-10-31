import os
import sys
import unittest
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ["SIM_TODAY"] = "2026-10-30"

import db  # noqa: E402
import herb  # noqa: E402
import seed  # noqa: E402
import server  # noqa: E402

NOW = date(2026, 10, 30)
CONN = None


def setUpModule():
    global CONN
    CONN = db.connect(":memory:")
    seed.build(CONN, NOW)


def tearDownModule():
    CONN.close()


def ask(text):
    return herb.ask(CONN, text, NOW)


class ParserTests(unittest.TestCase):
    def test_amounts(self):
        self.assertEqual(herb.amounts("about 520 thousand")[0][0], 520000)
        self.assertEqual(herb.amounts("$86.40 at Cedar Grill")[0][0], 86.4)
        self.assertEqual(herb.amounts("a 2k bonus")[0][0], 2000)
        self.assertEqual(herb.amounts("I made 6,500")[0][0], 6500)
        self.assertEqual(herb.amounts("talk Thursday after 5"), [])
        self.assertEqual(herb.amounts("drove 14 miles"), [])

    def test_durations(self):
        self.assertEqual(herb.duration_minutes("two hours of door knocking"), 120)
        self.assertEqual(herb.duration_minutes("forty five minutes"), 45)
        self.assertEqual(herb.duration_minutes("an hour and a half"), 90)
        self.assertEqual(herb.duration_minutes("90 minutes"), 90)
        self.assertIsNone(herb.duration_minutes("lunch with Dana"))

    def test_phone_and_wake(self):
        self.assertEqual(herb.phone("call 940-555-0137 today")[0], "(940) 555-0137")
        self.assertEqual(herb.strip_wake("Hi Herb, what's up"), "what's up")
        self.assertEqual(herb.strip_wake("Hey Siri, ask Herb who I need to call"), "who I need to call")

    def test_when(self):
        self.assertEqual(herb.parse_when("Thursday after five", NOW), date(2026, 11, 5))
        self.assertEqual(herb.parse_when("tomorrow", NOW), date(2026, 10, 31))
        self.assertEqual(herb.parse_when("in 3 days", NOW), date(2026, 11, 2))


class IntentTests(unittest.TestCase):
    def test_record_lead_design_example(self):
        r = ask("Kevin Morales, 940-555-0137, Ruth Alvarez at Cedar and Main sent him, move-up buyer about 520, "
                "Thursday after five")
        self.assertEqual(r["intent"], "log_prospect")
        d = r["draft"]["data"]
        self.assertEqual((d["firstNames"], d["lastName"]), ("Kevin", "Morales"))
        self.assertEqual(d["phone1"], "(940) 555-0137")
        self.assertEqual(d["source"], "Ruth Alvarez")
        self.assertEqual(d["categoryId"], "cat.realtor")
        self.assertIn("520,000", d["notes"])
        self.assertEqual(d["followUp"], "2026-11-05")

    def test_new_lead_open_house(self):
        r = ask("New lead from Saturday's open house, Nora Diaz, she's just looking")
        d = r["draft"]["data"]
        self.assertEqual(d["categoryId"], "cat.open_house")
        self.assertTrue(d["source"].startswith("Open house"))
        self.assertEqual(d["strength"], "cold")

    def test_past_client_referral_goes_to_clients(self):  # rule R2
        r = ask("New prospect Owen Park, Greg Wallace referred him")
        self.assertEqual(r["draft"]["data"]["pillar"], "clients")
        self.assertEqual(r["draft"]["data"]["categoryId"], "cat.past_client")

    def test_leads_to_record_prompts(self):
        r = ask("Hi Herb, I have some leads to record.")
        self.assertEqual(r["intent"], "log_prospect")
        self.assertNotIn("draft", r)
        self.assertTrue(r.get("followUp"))

    def test_closing(self):
        r = ask("The Morales loan closed, 520 thousand, I made 6,500")
        self.assertEqual(r["intent"], "log_closing")
        d = r["draft"]["data"]
        self.assertEqual(d["transactionSize"], 520000)
        self.assertEqual(d["income"], 6500)
        self.assertIsNotNone(d.get("prospectId"))

    def test_expense_meal_with_partner(self):
        r = ask("Log a $42 lunch with Jared")
        d = r["draft"]["data"]
        self.assertEqual(r["intent"], "log_expense")
        self.assertEqual(d["amount"], 42)
        self.assertEqual(d["categoryId"], "exp.relationships.meal")
        self.assertEqual(d["withWhom"], "Jared Cole")

    def test_expense_vendor(self):
        r = ask("Lunch with Dana, 86 dollars at Cedar Grill")
        d = r["draft"]["data"]
        self.assertEqual((d["vendor"], d["amount"]), ("Cedar Grill", 86))
        r = ask("Bought printer paper at Office Depot for $43.17")
        self.assertEqual(r["draft"]["data"]["categoryId"], "exp.general.office_supplies")
        self.assertEqual(r["draft"]["data"]["amount"], 43.17)

    def test_scan_receipt(self):
        r = ask("Scan a receipt")
        self.assertEqual(r["actions"][0]["target"], "expense:scan")

    def test_activity(self):
        r = ask("I spent two hours door knocking and got three leads")
        d = r["draft"]["data"]
        self.assertEqual((r["intent"], d["activityId"], d["minutes"]), ("log_activity", "act.door_knocking", 120))
        r = ask("an hour and a half at the open house")
        self.assertEqual(r["draft"]["data"]["minutes"], 90)

    def test_income(self):
        r = ask("Got a 2,000 referral fee from Lakeside Realty")
        d = r["draft"]["data"]
        self.assertEqual((d["amount"], d["type"], d["payer"]), (2000, "referral_fees", "Lakeside Realty"))

    def test_trip(self):
        r = ask("I drove to the title company, 14 miles")
        self.assertEqual(r["draft"]["data"]["gpsMiles"], 14)
        r = ask("Start a business trip to Lakeside Realty")
        self.assertEqual(r["intent"], "log_trip")
        r = ask("End trip")
        self.assertEqual(r["draft"]["log"], "trips")
        self.assertGreater(r["draft"]["data"]["gpsMiles"], 0)

    def test_focus(self):
        r = ask("What should I focus on this week to make more money?")
        self.assertEqual(r["intent"], "focus")
        self.assertEqual(len([c for c in r["cards"] if c["chip"] == "focus"]), 3)
        self.assertIn("Three things this week", r["say"])

    def test_follow_ups_via_siri(self):
        r = ask("Hey Siri, ask Herb who I need to follow up with")
        self.assertEqual(r["intent"], "follow_ups")
        self.assertIn("Priya Shah", r["say"] + " ".join(c["title"] for c in r["cards"]))

    def test_queries(self):
        cases = {"Am I on track?": "pace", "Which sources never close?": "sources_no_close",
                 "What's my Logsperity Index?": "index", "Where am I wasting time?": "efficiency",
                 "Which pillar has the best return?": "roi", "Which pillar converts best?": "conversion",
                 "Which agencies generated the most income for me this year, not just leads?": "top_sources",
                 "What does Herb need from me?": "review", "How many miles have I driven?": "mileage_summary",
                 "What can you do?": "help", "What's my business plan?": "plan"}
        for text, intent in cases.items():
            with self.subTest(text=text):
                r = ask(text)
                self.assertEqual(r["intent"], intent)
                self.assertTrue(r["say"])

    def test_sources_never_close_names_leadboost(self):
        self.assertIn("LeadBoost", ask("Which sources never close?")["say"])

    def test_report(self):
        r = ask("Email me the March report")
        self.assertEqual(r["actions"][0]["target"], "report:month_03")
        self.assertEqual(r["actions"][1]["target"], "email:month_03")

    def test_confirm_saves(self):
        r = ask("New lead, Hannah Brooks, 940-555-0199, Dana Ruiz sent her")
        before = CONN.execute("SELECT COUNT(*) FROM prospects").fetchone()[0]
        out = herb.confirm(CONN, r["draft"], lambda log, data: server.save_log(CONN, log, data))
        self.assertTrue(out["ok"])
        self.assertEqual(CONN.execute("SELECT COUNT(*) FROM prospects").fetchone()[0], before + 1)
        self.assertEqual(out["row"]["sourceName"], "Dana Ruiz")


class CoachingTests(unittest.TestCase):
    def test_story_rules_fire(self):
        keys = [i["key"] for i in herb.insights(CONN, NOW)]
        joined = " ".join(keys)
        self.assertIn("zombie.LeadBoost", keys)
        self.assertIn("conv.activity.act.door_knocking", keys)
        self.assertIn("timesink.act.open_houses", keys)
        self.assertTrue(any(k.startswith("drift.") for k in keys), joined)

    def test_review_queue_has_auto_items(self):
        items = herb.review_items(CONN, NOW)
        self.assertGreaterEqual(len(items), 8)
        self.assertEqual({i["log"] for i in items} >= {"trips", "expenses", "activities", "prospects"}, True)

    def test_checkin(self):
        c = herb.checkin(CONN, {}, NOW)
        self.assertEqual(len(c["steps"]), 6)
        self.assertEqual(len(c["commitments"]), 3)


if __name__ == "__main__":
    unittest.main()
