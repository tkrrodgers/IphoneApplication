"""SQLite storage for the simulator (plays the role SwiftData plays on the phone)."""
import json
import os
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PATH = os.path.join(HERE, "data", "logsperity.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS sources(id INTEGER PRIMARY KEY, name TEXT NOT NULL, normalized TEXT UNIQUE,
    kind TEXT DEFAULT 'person');
CREATE TABLE IF NOT EXISTS prospects(id INTEGER PRIMARY KEY, date TEXT, last_name TEXT, first_names TEXT,
    phone1 TEXT, phone1_type TEXT, phone2 TEXT, phone2_type TEXT, email1 TEXT, email2 TEXT,
    address TEXT, zip TEXT, city TEXT, state TEXT,
    pillar TEXT, sub_pillar TEXT, category_id TEXT, source_id INTEGER, activity_id TEXT,
    originally_from_source_id INTEGER, strength TEXT DEFAULT 'medium', plan_of_action TEXT, follow_up TEXT,
    notes TEXT, capture TEXT DEFAULT 'manual', reviewed INTEGER DEFAULT 1, created_at TEXT);
CREATE TABLE IF NOT EXISTS closings(id INTEGER PRIMARY KEY, date TEXT, prospect_id INTEGER UNIQUE,
    pillar TEXT, sub_pillar TEXT, category_id TEXT, source_id INTEGER, activity_id TEXT,
    transaction_size REAL DEFAULT 0, income REAL DEFAULT 0, referral_request TEXT DEFAULT 'no',
    post_closing_follow_up TEXT, notes TEXT, capture TEXT DEFAULT 'manual', reviewed INTEGER DEFAULT 1);
CREATE TABLE IF NOT EXISTS income(id INTEGER PRIMARY KEY, date TEXT, mode TEXT DEFAULT 'type',
    closing_id INTEGER, pillar TEXT, sub_pillar TEXT, category_id TEXT, source_id INTEGER, activity_id TEXT,
    type TEXT, transaction_count INTEGER, transaction_size REAL, last_name TEXT, amount REAL DEFAULT 0,
    payer TEXT, expect_1099 INTEGER DEFAULT 1, notes TEXT, capture TEXT DEFAULT 'manual',
    reviewed INTEGER DEFAULT 1);
CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY, date TEXT, vendor TEXT, amount REAL DEFAULT 0,
    group_id TEXT, relationship_sub_pillar TEXT, category_id TEXT, source_id INTEGER, check_number TEXT,
    card_last4 TEXT, purpose TEXT, with_whom TEXT, has_receipt INTEGER DEFAULT 0, notes TEXT,
    capture TEXT DEFAULT 'manual', reviewed INTEGER DEFAULT 1);
CREATE TABLE IF NOT EXISTS trips(id INTEGER PRIMARY KEY, date TEXT, reason TEXT, destination TEXT,
    odometer_start REAL, odometer_end REAL, gps_miles REAL, is_business INTEGER DEFAULT 1, activity_id TEXT,
    source_id INTEGER, notes TEXT, capture TEXT DEFAULT 'manual', reviewed INTEGER DEFAULT 1);
CREATE TABLE IF NOT EXISTS activities(id INTEGER PRIMARY KEY, date TEXT, pillar TEXT, sub_pillar TEXT,
    activity_id TEXT, minutes INTEGER DEFAULT 0, source_id INTEGER, notes TEXT, capture TEXT DEFAULT 'manual',
    reviewed INTEGER DEFAULT 1);
CREATE TABLE IF NOT EXISTS account(id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT);
CREATE TABLE IF NOT EXISTS plans(year INTEGER PRIMARY KEY, gross_income_goal REAL, net_profit_goal REAL,
    avg_commission REAL, avg_transaction_size REAL, hours_per_week REAL, vacation_weeks REAL);
CREATE TABLE IF NOT EXISTS autopilot(key TEXT PRIMARY KEY, level INTEGER);
CREATE TABLE IF NOT EXISTS checkins(id INTEGER PRIMARY KEY, date TEXT, json TEXT);
CREATE TABLE IF NOT EXISTS commitments(id INTEGER PRIMARY KEY, checkin_id INTEGER, text TEXT,
    activity_id TEXT, target INTEGER, due TEXT);
CREATE TABLE IF NOT EXISTS insight_dismissals(rule_key TEXT PRIMARY KEY, date TEXT);
CREATE INDEX IF NOT EXISTS ix_prospects_date ON prospects(date);
CREATE INDEX IF NOT EXISTS ix_closings_date ON closings(date);
CREATE INDEX IF NOT EXISTS ix_income_date ON income(date);
CREATE INDEX IF NOT EXISTS ix_expenses_date ON expenses(date);
CREATE INDEX IF NOT EXISTS ix_trips_date ON trips(date);
CREATE INDEX IF NOT EXISTS ix_activities_date ON activities(date);
"""

LOG_TABLES = ("prospects", "closings", "income", "expenses", "trips", "activities")


def db_path():
    return os.environ.get("HERB_DB", DEFAULT_PATH)


def connect(path=None):
    path = path or db_path()
    if path != ":memory:":
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    conn = sqlite3.connect(path, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = OFF")
    conn.executescript(SCHEMA)
    return conn


def columns(conn, table):
    return [r[1] for r in conn.execute(f"PRAGMA table_info({table})")]


def rows(cur):
    return [dict(r) for r in cur]


def one(cur):
    r = cur.fetchone()
    return dict(r) if r else None


def get_account(conn):
    r = conn.execute("SELECT json FROM account WHERE id = 1").fetchone()
    return json.loads(r["json"]) if r else {}


def set_account(conn, data):
    conn.execute("INSERT OR REPLACE INTO account(id, json) VALUES(1, ?)", (json.dumps(data),))
    conn.commit()


def normalize_source(name):
    return " ".join("".join(ch for ch in name.lower() if ch.isalnum() or ch.isspace()).split())


def source_id_for(conn, name, kind="person"):
    """Find or create a source by name (sources are remembered for autocomplete)."""
    name = (name or "").strip()
    if not name:
        return None
    norm = normalize_source(name)
    r = conn.execute("SELECT id FROM sources WHERE normalized = ?", (norm,)).fetchone()
    if r:
        return r["id"]
    cur = conn.execute("INSERT INTO sources(name, normalized, kind) VALUES(?,?,?)", (name, norm, kind))
    return cur.lastrowid
