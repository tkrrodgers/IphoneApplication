# HERB Simulator — architecture and API contract

Windows simulation of the Logsperity + HERB iPhone app (design: `../HerbFeaturesDesign.md` v0.2).
It runs in a browser inside an iPhone 16-size frame (390 × 844 pt). It will be replaced by the SwiftUI
app on the Mac; the calculation rules and API shapes here are the ones the Swift app will follow.

## Stack

| Part | Choice | Why |
|---|---|---|
| Server | Python 3.13 stdlib `http.server` (`ThreadingHTTPServer`) | Nothing to install |
| Database | SQLite (`data/logsperity.db`) via stdlib `sqlite3` | Same role as SwiftData on the phone; single file |
| UI | `static/` — vanilla HTML/CSS/JS, no build step | Opens in Edge/Chrome |
| Voice | Browser Web Speech API: `SpeechRecognition` (mic, "Hi Herb" wake word) + `speechSynthesis` (HERB talks) | Works in Edge/Chrome on Windows |
| HERB | `herb.py`: deterministic intent parser + templated replies over `calc.py` | "Code computes, AI narrates"; a real model plugs in later |

Run: `run.bat` → `python server.py` on http://localhost:8765 . Reset data: `python seed.py --reset`.
Tests: `python -m unittest discover -s tests`.

## Files

```
herb-sim/
  server.py      HTTP server: static files + /api/* routing (JSON)
  db.py          connect(), SCHEMA, helpers (rows→dicts)
  taxonomy.py    pillars, sub-pillars, 63 categories, 53 activities, expense groups/categories + IRS map,
                 pick lists, mileage rates by date — stable string IDs
  calc.py        all §11 calculations; period parsing; scorecard(); no HTTP code
  reports.py     report builders → widget JSON (below); annual report pages
  herb.py        HERB: intent parsing, drafts, replies, coaching rules (§16.3), focus (§16.4), check-in
  seed.py        deterministic synthetic year (seed 42) for "Marcus Reed", independent mortgage broker
  tests/         unittest: test_calc.py, test_herb.py, test_api.py
  static/        index.html, app.css, app.js (UI)
  data/          logsperity.db (created by seed.py)
  run.bat
```

## Simulation clock

"Today" = the real current date (2026-10-30 when built). `SIM_TODAY` env var overrides (YYYY-MM-DD).
Synthetic data covers 2026-01-02 … today−1, plus a handful of unreviewed auto-captured items on the last
two days and some 2025 history (Q4 2025) for "same period last year".

## IDs and enums (from taxonomy.py)

- pillar: `clients | relationships | advertising | prospecting`
- sub_pillar: `clients | personal | professional | internet | traditional | prospecting`
- category_id / activity_id: slugs such as `cat.past_client`, `cat.realtor`, `act.open_houses`,
  `act.relationship_building_professional`, `act.mail_campaigning.clients` (duplicate names get a pillar suffix)
- expense group: `clients | relationships | ad_internet | ad_traditional | prospecting | general | self_improvement | technology | travel`
- expense category id: `exp.<group>.<slug>`; each has `irs` (one of the 16 IRS categories)
- strength: `red_hot | hot | medium | cold | no_go`
- capture: `manual | voice | receipt | gps | calendar | bank`
- income mode: `transaction | batch | type`; income type: `commission | consulting_fees | profit_sharing | bonuses | base_wages | allowance | referral_fees`
- referral_request: `yes | no | ask_7 | ask_14 | ask_21 | ask_30 | ask_45`

## Schema (SQLite)

```sql
sources(id INTEGER PK, name TEXT, normalized TEXT UNIQUE, kind TEXT)          -- kind: person|company|venue|online
prospects(id PK, date TEXT, last_name, first_names, phone1, phone1_type, phone2, phone2_type,
          email1, email2, address, zip, city, state,
          pillar, sub_pillar, category_id, source_id, activity_id, originally_from_source_id,
          strength, plan_of_action, follow_up TEXT, notes, capture, reviewed INTEGER, created_at)
closings(id PK, date, prospect_id UNIQUE, pillar, sub_pillar, category_id, source_id, activity_id,
         transaction_size REAL, income REAL, referral_request, post_closing_follow_up, notes, capture, reviewed)
income(id PK, date, mode, closing_id, pillar, sub_pillar, category_id, source_id, activity_id,
       type, transaction_count, transaction_size REAL, last_name, amount REAL, payer, expect_1099 INTEGER,
       notes, capture, reviewed)
expenses(id PK, date, vendor, amount REAL, group_id, relationship_sub_pillar, category_id, source_id,
         check_number, card_last4, purpose, with_whom, has_receipt INTEGER, notes, capture, reviewed)
trips(id PK, date, reason, destination, odometer_start REAL, odometer_end REAL, gps_miles REAL,
      is_business INTEGER, activity_id, source_id, notes, capture, reviewed)
activities(id PK, date, pillar, sub_pillar, activity_id, minutes INTEGER, source_id, notes, capture, reviewed)
account(id=1, json TEXT)
plans(year INTEGER PK, gross_income_goal, net_profit_goal, avg_commission, avg_transaction_size,
      hours_per_week, vacation_weeks)
autopilot(key PK, level INTEGER)
checkins(id PK, date, json)
commitments(id PK, checkin_id, text, activity_id, target INTEGER, due)
insight_dismissals(rule_key PK, date)
```

Dates are ISO `YYYY-MM-DD`. Money is dollars (REAL). `reviewed = 0` ⇒ item is in the Review queue.
Closing income is credited through a linked `income` row (mode `transaction`, `closing_id` set) when
"Add to Income Log" is yes; reports never double-count.

## Periods

Query param `period`: `ytd` (default) · `month` (current) · `month:YYYY-MM` · `q:YYYY-N` · `year:YYYY` ·
`last30` · `custom:YYYY-MM-DD:YYYY-MM-DD`. Every response that depends on a period echoes
`period: {key, label, from, to}`.

## Endpoints (all JSON; errors → `{"error": "..."}` with 4xx)

| Method & path | Body / query | Returns |
|---|---|---|
| GET `/api/taxonomy` | | `{pillars:[{id,name}], subPillars:[{id,name,pillar}], categories:[{id,name,pillar,subPillar}], activities:[…same…], expenseGroups:[{id,name,pillar|null}], expenseCategories:[{id,group,name,irs}], irsCategories:[…], picklists:{strength:[{id,name,color}], planOfAction:[…], followUpDays:[…ints], referralRequest:[{id,name}], incomeTypes:[{id,name}], professions:[…], phoneTypes:[…], mileageReasons:[…]}}` |
| GET/PUT `/api/account` | PUT: partial fields | `{name,title,email,company,phone,profession,address,zip,city,state,reminderTime:"17:30",plan:"monthly"\|"annual",subscription:{status:"active",via:"Apple In-App Purchase (simulated)",renews:"YYYY-MM-DD",price:"$50/month"}}` — **no card fields ever** |
| GET/PUT `/api/plan` | `?year=`; PUT inputs | `{year, inputs:{grossIncomeGoal,netProfitGoal,avgCommission,avgTransactionSize,hoursPerWeek,vacationWeeks}, outputs:{monthlyGross,monthlyNet,annualExpenses,monthlyExpenses,yieldPct,annualTransactions,monthlyTransactions,annualVolume,monthlyVolume,annualWorkHours,hourlyGross,hourlyNet}, extended:{conversion,prospectsNeeded,prospectsPerWeek,hoursPerProspect,bbHoursNeeded,bbHoursPerWeek}}` |
| GET `/api/sources` | `?q=` | `[{id,name,kind,prospects,closings}]` (autocomplete) |
| GET `/api/<log>` | log ∈ prospects, closings, income, expenses, trips, activities; `?period=&pillar=&q=&limit=` | `{period, rows:[…row + display fields: categoryName, activityName, sourceName, irs, miles…], totals:{count, …}}` |
| POST `/api/<log>` | row fields (names as schema, camelCase **or** snake_case accepted); `source` may be a name (created if new). Prospect POST may include `phones` etc. Closing POST: `prospectId`, `addToIncome` (default true), `additionalTransactions:[{transactionSize,income}]` → income rows (rule R3). Expense/trip/activity POST may be an array (multi-row screens). | `{ok:true, row}` or `{ok:true, rows}` |
| PUT/DELETE `/api/<log>/<id>` | partial fields | `{ok:true, row}` |
| GET `/api/today` | | `{date, greeting, kpis:[{key,label,value,display,sub}], focus:[{title,why,value}], followUps:[{id,kind,name,reason,due,chip:"late"\|"today"\|"new"\|"soon",prospectId}], reviewCount, insight:{text,level}\|null, index:{value}}` |
| GET `/api/review` | | `[{id:"<log>:<rowid>", log, capture, title, subtitle, question, fields:{…}, suggestions:{…}}]` |
| POST `/api/review/<log>:<rowid>` | `{action:"confirm"\|"dismiss", patch:{…}}` | `{ok:true, remaining}` (dismiss deletes the auto item) |
| GET `/api/reports` | | menu `{groups:[{id,title,items:[{key,title}]}]}` — groups: logs, quick, detailed, monthly (per §14.1) |
| GET `/api/reports/<key>` | `?period=` | `{key,title,period,widgets:[…]}` |
| GET `/api/annual-report` | `?year=&version=complete\|streamlined\|ytd` | `{title, period, pages:[{title, widgets:[…]}]}` |
| GET `/api/coach` | | `{index:{value,label,drivers:[{key,label,value,display,benchmark,benchmarkDisplay}],trend:[{month,value}]}, plan:{items:[{key,label,actual,projected,goal,display:{…},pacePct}]}, insights:[{key,level:"watch"\|"concern"\|"win"\|"info",title,text,numbers,sample}], focus:{say,items:[…],drop}, lastCheckin}` |
| POST `/api/coach/checkin` | `{commitments?:[…]}` to save | `{steps:[{title,text,say}], commitments:[…]}` |
| GET/PUT `/api/autopilot` | PUT `{key,level}` | `[{key,label,level,min,max,description}]` |
| POST `/api/herb` | `{text, dialog?}` | `{intent, say, display?, cards:[{title,subtitle,value,chip}], draft?:{log,data,summary:[{label,value,ask?}],id?}, actions:[{label,action:"reply"\|"edit_draft"\|"confirm_draft"\|"open"\|"say",target?}], followUp?:bool, dialog?, pending?:{type,slot?,slots?}, saved?:log, openForm?:bool}` — when HERB asks a follow-up question it returns `dialog` (opaque state, see `dialog.py`); send it back with the next `text`. `dialog: null` means the conversation ended. `reply` actions are quick answers: send their `target` as the next `text` |
| POST `/api/herb/confirm` | `{draft}` | `{ok, say, row}` — a draft with `id` updates that record |
| POST `/api/admin/reset` | | reseeds; `{ok:true}` |

## Widget JSON (reports, annual report, coach)

Every widget: `{type, title, span?: 1|2|3}`. Formats: `money | money0 | pct | num | num1 | hours | miles`.

| type | fields |
|---|---|
| `stat` | `value, display, caption, formula` (formula shown italic under the big number, e.g. "0.54 = 69.75 ÷ 129") |
| `stats` | `items:[{label,display,caption?,formula?}]` |
| `table` | `columns:[{key,label,align:"left"\|"right",format?}], rows:[{…}], total?:{…}, note?` |
| `bar` | `items:[{label,value,display}], horizontal?:bool` |
| `pie` / `donut` | `items:[{label,value,display}], center?:"20%"` |
| `stack` | `items:[{label,value,display,role:"profit"\|"expense"}]` (P&L bar) |
| `progress` | `items:[{label,actual,projected,goal,displayActual,displayProjected,displayGoal,pct}]` |
| `index` | `value, display, label, drivers:[{label,display,benchmarkDisplay,ratio}]` |
| `text` | `paragraphs:[…]` |
| `list` | `items:[{title,text,level?}]` |
| `columns` | `series:[{name}], items:[{label, values:[…], displays:[…]}]` (grouped monthly bars) |

## HERB intents (herb.py)

Wake-word prefixes ("hi herb", "hey herb", "herb,") are stripped. Intents: `log_prospect, log_closing,
log_income, log_expense, log_trip, log_activity, focus, follow_ups, pace, conversion, sources_no_close,
efficiency, roi, index, top_sources, income_summary, expenses_summary, mileage_summary, review, report,
plan, help, smalltalk, unknown`. Logging intents return a `draft` (never saved until confirm).
Numbers in `say` always come from calc.py. Replies are short (spoken in a car).
