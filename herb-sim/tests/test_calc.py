import os
import sys
import unittest
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import calc  # noqa: E402
import db  # noqa: E402
import server  # noqa: E402

NOW = date(2026, 4, 15)


def fixture():
    """Tiny hand-checkable ledger for March 2026."""
    conn = db.connect(":memory:")
    conn.execute("INSERT INTO plans VALUES(2026, 150000, 125000, 6500, 335000, 40, 0)")
    s = db.source_id_for(conn, "Greg Wallace")
    ins = server.insert
    p1 = ins(conn, "prospects", dict(date="2026-03-02", first_names="A", last_name="One", pillar="clients",
                                     sub_pillar="clients", category_id="cat.past_client", source_id=s,
                                     activity_id="act.past_client_interaction", strength="hot"))
    ins(conn, "prospects", dict(date="2026-03-05", first_names="B", last_name="Two", pillar="clients",
                                sub_pillar="clients", category_id="cat.past_client", source_id=s,
                                activity_id="act.past_client_interaction", strength="medium"))
    for i in range(2):
        ins(conn, "prospects", dict(date="2026-03-10", first_names="C", last_name=f"Door{i}", pillar="prospecting",
                                    sub_pillar="prospecting", category_id="cat.door_knocking",
                                    activity_id="act.door_knocking", strength="cold"))
    c = ins(conn, "closings", dict(date="2026-03-20", prospect_id=p1, pillar="clients", sub_pillar="clients",
                                   category_id="cat.past_client", source_id=s, activity_id="act.past_client_interaction",
                                   transaction_size=400000, income=5000))
    ins(conn, "income", dict(date="2026-03-20", mode="transaction", closing_id=c, pillar="clients",
                             sub_pillar="clients", category_id="cat.past_client", amount=5000))
    ins(conn, "income", dict(date="2026-03-25", mode="type", type="consulting_fees", amount=1000))
    ins(conn, "expenses", dict(date="2026-03-03", vendor="Gift", amount=100, group_id="clients",
                               category_id="exp.clients.thank_you_gifts"))
    ins(conn, "expenses", dict(date="2026-03-04", vendor="Phone", amount=50, group_id="general",
                               category_id="exp.general.phone"))
    ins(conn, "trips", dict(date="2026-03-06", reason="x", destination="y", odometer_start=1000, odometer_end=1010,
                            is_business=1))
    ins(conn, "trips", dict(date="2026-03-07", reason="x", destination="y", gps_miles=99, is_business=0))
    ins(conn, "activities", dict(date="2026-03-02", pillar="clients", sub_pillar="clients",
                                 activity_id="act.past_client_interaction", minutes=120))
    ins(conn, "activities", dict(date="2026-03-10", pillar="prospecting", sub_pillar="prospecting",
                                 activity_id="act.door_knocking", minutes=60))
    conn.commit()
    return conn


class PlanTests(unittest.TestCase):
    def test_2018_business_plan_example(self):
        o = calc.plan_outputs({"grossIncomeGoal": 150000, "netProfitGoal": 125000, "avgCommission": 6500,
                               "avgTransactionSize": 335000, "hoursPerWeek": 40, "vacationWeeks": 0})
        self.assertAlmostEqual(o["annualTransactions"], 23.08, places=2)
        self.assertAlmostEqual(o["monthlyTransactions"], 1.92, places=2)
        self.assertAlmostEqual(o["hourlyGross"], 72.12, places=2)
        self.assertAlmostEqual(o["hourlyNet"], 60.10, places=2)
        self.assertAlmostEqual(o["annualVolume"], 7730769.23, places=1)
        self.assertAlmostEqual(o["yieldPct"], 0.0194, places=4)
        self.assertEqual(o["annualWorkHours"], 2080)
        self.assertAlmostEqual(o["annualExpenses"], 25000)

    def test_vacation_reduces_work_hours(self):
        o = calc.plan_outputs({"grossIncomeGoal": 180000, "netProfitGoal": 150000, "avgCommission": 5500,
                               "avgTransactionSize": 380000, "hoursPerWeek": 45, "vacationWeeks": 3})
        self.assertEqual(o["annualWorkHours"], 49 * 45)

    def test_net_cannot_exceed_gross(self):
        conn = db.connect(":memory:")
        self.addCleanup(conn.close)
        with self.assertRaises(ValueError):
            calc.save_plan(conn, 2026, {"grossIncomeGoal": 100, "netProfitGoal": 200})


class IndexTests(unittest.TestCase):
    def test_2018_sample(self):
        self.assertAlmostEqual(calc.logsperity_index(2.386, 0.8193, 0.40), 120.5, delta=0.05)

    def test_healthy_is_100(self):
        self.assertAlmostEqual(calc.logsperity_index(2.0, 0.75, 0.30), 100.0)

    def test_missing_input(self):
        self.assertIsNone(calc.logsperity_index(None, 0.5, 0.3))


class PeriodTests(unittest.TestCase):
    def test_quarter(self):
        p = calc.parse_period("q:2026-3", NOW)
        self.assertEqual((p.frm, p.to), (date(2026, 7, 1), date(2026, 9, 30)))

    def test_ytd_and_month(self):
        self.assertEqual(calc.parse_period("ytd", NOW).frm, date(2026, 1, 1))
        p = calc.parse_period("month:2026-02", NOW)
        self.assertEqual(p.to, date(2026, 2, 28))

    def test_bad_period(self):
        with self.assertRaises(ValueError):
            calc.parse_period("fortnight", NOW)


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.conn = fixture()
        self.addCleanup(self.conn.close)
        self.led = calc.Ledger(self.conn, calc.parse_period("month:2026-03", NOW), NOW)

    def test_counts_and_conversion(self):
        self.assertEqual(self.led.n_prospects, 4)
        self.assertEqual(self.led.n_closings, 1)
        self.assertAlmostEqual(self.led.conversion, 0.25)
        self.assertEqual(self.led.volume, 400000)

    def test_income_and_expenses(self):
        self.assertEqual(self.led.income_total, 6000)
        self.assertEqual(self.led.nontrans_income, 1000)
        self.assertAlmostEqual(self.led.mileage_deduction, 10 * 0.725)  # personal trip excluded
        self.assertAlmostEqual(self.led.expenses_total, 150 + 7.25)
        self.assertAlmostEqual(self.led.profit, 6000 - 157.25)

    def test_efficiency(self):
        self.assertAlmostEqual(self.led.bb_hours, 3.0)
        self.assertAlmostEqual(self.led.hours_per_prospect, 0.75)
        self.assertAlmostEqual(self.led.hours_per_closing, 3.0)
        self.assertAlmostEqual(self.led.work_hours, 2080 * 31 / 365)
        self.assertAlmostEqual(self.led.hourly_gross, 6000 / (2080 * 31 / 365))

    def test_pillar_breakdown_and_roi(self):
        pil = {r["key"]: r for r in self.led.breakdown("pillar")}
        self.assertAlmostEqual(pil["clients"]["conversion"], 0.5)
        self.assertEqual(pil["prospecting"]["closings"], 0)
        self.assertEqual(pil["clients"]["expenses"], 100)
        roi = {r["key"]: r for r in self.led.pillar_roi()}
        self.assertAlmostEqual(roi["clients"]["roi"], (5000 - 100) / 100)
        wages = 2 * self.led.hourly_gross
        self.assertAlmostEqual(roi["clients"]["roiWithTime"], (5000 - 100 - wages) / (100 + wages))
        # overhead holds the phone bill, mileage and unattributed consulting income
        self.assertAlmostEqual(roi["overhead"]["expenses"], 50 + 7.25)
        self.assertAlmostEqual(roi["overhead"]["income"], 1000)
        self.assertAlmostEqual(roi["total"]["roiWithTime"], self.led.net_roi)

    def test_net_roi_and_index(self):
        capital = self.led.expenses_total + self.led.bb_hours * self.led.hourly_gross
        self.assertAlmostEqual(self.led.net_roi, (6000 - capital) / capital)
        self.assertAlmostEqual(self.led.index, calc.logsperity_index(self.led.net_roi, self.led.margin, 0.25))

    def test_split_mileage_rate(self):
        self.assertEqual(calc.tx.mileage_rate("2026-06-30"), 0.725)
        self.assertEqual(calc.tx.mileage_rate("2026-07-01"), 0.76)

    def test_scorecard(self):
        sc = calc.scorecard(self.conn, "prospects", "quantity", "category", "month:2026-03")
        totals = {r["key"]: r["total"] for r in sc["rows"]}
        self.assertEqual(totals["cat.door_knocking"], 2)
        self.assertEqual(sc["subPillarTotals"]["clients"], 2)

    def test_months_in_use(self):
        led = calc.Ledger(self.conn, calc.parse_period("ytd", NOW), NOW)
        self.assertEqual(led.months_in_use, 2)  # March and April (data starts in March)


class RuleTests(unittest.TestCase):
    def test_r5_one_closing_per_prospect(self):
        conn = fixture()
        self.addCleanup(conn.close)
        pid = conn.execute("SELECT id FROM prospects WHERE last_name = 'Two'").fetchone()[0]
        server.save_log(conn, "closings", {"prospectId": pid, "transactionSize": 300000, "income": 4000})
        with self.assertRaises(server.ApiError) as cm:
            server.save_log(conn, "closings", {"prospectId": pid, "transactionSize": 300000, "income": 4000})
        self.assertEqual(cm.exception.status, 409)

    def test_r3_additional_transactions_are_income(self):
        conn = fixture()
        self.addCleanup(conn.close)
        pid = conn.execute("SELECT id FROM prospects WHERE last_name = 'Door0'").fetchone()[0]
        before = conn.execute("SELECT COUNT(*) FROM income").fetchone()[0]
        server.save_log(conn, "closings", {"prospectId": pid, "transactionSize": 300000, "income": 4000,
                                           "additionalTransactions": [{"transactionSize": 200000, "income": 2500}]})
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM closings").fetchone()[0], 2)
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM income").fetchone()[0], before + 2)

    def test_r6_odometer_defaults_to_previous_end(self):
        conn = fixture()
        self.addCleanup(conn.close)
        row = server.save_log(conn, "trips", {"date": "2026-03-08", "reason": "x", "destination": "z",
                                              "odometerEnd": 1030})
        self.assertEqual(row["odometer_start"], 1010)
        self.assertEqual(row["miles"], 20)

    def test_activity_rounds_to_15_minutes(self):
        conn = fixture()
        self.addCleanup(conn.close)
        row = server.save_log(conn, "activities", {"activityId": "act.open_houses", "minutes": 50})
        self.assertEqual(row["minutes"], 45)
        self.assertEqual(row["pillar"], "prospecting")


if __name__ == "__main__":
    unittest.main()
