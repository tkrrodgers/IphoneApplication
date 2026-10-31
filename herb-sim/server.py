"""HERB simulator server: static UI + JSON API (see CONTRACT.md). Python stdlib only.

    python server.py            # http://localhost:8765
    set PORT=9000 & python server.py
"""
import json
import mimetypes
import os
import re
import sys
import traceback
from datetime import date, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

import calc
import db
import herb
import reports
import seed
import taxonomy as tx

HERE = os.path.dirname(os.path.abspath(__file__))
STATIC = os.path.join(HERE, "static")
LOGS = db.LOG_TABLES
CARD_KEYS = re.compile(r"card|cvv|cvc|security.?code|expir|credit", re.I)


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


# ---------------------------------------------------------------- body helpers

ALIASES = {"expect1099": "expect_1099", "expect_1099": "expect_1099"}


def snake(k):
    if k in ALIASES:
        return ALIASES[k]
    return re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", k).lower()


def normalize(d):
    return {snake(k): v for k, v in (d or {}).items()}


def to_bool_int(v):
    if isinstance(v, str):
        return 1 if v.lower() in ("1", "true", "yes", "on") else 0
    return 1 if v else 0


def as_float(v):
    if v in (None, ""):
        return None
    if isinstance(v, str):
        v = v.replace("$", "").replace(",", "").strip()
    return float(v)


# ---------------------------------------------------------------- log writer (shared by API and HERB confirm)

def prepare(conn, log, data, existing=None):
    d = normalize(data)
    cols = set(db.columns(conn, log))
    if "source" in d and "source_id" not in d:
        name = d.pop("source")
        if name:
            d["source_id"] = db.source_id_for(conn, name, "person")
    if "originally_from" in d:
        name = d.pop("originally_from")
        if name:
            d["originally_from_source_id"] = db.source_id_for(conn, name, "person")
    if log in ("prospects", "closings", "income") and d.get("category_id"):
        cat = tx.CATEGORY_BY_ID.get(d["category_id"])
        if not cat:
            raise ApiError(400, f"Unknown category '{d['category_id']}'")
        d.setdefault("sub_pillar", cat["subPillar"])
        d.setdefault("pillar", cat["pillar"])
    if log == "activities" and d.get("activity_id"):
        act = tx.ACTIVITY_BY_ID.get(d["activity_id"])
        if not act:
            raise ApiError(400, f"Unknown activity '{d['activity_id']}'")
        d.setdefault("pillar", act["pillar"])
        d.setdefault("sub_pillar", act["subPillar"])
    if d.get("activity_id") and d["activity_id"] not in tx.ACTIVITY_BY_ID:
        raise ApiError(400, f"Unknown activity '{d['activity_id']}'")
    if log == "expenses" and d.get("category_id"):
        meta = tx.EXPENSE_CATEGORY_BY_ID.get(d["category_id"])
        if not meta:
            raise ApiError(400, f"Unknown expense category '{d['category_id']}'")
        d["group_id"] = meta["group"]
    if log == "activities" and "minutes" in d and d["minutes"] not in (None, ""):
        m = int(round(float(d["minutes"]) / 15) * 15)
        if m <= 0:
            raise ApiError(400, "Time must be at least 15 minutes")
        d["minutes"] = m
    for k in ("amount", "transaction_size", "income", "odometer_start", "odometer_end", "gps_miles"):
        if k in d:
            d[k] = as_float(d[k])
    for k in ("is_business", "has_receipt", "expect_1099", "reviewed"):
        if k in d and d[k] is not None:
            d[k] = to_bool_int(d[k])
    if log == "trips" and existing is None and d.get("odometer_end") is not None and d.get("odometer_start") is None:
        prev = conn.execute("SELECT odometer_end FROM trips WHERE odometer_end IS NOT NULL "
                            "ORDER BY date DESC, id DESC LIMIT 1").fetchone()
        if prev:
            d["odometer_start"] = prev[0]  # rule R6
    if existing is None:
        d.setdefault("date", calc.today().isoformat())
        d.setdefault("capture", "manual")
        d.setdefault("reviewed", 1)
        if log == "prospects":
            d.setdefault("created_at", calc.today().isoformat())
            if not (d.get("last_name") or d.get("first_names")):
                raise ApiError(400, "A prospect needs a name")
        if log == "trips":
            d.setdefault("is_business", 1)
    return {k: v for k, v in d.items() if k in cols and k != "id"}


def insert(conn, table, row):
    keys = list(row)
    cur = conn.execute(f"INSERT INTO {table}({', '.join(keys)}) VALUES({', '.join('?' for _ in keys)})",
                       [row[k] for k in keys])
    return cur.lastrowid


def get_row(conn, log, rid):
    r = db.one(conn.execute(f"SELECT * FROM {log} WHERE id = ?", (rid,)))
    return reports.decorate(conn, log, [r])[0] if r else None


def save_log(conn, log, data):
    """Create one log entry (or a closing with its income rows). Returns the decorated row."""
    if log not in LOGS:
        raise ApiError(404, f"Unknown log '{log}'")
    data = dict(data)
    if log == "closings":
        return save_closing(conn, data)
    row = prepare(conn, log, data)
    rid = insert(conn, log, row)
    conn.commit()
    return get_row(conn, log, rid)


def save_closing(conn, data):
    d = normalize(data)
    add_income = d.pop("add_to_income", True)
    extra = d.pop("additional_transactions", None) or []
    pid = d.get("prospect_id")
    if pid:
        p = db.one(conn.execute("SELECT * FROM prospects WHERE id = ?", (pid,)))
        if not p:
            raise ApiError(404, "Prospect not found")
    else:
        if not (d.get("last_name") or d.get("first_names")):
            raise ApiError(400, "Choose a prospect or enter the client's name")
        pdata = {k: d.get(k) for k in ("first_names", "last_name", "phone1", "phone1_type", "email1", "pillar",
                                       "sub_pillar", "category_id", "activity_id", "source", "source_id")
                 if d.get(k) is not None}
        pdata.update(date=d.get("date") or calc.today().isoformat(), strength="hot", capture=d.get("capture", "manual"))
        if not pdata.get("category_id"):
            pdata.update(category_id="cat.prospective_client", activity_id="act.prospective_client_interaction")
        prow = prepare(conn, "prospects", pdata)
        pid = insert(conn, "prospects", prow)
        p = db.one(conn.execute("SELECT * FROM prospects WHERE id = ?", (pid,)))
    if conn.execute("SELECT 1 FROM closings WHERE prospect_id = ?", (pid,)).fetchone():
        raise ApiError(409, "This prospect already has a closing (rule R5: one closing per prospect). "
                            "Log repeat transactions as income.")
    for k in ("pillar", "sub_pillar", "category_id", "source_id", "activity_id"):
        if d.get(k) is None:
            d[k] = p[k]
    d["prospect_id"] = pid
    for k in ("first_names", "last_name", "phone1", "phone1_type", "email1", "source"):
        d.pop(k, None)
    row = prepare(conn, "closings", d)
    row.setdefault("referral_request", "no")
    cid = insert(conn, "closings", row)
    if to_bool_int(add_income):
        insert(conn, "income", {"date": row["date"], "mode": "transaction", "closing_id": cid, "pillar": row["pillar"],
                                "sub_pillar": row["sub_pillar"], "category_id": row["category_id"],
                                "source_id": row["source_id"], "activity_id": row["activity_id"], "type": "commission",
                                "transaction_count": 1, "transaction_size": row.get("transaction_size"),
                                "last_name": p["last_name"], "amount": row.get("income") or 0, "expect_1099": 1,
                                "capture": row.get("capture", "manual"), "reviewed": 1})
    for t in extra:  # rule R3: additional transactions go to the income log, not extra closings
        t = normalize(t)
        insert(conn, "income", {"date": row["date"], "mode": "transaction", "closing_id": cid, "pillar": row["pillar"],
                                "sub_pillar": row["sub_pillar"], "category_id": row["category_id"],
                                "source_id": row["source_id"], "activity_id": row["activity_id"], "type": "commission",
                                "transaction_count": 1, "transaction_size": as_float(t.get("transaction_size")),
                                "last_name": p["last_name"], "amount": as_float(t.get("income")) or 0, "expect_1099": 1,
                                "notes": "Additional transaction (rule R3)", "capture": "manual", "reviewed": 1})
    conn.execute("UPDATE prospects SET reviewed = 1 WHERE id = ?", (pid,))
    conn.commit()
    return get_row(conn, "closings", cid)


def update_log(conn, log, rid, data):
    if not conn.execute(f"SELECT 1 FROM {log} WHERE id = ?", (rid,)).fetchone():
        raise ApiError(404, "Not found")
    row = prepare(conn, log, data, existing=True)
    if log == "closings" and "prospect_id" in row:
        other = conn.execute("SELECT id FROM closings WHERE prospect_id = ? AND id != ?", (row["prospect_id"], rid)).fetchone()
        if other:
            raise ApiError(409, "That prospect already has a closing (rule R5)")
    if row:
        conn.execute(f"UPDATE {log} SET {', '.join(k + ' = ?' for k in row)} WHERE id = ?", [*row.values(), rid])
        if log == "closings":  # keep the linked income row in step
            if "income" in row:
                conn.execute("UPDATE income SET amount = ? WHERE closing_id = ? AND notes IS NULL", (row["income"], rid))
            if "transaction_size" in row:
                conn.execute("UPDATE income SET transaction_size = ? WHERE closing_id = ? AND notes IS NULL",
                             (row["transaction_size"], rid))
        conn.commit()
    return get_row(conn, log, rid)


def delete_log(conn, log, rid):
    if log == "closings":
        conn.execute("DELETE FROM income WHERE closing_id = ?", (rid,))
    if log == "prospects":
        c = conn.execute("SELECT id FROM closings WHERE prospect_id = ?", (rid,)).fetchone()
        if c:
            raise ApiError(409, "Delete the closing for this prospect first")
    cur = conn.execute(f"DELETE FROM {log} WHERE id = ?", (rid,))
    conn.commit()
    if not cur.rowcount:
        raise ApiError(404, "Not found")


def list_log(conn, log, q):
    period = calc.parse_period(q.get("period", "ytd"))
    sql = f"SELECT * FROM {log} WHERE date BETWEEN ? AND ?"
    args = [period.frm.isoformat(), period.to.isoformat()]
    if q.get("pillar") and log != "expenses" and log != "trips":
        sql += " AND pillar = ?"
        args.append(q["pillar"])
    if q.get("pillar") and log == "expenses":
        groups = [g for g, _, p in tx.EXPENSE_GROUPS if p == q["pillar"]]
        sql += f" AND group_id IN ({', '.join('?' for _ in groups) or 'NULL'})"
        args.extend(groups)
    if q.get("reviewed") in ("0", "1"):
        sql += " AND reviewed = ?"
        args.append(int(q["reviewed"]))
    sql += " ORDER BY date DESC, id DESC"
    rows = reports.decorate(conn, log, db.rows(conn.execute(sql, args)))
    if q.get("q"):
        needle = q["q"].lower()
        rows = [r for r in rows if needle in json.dumps(r, default=str).lower()]
    totals = reports.log_totals(log, rows)
    if q.get("limit"):
        rows = rows[:int(q["limit"])]
    return {"period": period.json(), "rows": rows, "totals": totals}


# ---------------------------------------------------------------- other endpoints

def account_get(conn):
    a = db.get_account(conn)
    return {k: v for k, v in a.items() if not CARD_KEYS.search(k)}


def account_put(conn, body):
    a = db.get_account(conn)
    for k, v in body.items():
        if CARD_KEYS.search(k):
            continue  # payment is Apple In-App Purchase; card data is never stored
        if k == "plan" and v in ("monthly", "annual"):
            a["plan"] = v
            a.setdefault("subscription", {})
            a["subscription"].update({"status": "active", "via": "Apple In-App Purchase (simulated)",
                                      "price": "$50/month" if v == "monthly" else "$500/year"})
        elif k != "subscription":
            a[k] = v
    if a.get("zip") and not body.get("city"):
        if str(a["zip"]).startswith("762"):
            a.setdefault("city", "Denton")
            a.setdefault("state", "TX")
    db.set_account(conn, a)
    return account_get(conn)


def autopilot_get(conn):
    levels = {r["key"]: r["level"] for r in conn.execute("SELECT key, level FROM autopilot")}
    return [{"key": k, "label": v[3], "level": levels.get(k, v[0]), "min": v[1], "max": v[2], "description": v[4]}
            for k, v in seed.AUTOPILOT_DEFAULTS.items()]


def autopilot_put(conn, body):
    key, level = body.get("key"), body.get("level")
    meta = seed.AUTOPILOT_DEFAULTS.get(key)
    if not meta:
        raise ApiError(404, f"Unknown autopilot setting '{key}'")
    level = int(level)
    if not meta[1] <= level <= meta[2]:
        raise ApiError(400, f"Level for {meta[3]} must be between {meta[1]} and {meta[2]}")
    conn.execute("INSERT OR REPLACE INTO autopilot VALUES(?, ?)", (key, level))
    conn.commit()
    return autopilot_get(conn)


def review_post(conn, item_id, body):
    log, _, rid = item_id.partition(":")
    if log not in LOGS or not rid.isdigit():
        raise ApiError(404, "Unknown review item")
    rid = int(rid)
    action = body.get("action", "confirm")
    if action == "dismiss":
        delete_log(conn, log, rid)
    else:
        patch = dict(body.get("patch") or {})
        patch["reviewed"] = 1
        update_log(conn, log, rid, patch)
    return {"ok": True, "remaining": len(herb.review_items(conn))}


def sources_get(conn, q):
    sql = ("SELECT s.id, s.name, s.kind, (SELECT COUNT(*) FROM prospects p WHERE p.source_id = s.id) AS prospects, "
           "(SELECT COUNT(*) FROM closings c WHERE c.source_id = s.id) AS closings FROM sources s")
    args = []
    if q.get("q"):
        sql += " WHERE s.normalized LIKE ?"
        args.append(f"%{db.normalize_source(q['q'])}%")
    sql += " ORDER BY prospects DESC, s.name LIMIT 50"
    return db.rows(conn.execute(sql, args))


# ---------------------------------------------------------------- HTTP

class Handler(BaseHTTPRequestHandler):
    server_version = "HerbSim/1.0"

    def log_message(self, fmt, *args):
        if os.environ.get("HERB_QUIET"):
            return
        sys.stderr.write("%s %s\n" % (self.command, self.path))

    def _send(self, status, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else json.dumps(body, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except json.JSONDecodeError:
            raise ApiError(400, "Body must be JSON")

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def do_PUT(self):
        self._dispatch("PUT")

    def do_DELETE(self):
        self._dispatch("DELETE")

    def _dispatch(self, method):
        url = urlparse(self.path)
        if not url.path.startswith("/api/"):
            if method != "GET":
                return self._send(405, {"error": "Method not allowed"})
            return self._static(url.path)
        q = {k: v[-1] for k, v in parse_qs(url.query).items()}
        conn = db.connect()
        try:
            body = self._body() if method in ("POST", "PUT") else {}
            result = route(conn, method, unquote(url.path[5:]).strip("/"), q, body)
            self._send(201 if method == "POST" and isinstance(result, dict) and result.get("created") else 200, result)
        except ApiError as e:
            self._send(e.status, {"error": e.message})
        except (ValueError, KeyError) as e:
            self._send(400, {"error": str(e)})
        except Exception as e:  # pragma: no cover
            traceback.print_exc()
            self._send(500, {"error": f"Server error: {e}"})
        finally:
            conn.close()

    def _static(self, path):
        rel = unquote(path).lstrip("/") or "index.html"
        full = os.path.normpath(os.path.join(STATIC, rel))
        if not full.startswith(os.path.normpath(STATIC)):
            return self._send(403, {"error": "Forbidden"})
        if not os.path.isfile(full):
            full = os.path.join(STATIC, "index.html")
            if not os.path.isfile(full):
                return self._send(200, b"<!doctype html><title>HERB</title><p>UI not built yet. API is at /api/.</p>",
                                  "text/html; charset=utf-8")
        ctype = mimetypes.guess_type(full)[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype in ("application/javascript", "application/json"):
            ctype += "; charset=utf-8"
        with open(full, "rb") as f:
            self._send(200, f.read(), ctype)


def route(conn, method, path, q, body):
    parts = path.split("/")
    head = parts[0]
    if head == "taxonomy" and method == "GET":
        return tx.as_json()
    if head == "account":
        return account_get(conn) if method == "GET" else account_put(conn, body)
    if head == "plan":
        year = int(q.get("year") or calc.today().year)
        if method == "PUT":
            calc.save_plan(conn, year, body.get("inputs", body))
        return calc.plan_json(conn, year)
    if head == "sources" and method == "GET":
        return sources_get(conn, q)
    if head in LOGS:
        if len(parts) == 1:
            if method == "GET":
                return list_log(conn, head, q)
            if method == "POST":
                if isinstance(body, list):
                    return {"ok": True, "created": True, "rows": [save_log(conn, head, b) for b in body]}
                return {"ok": True, "created": True, "row": save_log(conn, head, body)}
        elif len(parts) == 2 and parts[1].isdigit():
            rid = int(parts[1])
            if method == "GET":
                r = get_row(conn, head, rid)
                if not r:
                    raise ApiError(404, "Not found")
                return r
            if method == "PUT":
                return {"ok": True, "row": update_log(conn, head, rid, body)}
            if method == "DELETE":
                delete_log(conn, head, rid)
                return {"ok": True}
    if head == "today" and method == "GET":
        return herb.today_view(conn)
    if head == "review":
        if method == "GET" and len(parts) == 1:
            return herb.review_items(conn)
        if method == "POST" and len(parts) == 2:
            return review_post(conn, parts[1], body)
    if head == "reports" and method == "GET":
        if len(parts) == 1:
            return reports.MENU
        try:
            return reports.build(conn, parts[1], q.get("period"))
        except KeyError:
            raise ApiError(404, f"Unknown report '{parts[1]}'")
    if head == "annual-report" and method == "GET":
        version = q.get("version", "complete")
        if version not in ("complete", "streamlined", "ytd"):
            raise ApiError(400, "version must be complete, streamlined or ytd")
        return reports.annual_pages(conn, int(q.get("year") or calc.today().year), version)
    if head == "coach":
        if method == "GET" and len(parts) == 1:
            return herb.coach(conn)
        if method == "POST" and parts[1:] == ["checkin"]:
            return herb.checkin(conn, body)
        if method == "POST" and parts[1:] == ["dismiss"]:
            conn.execute("INSERT OR REPLACE INTO insight_dismissals VALUES(?, ?)",
                         (body.get("key"), calc.today().isoformat()))
            conn.commit()
            return {"ok": True}
    if head == "autopilot":
        return autopilot_get(conn) if method == "GET" else autopilot_put(conn, body)
    if head == "herb" and method == "POST":
        def saver(log, data, rid=None):
            return update_log(conn, log, rid, data) if rid else save_log(conn, log, data)
        if parts[1:] == ["confirm"]:
            draft = body.get("draft") or body
            return herb.confirm(conn, draft, saver)
        if len(parts) == 1:
            dialog = body.get("dialog") if isinstance(body.get("dialog"), dict) else None
            return herb.ask(conn, body.get("text", ""), dialog=dialog, save=saver)
    if head == "scorecard" and method == "GET":
        return calc.scorecard(conn, q.get("log", "prospects"), q.get("measure", "quantity"),
                              q.get("dimension", "category"), q.get("period", "ytd"))
    if head == "admin" and parts[1:] == ["reset"] and method == "POST":
        seed.build(conn)
        return {"ok": True}
    raise ApiError(404, f"No route for {method} /api/{path}")


def make_server(port=None, host="127.0.0.1"):
    port = int(port if port is not None else os.environ.get("PORT", 8765))
    return ThreadingHTTPServer((host, port), Handler)


def main():
    conn = db.connect()
    if not conn.execute("SELECT 1 FROM account").fetchone():
        print("First run: creating synthetic data...")
        seed.build(conn)
    conn.close()
    srv = make_server()
    print(f"HERB simulator running at http://localhost:{srv.server_address[1]}  (Ctrl+C to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
