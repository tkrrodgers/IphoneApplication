"""Follow-up questions (design §17.6): HERB asks for what was left out, and accepts yes / no / "phone only" /
the value itself / corrections, without saving until the user confirms."""
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

NOW = date(2026, 10, 30)  # a Friday; "next week" is Monday Nov 2


class Convo:
    """Drives one conversation the way the app does: the dialog state from each reply goes back with the next."""

    def __init__(self, conn):
        self.conn, self.dialog, self.last = conn, None, None

    def say(self, text):
        self.last = herb.ask(self.conn, text, NOW, dialog=self.dialog, save=self.save)
        self.dialog = self.last.get("dialog")
        return self.last

    def save(self, log, data, rid=None):
        return server.update_log(self.conn, log, rid, data) if rid else server.save_log(self.conn, log, data)

    @property
    def pending(self):
        return self.last.get("pending") or {}

    @property
    def data(self):
        return self.last["draft"]["data"]


class DialogTest(unittest.TestCase):
    def setUp(self):
        self.conn = db.connect(":memory:")
        seed.build(self.conn, NOW)
        self.c = Convo(self.conn)

    def tearDown(self):
        self.conn.close()

    def prospect(self, last="Rodgers"):
        return db.one(self.conn.execute("SELECT * FROM prospects WHERE last_name = ? ORDER BY id DESC", (last,)))

    def set_mode(self, mode):
        a = db.get_account(self.conn)
        a["herbQuestions"] = mode
        db.set_account(self.conn, a)


class ProspectFollowUps(DialogTest):
    def test_complete_entry_only_asks_for_the_source(self):
        r = self.c.say("Hi Herb, new prospect Tom Rodgers, 216 Shadow Creek Lane, Hickory Creek Texas, 847-477-0619, "
                       "Follow up next week")
        d = self.c.data
        self.assertEqual((d["firstNames"], d["lastName"], d["phone1"]), ("Tom", "Rodgers", "(847) 477-0619"))
        self.assertEqual((d["address"], d["city"], d["state"]), ("216 Shadow Creek Lane", "Hickory Creek", "TX"))
        self.assertEqual(d["followUp"], "2026-11-02")
        self.assertEqual(self.c.pending, {"type": "value", "slot": "source", "slots": None})
        self.assertIn("Who referred Tom", r["say"])
        r = self.c.say("Ruth Alvarez sent him")
        self.assertEqual(self.c.pending["type"], "confirm")
        self.assertTrue(r["say"].endswith("Save it?"))
        self.c.say("yes")
        p = self.prospect()
        self.assertEqual((p["address"], p["city"], p["state"], p["phone1"]),
                         ("216 Shadow Creek Lane", "Hickory Creek", "TX", "(847) 477-0619"))
        self.assertEqual(p["category_id"], "cat.realtor")
        self.assertIsNone(self.c.dialog)

    def test_missing_address_is_offered(self):
        r = self.c.say("Hi Herb, New Prospect, Tom Rodgers, 847-477-0619, Follow up next week")
        self.assertIn("Do you want to add an address?", r["say"])
        self.assertEqual(self.c.pending["slots"], ["address"])

    def test_missing_address_and_phone_offered_together(self):
        r = self.c.say("Hi Herb, new prospect Tom Rodgers, follow up next week")
        self.assertIn("Do you want to add an address and phone number?", r["say"])
        self.assertEqual(self.c.pending["slots"], ["address", "phone"])

    def test_phone_number_only(self):
        self.c.say("new prospect Tom Rodgers, follow up next week")
        r = self.c.say("phone number only")
        self.assertEqual(r["say"], "What's the phone number?")
        r = self.c.say("847 477 0619")
        self.assertIn("(847) 477-0619", r["say"])
        self.assertEqual(self.c.pending["slot"], "source")  # address was declined: not offered again

    def test_yes_asks_each_value_in_turn(self):
        self.c.say("new prospect Tom Rodgers, follow up next week")
        self.assertEqual(self.c.say("yes")["say"], "What's the address?")
        r = self.c.say("216 Shadow Creek Lane in Hickory Creek")
        self.assertIn("And the phone number?", r["say"])
        self.c.say("847-477-0619")
        self.assertEqual(self.c.data["city"], "Hickory Creek")
        self.assertEqual(self.c.data["phone1"], "(847) 477-0619")

    def test_giving_the_phone_reoffers_the_address(self):
        self.c.say("new prospect Tom Rodgers, follow up next week")
        r = self.c.say("847-477-0619")
        self.assertIn("Do you want to add the address?", r["say"])
        r = self.c.say("No")
        self.assertEqual(self.c.pending["slot"], "source")
        self.c.say("216 Shadow Creek Lane")  # changing one's mind later still works
        self.assertEqual(self.c.data["address"], "216 Shadow Creek Lane")

    def test_address_given_directly_reoffers_phone(self):
        self.c.say("new prospect Tom Rodgers, follow up next week")
        r = self.c.say("216 Shadow Creek Lane, Hickory Creek, Texas")
        self.assertIn("Do you want to add the phone number?", r["say"])

    def test_no_address_just_the_phone(self):
        self.c.say("new prospect Tom Rodgers")
        r = self.c.say("no address, just the phone")
        self.assertEqual(r["say"], "What's the phone number?")

    def test_no_declines_both(self):
        self.c.say("new prospect Tom Rodgers, follow up next week")
        self.c.say("no")
        self.assertEqual(self.c.pending["slot"], "source")

    def test_spoken_email_in_thorough_mode(self):
        self.set_mode("thorough")
        r = self.c.say("new prospect Tom Rodgers, 847-477-0619, 216 Shadow Creek Lane")
        self.assertIn("Do you want to add the email address?", r["say"].replace("an email", "the email"))
        self.c.say("yes")
        self.c.say("tom dot rodgers at gmail dot com")
        self.assertEqual(self.c.data["email1"], "tom.rodgers@gmail.com")

    def test_new_source_asks_who_it_is(self):
        self.c.say("new prospect Tom Rodgers, 847-477-0619, follow up next week")
        self.c.say("no")
        r = self.c.say("Sam Lee")
        self.assertIn("Sam Lee is new to me", r["say"])
        self.c.say("he's a realtor")
        self.assertEqual((self.c.data["source"], self.c.data["categoryId"]), ("Sam Lee", "cat.realtor"))

    def test_follow_up_default_and_choice(self):
        self.c.say("new prospect Tom Rodgers, 847-477-0619")
        self.c.say("no")
        self.c.say("Zillow")
        self.assertEqual(self.c.pending["type"], "default")
        self.assertIn("Monday", self.c.last["say"])
        self.c.say("in two weeks")
        self.assertEqual(self.c.data["followUp"], "2026-11-13")

    def test_correction_at_confirm(self):
        self.c.say("new prospect Tom Rodgers, 847-477-0619, 216 Shadow Creek Lane, from Zillow, follow up Monday")
        self.assertEqual(self.c.pending["type"], "confirm")
        self.c.say("actually make it Tuesday")
        self.assertEqual(self.c.data["followUp"], "2026-11-03")
        self.c.say("the phone is 940-555-0111")
        self.assertEqual(self.c.data["phone1"], "(940) 555-0111")
        self.assertEqual(self.c.pending["type"], "confirm")

    def test_cancel_saves_nothing(self):
        before = self.conn.execute("SELECT COUNT(*) FROM prospects").fetchone()[0]
        self.c.say("new prospect Tom Rodgers")
        r = self.c.say("cancel")
        self.assertIsNone(r["dialog"])
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM prospects").fetchone()[0], before)

    def test_finish_later_parks_it_in_review(self):
        self.c.say("new prospect Tom Rodgers, follow up next week")
        r = self.c.say("I'm driving")
        self.assertIn("Review queue", r["say"])
        self.assertIn("the address", r["say"])
        p = self.prospect()
        self.assertEqual(p["reviewed"], 0)
        self.assertIn("HERB: still need", p["notes"])
        item = next(i for i in herb.review_items(self.conn, NOW) if i["id"] == f"prospects:{p['id']}")
        self.assertTrue(item["question"].startswith("Finish Tom Rodgers"))

    def test_quick_mode_still_asks_the_source(self):  # D3: source is required in every mode
        self.set_mode("quick")
        self.c.say("new prospect Tom Rodgers")
        self.assertEqual(self.c.pending["slot"], "source")
        r = self.c.say("from Zillow")
        self.assertEqual(self.c.pending["type"], "confirm", r["say"])

    def test_unknown_source_goes_to_review(self):
        for answer in ("I don't know", "skip", "no", "Don't know", "nobody, he just called me"):
            with self.subTest(answer=answer):
                c = Convo(self.conn)
                c.say("new prospect Tom Rodgers, 847-477-0619")
                if c.pending.get("type") == "offer":  # after three "no"s HERB stops offering the address
                    c.say("no")
                self.assertEqual(c.pending["slot"], "source")
                r = c.say(answer)
                self.assertIn("mark the source unknown", r["say"])
                self.assertEqual(c.data["source"], "Unknown")
                self.assertFalse(c.data["reviewed"])
        c.say("yes")
        c.say("yes")
        p = db.one(self.conn.execute("SELECT p.*, s.name AS src FROM prospects p JOIN sources s ON s.id = p.source_id "
                                     "WHERE p.id = (SELECT MAX(id) FROM prospects)"))
        self.assertEqual((p["src"], p["reviewed"]), ("Unknown", 0))
        item = next(i for i in herb.review_items(self.conn, NOW) if i["id"] == f"prospects:{p['id']}")
        self.assertTrue(item["question"].startswith("Where did Tom"), item["question"])
        keys = [i["key"] for i in herb.insights(self.conn, NOW)]
        self.assertIn("source.unknown", keys)
        self.assertNotIn("source.Unknown", " ".join(keys))
        self.assertNotIn("Unknown", herb.ask(self.conn, "Which sources never close?", NOW)["say"])

    def test_known_source_can_replace_unknown(self):
        self.c.say("new prospect Tom Rodgers, 847-477-0619")
        self.c.say("no")
        self.c.say("I don't know")
        self.c.say("actually Ruth Alvarez sent him")
        self.assertEqual(self.c.data["source"], "Ruth Alvarez")
        self.assertNotEqual(self.c.data.get("reviewed"), False)

    def test_skipping_three_times_stops_the_offer(self):
        for _ in range(3):
            c = Convo(self.conn)
            c.say("new prospect Tom Rodgers, 847-477-0619")
            self.assertEqual(c.pending["slots"], ["address"])
            r = c.say("no")
        self.assertIn("stop asking", r["say"])
        c = Convo(self.conn)
        c.say("new prospect Ann Lee, 847-477-0620")
        self.assertNotEqual(c.pending.get("type"), "offer")
        self.assertIn("address", db.get_account(self.conn)["herbNeverAsk"])

    def test_duplicate_becomes_an_update(self):
        r = self.c.say("new prospect Kevin Morales")
        self.assertIn("Is this the same person?", r["say"])
        self.c.say("same person")
        self.c.say("940-555-0199")
        self.c.say("yes")
        self.assertEqual(self.prospect("Morales")["phone1"], "(940) 555-0199")
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM prospects WHERE last_name = 'Morales'").fetchone()[0], 1)

    def test_side_question_keeps_the_draft(self):
        self.c.say("new prospect Tom Rodgers, 847-477-0619")
        r = self.c.say("which sources never close?")
        self.assertIn("LeadBoost", r["say"])
        self.assertIn("Back to Tom Rodgers", r["say"])
        self.assertEqual(self.c.pending["slots"], ["address"])

    def test_new_entry_while_one_waits(self):
        self.c.say("new prospect Tom Rodgers, 847-477-0619")
        r = self.c.say("new prospect Mary Jones")
        self.assertIn("save Tom Rodgers", r["say"])
        r = self.c.say("yes")
        self.assertIsNotNone(self.prospect())
        self.assertIn("Mary Jones", r["say"])
        self.assertEqual(self.c.dialog["data"]["lastName"], "Jones")


class OtherLogs(DialogTest):
    def test_expense_missing_category_and_people(self):
        r = self.c.say("I spent 45 dollars")
        self.assertEqual(self.c.pending["slot"], "category")
        self.c.say("lunch")
        self.assertIn("Who was the lunch with?", self.c.last["say"])
        self.c.say("Dana Ruiz")
        self.assertIn("Which restaurant?", self.c.last["say"])
        r = self.c.say("Cedar Grill")
        self.assertEqual(self.c.pending["type"], "confirm", r["say"])
        self.assertEqual((self.c.data["vendor"], self.c.data["categoryId"]), ("Cedar Grill", "exp.relationships.meal"))

    def test_solo_meal_warns(self):
        self.c.say("lunch, 18 dollars at Chipotle")
        r = self.c.say("just me")
        self.assertIn("aren't deductible", r["say"])

    def test_activity_leads_chain_into_prospects(self):
        self.c.say("I spent two hours door knocking and got two leads")
        r = self.c.say("yes")
        self.assertIn("want to add them now", r["say"])
        self.assertEqual(self.c.say("yes")["say"], "Lead 1 of 2 — what's the name?")
        self.c.say("Maria Lopez 940-555-0101")
        self.assertEqual(self.c.data["categoryId"], "cat.door_knocking")
        self.c.say("no")
        self.c.say("yes")
        r = self.c.say("yes")
        self.assertIn("Lead 2 of 2", r["say"])
        r = self.c.say("that's all")
        self.assertIsNone(r["dialog"])
        self.assertIsNotNone(self.prospect("Lopez"))

    def test_update_existing_contact(self):
        r = self.c.say("I called Priya Shah, she's not ready yet, follow up in two weeks")
        self.assertEqual(r["intent"], "update_prospect")
        self.c.say("yes")
        p = self.prospect("Shah")
        self.assertEqual(p["follow_up"], "2026-11-13")
        self.assertIn("Called — she's not ready yet", p["notes"])

    def test_update_contact_details(self):
        for text in ("Kevin Morales's email is kevin@example.com", "Kevin Morales email is kevin@example.com",
                     "new phone for Kevin Morales 940-555-0123"):
            with self.subTest(text=text):
                r = Convo(self.conn).say(text)
                self.assertEqual(r["intent"], "update_prospect")
                self.assertEqual(r["pending"]["type"], "confirm")

    def test_update_asks_for_next_follow_up(self):
        r = self.c.say("I called Priya Shah, left a voicemail")
        self.assertIn("When should you follow up with Priya next", r["say"])

    def test_income_asks_type_and_payer(self):
        self.c.say("got paid 3,000")
        self.assertEqual(self.c.pending["slot"], "type")
        self.c.say("referral fee")
        self.assertEqual(self.c.pending["slot"], "payer")
        self.c.say("Lakeside Realty")
        self.assertEqual((self.c.data["type"], self.c.data["payer"]), ("referral_fees", "Lakeside Realty"))

    def test_trip_asks_destination(self):
        self.c.say("drove 12 miles")
        r = self.c.say("to the title company")
        self.assertEqual(self.c.data["reason"], "Title Company")
        self.assertIn("worth $9.12", r["say"])

    def test_closing_estimates_income(self):
        self.c.say("the Morales loan closed")
        self.assertEqual(self.c.pending["slot"], "size")
        r = self.c.say("520 thousand")
        self.assertEqual(self.c.pending["type"], "default")
        self.assertIn("about $", r["say"])
        self.c.say("yes")
        self.assertGreater(self.c.data["income"], 5000)

    def test_required_fields_cannot_be_skipped(self):
        self.c.say("I spent 45 dollars")
        r = self.c.say("skip")
        self.assertEqual(self.c.pending["slot"], "category")
        self.assertIn("I need that one", r["say"])


if __name__ == "__main__":
    unittest.main()
