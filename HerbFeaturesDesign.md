# HERB Features Design — Logsperity with an AI Business Coach

**Logsperity** by **Prosperity Simplified** — *Know Your Numbers. Maximize Your Time. Multiply Your Prosperity.*
**HERB** is the AI assistant, analyst and coach built into Logsperity.

| | |
|---|---|
| Document | `HerbFeaturesDesign.md` — v0.4 (requirements, input screens, reports; follow-up questions §17.2; decision log §22; Windows simulator §23) |
| Date | October 31, 2026 |
| Sources | `Logsperity Model 3.3.2018.xlsx` (63 tabs) · `Logsperity Quick Reference Guide.pdf` · `Logsperity Annual Report Sample 10.2026.pdf` · `Logsperity Updated USP 10.2026.docx` · `HERBSupportsLoanBroker.md` (pilot design) |
| Owner's direction | Keep the proven Logsperity model; **automate as much of it as possible with AI** |
| Platform | iPhone first (SwiftUI, iOS 27); same codebase for iPad and Mac |

> Sample numbers come from the Logsperity model and the sample report, or are fictional. Tax and
> compliance notes are design input, not tax or legal advice.

---

## Contents

1. [Summary](#1-summary)
2. [The Logsperity model in one page](#2-the-logsperity-model-in-one-page)
3. [Functional requirements](#3-functional-requirements)
4. [The taxonomy: Pillars, Categories, Activities, Sources](#4-the-taxonomy-pillars-categories-activities-sources)
5. [Logging rules](#5-logging-rules)
6. [AI automation design](#6-ai-automation-design)
7. [Screen map](#7-screen-map)
8. [Account, onboarding and help screens](#8-account-onboarding-and-help-screens)
9. [Business Plan Set Up screen](#9-business-plan-set-up-screen)
10. [Input screens (the six logs)](#10-input-screens-the-six-logs)
11. [Calculation specification](#11-calculation-specification)
12. [The Logsperity Index](#12-the-logsperity-index)
13. [Scorecards (internal)](#13-scorecards-internal)
14. [Reports](#14-reports)
15. [The Annual Report](#15-the-annual-report)
16. [HERB coaching](#16-herb-coaching)
17. [Voice commands and follow-up questions](#17-voice-commands)
18. [Data model](#18-data-model)
19. [Issues found in the 2018 model (and how the app fixes them)](#19-issues-found-in-the-2018-model)
20. [Roadmap](#20-roadmap)
21. [Open questions for Prosperity Simplified](#21-open-questions-for-prosperity-simplified)
22. [Decision log and pending items](#22-decision-log-and-pending-items)
23. [Windows simulator (before the Mac)](#23-windows-simulator-before-the-mac)
- [Appendix A — Expense categories and IRS mapping](#appendix-a--expense-categories-and-irs-mapping)
- [Appendix B — Pick lists](#appendix-b--pick-lists)

---

## 1. Summary

Logsperity asks a solopreneur to spend **about six minutes a day** on **six logs**: **Prospects,
Closings, Income, Expenses, Mileage and Activity (business-building time)**. Every prospect, closing,
dollar and hour is tagged with **where the business came from**: one of **four Pillars** (Clients,
Relationships, Advertising, Prospecting), plus a Category, a Source and the Activity that produced it.

From those six logs, the 2018 Excel model builds **12 scorecards, 19 analyses and 25 reports**. The
key outputs are conversion rates, hours per prospect and per closing, hourly rates, ROI by pillar, a
Business Plan tracker, the proprietary **Logsperity Index**, and an Annual Report with coaching advice.

**This design keeps that model exactly.** The app is the Excel model rebuilt as an iPhone app, with
every number calculated from the logs. **HERB** adds three things on top:

| HERB as… | Takes over from the user | Result |
|---|---|---|
| **Assistant** | Typing entries | Six minutes a day → about one: entries come from voice, receipt photos, GPS trips, calendar and bank data; the user reviews |
| **Analyst** | Reading 25 reports | HERB reads them and tells you the 1–3 things that matter, in plain English |
| **Coach** | The static "Coaching Advice" page | Advice based on the user's own numbers, a weekly check-in and Business Plan pace alerts |

---

## 2. The Logsperity model in one page

```
 INPUT SCREENS (6)  ─►  LOGS (6)  ─►  SCORECARDS (12)  ─►  ANALYSES (19)  ─►  REPORTS (25)
 Prospects              Prospects     by Category/Activity   conversion, efficiency,   view · print · email
 Closings               Closings      × Quantity/Income/     hourly rate, ROI, profit, monthly · YTD · annual
 Income                 Income          Volume, conversion,  Logsperity Index
 Expenses               Expenses        expenses, activity
 Mileage                Mileage
 Activity               Activity                  ▲
                                                  │
 BUSINESS PLAN SET UP (goals) ────────────────────┘  → Business Plan Report (current vs projected vs goal)
```

In the app, scorecards and analyses aren't separate screens. They are calculations the **Reports**
and **HERB** draw on (§11, §13).

---

## 3. Functional requirements

IDs are used for traceability (FR = functional requirement). "Source" points to the workbook tab (T##),
the Quick Reference Guide (QRG), the Annual Report sample (AR) or the USP.

### 3.1 Account and access

| ID | Requirement | Source |
|---|---|---|
| FR-01 | Public home screen: What is Logsperity? (video), Pricing Options, Join, Log In | T1 |
| FR-02 | Account set up: name, title, email, company, phone, profession, address (city/state filled in from zip), daily reminder time (30-minute steps) | T4 |
| FR-03 | Subscription plans: Monthly $50 / Annual $500 ("20% savings") | T4 |
| FR-04 | Dashboard after log-in: the six logs plus Help, Reports, Account | T2 |
| FR-05 | Help: customer service email, FAQs, member forum, Input Cheat Sheet, referral program, other products | T3 |
| FR-06 | Account screen: personal settings and subscription/payment management | T2 |

### 3.2 Logging

| ID | Requirement | Source |
|---|---|---|
| FR-10 | Six input screens, one per log; date defaults to today and can be changed | T13–T50 |
| FR-11 | Prospects, Closings, Income and Activity entries are tagged with Pillar → Category → Source → Activity | QRG, T10 |
| FR-12 | Category and Activity pick lists are filtered by the selected Pillar | QRG |
| FR-13 | Source is free text that is remembered and suggested next time (autocomplete) | T10, T11 |
| FR-14 | Prospects capture Strength (5 colors), Plan of Action and a Follow-Up Date (number of days or a calendar date) | T13 |
| FR-15 | A Closing can be picked from existing Prospects; contact details and tags carry over | T21 |
| FR-16 | A Closing captures Transaction Size (volume) and Income Earned; "Add to Income Log?" yes/no | T21 |
| FR-17 | A Closing offers "Request Referral or Review": Yes / No / Ask in 7, 14, 21, 30 or 45 days | T21 |
| FR-18 | Income can be entered by Transaction (pick a closing), by Batch (type, # of transactions, amount) or by Type (non-transaction income) | T37, T38 |
| FR-19 | Expenses: several per screen; Pillar (or a No-Pillar group), Category, Vendor, Amount, Check #, receipt Photo | T41 |
| FR-20 | A receipt photo fills in the expense fields | T41 |
| FR-21 | Each expense category maps to an IRS (Schedule C) category | T42 |
| FR-22 | Mileage: several trips per screen; Reason and Destination (remembered lists); start/end odometer or GPS; per-trip and daily totals | T47 |
| FR-23 | Activity: several entries per screen; Pillar, Activity, Time in 15-minute steps | T50 |
| FR-24 | The Input Cheat Sheet explains the Pillars, Categories, Sources and Activities, with icons | T11, QRG |
| FR-25 | A daily reminder to log, at the user's chosen time | T4 |

### 3.3 Business plan

| ID | Requirement | Source |
|---|---|---|
| FR-30 | Business Plan Set Up: gross income goal, net profit goal, average commission per transaction, average transaction size, hours per week, weeks of vacation | T12 |
| FR-31 | Calculate monthly targets, required transactions and volume, projected work hours, and anticipated hourly rates (§11.1) | T12 |
| FR-32 | Business Plan Report: Current vs Projected-to-date vs Annual Goal for income, profit, closings and volume; projected vs actual hourly rates | T61, AR p2 |

### 3.4 Reports and analysis

| ID | Requirement | Source |
|---|---|---|
| FR-40 | Reports menu with four groups: Logs, Quick Stats, Detailed Reports, Monthly & YTD Reports | T9 |
| FR-41 | View any one report; print or email one or several (choose with check boxes) | T9 |
| FR-42 | Report menu fits one page on tablet/computer and four pages on a phone | T9 |
| FR-43 | Every log can be viewed, sorted, printed and emailed | T5 |
| FR-44 | Conversion rates by pillar, category, activity and source, ranked best to worst, with the "no conversion" items listed separately | T32–T36 |
| FR-45 | Efficiency: hours per prospect and per closing by pillar; gross and net hourly rate | T55 |
| FR-46 | Profit and ROI by pillar, with and without the value of time | T58 |
| FR-47 | Traditional P&L in IRS format | T44 |
| FR-48 | Logsperity Index | T56 |
| FR-49 | 12 monthly reports, a YTD report and an Annual Report (Complete and Streamlined versions) | T9, AR |
| FR-50 | Big numbers in reports show their formula underneath, e.g. "0.54 = 69.75 ÷ 129" | AR |

### 3.5 AI (the owner's direction and the USP)

| ID | Requirement | Source |
|---|---|---|
| FR-60 | Enter information through natural conversation (voice or text) | USP |
| FR-61 | Timely reminders to log | USP |
| FR-62 | Categorize expenses from connected financial accounts | USP |
| FR-63 | Capture and organize receipts from phone photos | USP, T41 |
| FR-64 | Identify and categorize business mileage | USP, T47 |
| FR-65 | Identify the most profitable activities; analyze sources and conversion; measure return on time and money | USP |
| FR-66 | Reveal underperforming activities and unnecessary expenses; spot trends | USP |
| FR-67 | Help set goals; create a plan from them; monitor progress; recommend course corrections | USP |
| FR-68 | Action plans to improve conversion and profit; accountability check-ins | USP |
| FR-69 | Answer "What should I focus on this week to make more money?" | USP |

---

## 4. The taxonomy: Pillars, Categories, Activities, Sources

The heart of Logsperity. **Every prospect, closing, income entry and activity hour is tagged so the user
can see where business really comes from.**

| Level | Meaning | Picked how | Icon (QRG) |
|---|---|---|---|
| **Pillar** | One of the four places business comes from | Pick one of 4 | Greek column |
| Sub-pillar | Relationships → Personal / Professional; Advertising → Internet / Traditional | Derived from Category | — |
| **Category** | *Who or what* the lead is (Past Client, Realtor, Website-Paid…) | List filtered by Pillar | Grid with target |
| **Source** | The specific person, company or venue ("Franks", "Zillow") | Free text with autocomplete | Org chart |
| **Activity** | *What the user did* to produce it (Open Houses, Partner Coaching…) | List filtered by Pillar | Running man |

### 4.1 Categories (63)

| Pillar | Sub-pillar | Categories |
|---|---|---|
| Clients | — | Past Client, Current Client, Prospective Client |
| Relationships | Personal | Family, Friend, Social Group, Church, School, Sports, Alumni Group |
| Relationships | Professional | Accountant, Appraiser, Architect, Attorney, Banker, Business Coach, Consultant, Contractor, Dentist, Designer, Doctor, Engineer, Escrow Officer, Financial Planner, Insurance Agent, Insurance Company, Lender, Realtor, Salesperson, Therapist, Vendor |
| Advertising | Internet | Website-Personal, Website-Blog, Website-Free, Website-Paid, Website-Video Site |
| Advertising | Traditional | Article, Billboard, Car Wrap, Door Hanger, Flyer, Lead Generator, Magazine, Mailer/Farming, Newsletter, Newspaper, Promotion, Radio, Sign, Sponsorship, Swag, TV |
| Prospecting | — | Cold Calls, Committee, Door Knocking, Expired Listings, Floor Time, Office Visits, Open House, Organization, Network-Open Group, Seminar, Trade Show |

### 4.2 Activities (53)

| Pillar | Sub-pillar | Activities |
|---|---|---|
| Clients | — | Past Client Interaction, Current Client Interaction, Marketing for Current Client, Prospective Client Interaction, Client Appreciation Party, Database Marketing, Email Campaigning, Facebook Marketing, Mail Campaigning, Newsletter Campaigning, Personal Visit, Twitter Marketing |
| Relationships | Personal | Relationship Building-Personal, Community Involvement-Personal, Socializing |
| Relationships | Professional | Relationship Building-Professional, Networking-Closed Group, Partner Coaching, Committee Involvement, Organization Involvement, Community Involvement-Professional |
| Advertising | Internet | Website Set Up, Blog Development, Website Ad Set Up-Free, Website Ad Set Up-Paid, Video Production |
| Advertising | Traditional | Article Writing, Billboard Ad Set Up, Car Wrap Set Up, Door Hanger Set Up, Flyer Set Up, Lead Generation, Magazine Ad Set Up, Mail Campaigning, Newsletter Set Up, Newspaper Ad Set Up, Promotion Set Up, Radio Ad Set Up, Sign Set Up, Sponsorship Set Up, Swag Set Up, TV Ad Set Up |
| Prospecting | — | Cold Calling, Committee Involvement, Door Knocking, Expired Listings Calling, Floor Time, Office Visits, Open Houses, Organization Involvement, Networking-Open Group, Seminar, Trade Show |

**App rules for the taxonomy**
- Ship this as a **versioned taxonomy file** (`taxonomy-v1.json`) with stable IDs, so names can be fixed
  ("Buiding" → "Building", "Newletter" → "Newsletter") without breaking history.
- A few activity names appear under two pillars (Mail Campaigning; Committee and Organization
  Involvement). They get **separate IDs per pillar**.
- Users can **hide** items they never use and **add custom** Categories, Activities and Sources under a
  Pillar. Custom items roll up to that Pillar in every report.
- **Profession packs** (§21) can rename or hide items. For example, "Expired Listings" makes sense for
  real estate but not for a dentist.

---

## 5. Logging rules

From the Quick Reference Guide's best practices. **The app enforces these automatically** so users don't
have to remember them.

| # | Rule | How the app applies it |
|---|---|---|
| R1 | Log **every** inquiry as a prospect, however weak. Weak leads show which streams to cut | HERB creates prospect drafts from calls, texts and lead emails (§6). Strength "Cold" or "No Go" still counts |
| R2 | A **referral from a former client** goes under **Clients**, even if the chain started with someone else | When the referrer is a past client, HERB defaults Pillar = Clients and keeps an optional "Originally from" link to the first source |
| R3 | **Several transactions for one client at once**: one goes on the **Closing log**, the rest on the **Income log** | The closing screen has "+ Additional transactions" which creates Income entries, not extra closings |
| R4 | **Repeat clients**: the first transaction is a Closing; later ones go on the Income log | Picking an existing client who already has a closing offers "Log as income (repeat client)" |
| R5 | **One closing per prospect** (keeps conversion rates honest) | Enforced. The 2018 sample shows a 300% conversion for one source, which the app prevents |
| R6 | Mileage: the beginning odometer defaults to the previous trip's ending | Default value; GPS trips skip odometers entirely |

---

## 6. AI automation design

### 6.1 Principles

1. **Capture without asking.** If the phone already knows something (a drive, a meeting, a card charge,
   a receipt photo), HERB logs it and puts it in the **Review queue**.
2. **Ask one question, not a form.** "Business trip to Lakeside Realty?" can be answered by voice, tap or notification.
3. **Learn from every correction.** A correction becomes a rule for that vendor, place or contact.
4. **Code computes, AI narrates.** Swift calculates every number (§11). The model picks which
   analysis to show and words the answer, so dollar figures are never invented.
5. **The human owns consequential actions.** HERB drafts messages and plans; the user sends, pays and files.
6. **On-device first; the developer stores nothing** (pilot design §12): data lives on the phone and in the user's iCloud.

### 6.2 Automation levels

| Level | Name | HERB… |
|---|---|---|
| 0 | Manual | does nothing until asked |
| 1 | Suggest | notices and offers ("Log this as a prospect?") |
| 2 | Draft | fills in the entry; the user taps Save |
| 3 | Auto + review | saves it and lists it in the Review queue |
| 4 | Autopilot | saves silently when a learned rule matches with high confidence |

An item can be promoted to Autopilot after **3 confirmations with no corrections**. Any correction drops it
back to level 2. Users change levels in **More → HERB Autopilot**.

### 6.3 What HERB automates on each log

| Log | Manual 2018 way | HERB way | Default level |
|---|---|---|---|
| **Prospects** | Type every field | Say it: "New lead, Kevin Morales, 940-555-0137, Ruth Alvarez sent him, wants to talk Thursday." HERB fills in name, phone, **Pillar/Category/Source/Activity** (Ruth → Relationships · Professional · Realtor · "Ruth Alvarez" · Relationship Building-Professional), Strength and Follow-up. Also: business-card scan; lead emails shared to the app; an unknown caller after an open house → "Log as a prospect from the open house?" | 2 (1 for unknown callers) |
| **Closings** | Re-type the client and amounts | "The Morales loan closed, 520 thousand, I made 6,500." HERB finds the prospect, carries over the tags, fills in volume and income, offers "Add to Income Log" (default Yes) and schedules the referral/review request | 2 |
| **Income** | Type deposits | Bank deposits (§6.5) matched to expected closing income; batch and type income suggested from payer patterns | 2 → 3 |
| **Expenses** | Type each expense, choose a category | Receipt photo → fields filled in → Category → IRS category; bank/card transactions categorized by vendor rules; receipt and bank charge merged so nothing is counted twice; meals matched to calendar meetings ("Lunch with Dana" → Relationships · Meal) | 2 → 4 |
| **Mileage** | Odometer readings | Trips detected automatically (Core Location visits); Reason and Destination guessed from the calendar and learned places; one tap for Business/Personal; GPS miles | 3 → 4 |
| **Activity** | Type minutes per activity | Built automatically from calendar events and detected trips ("Networking breakfast 7–8:30" → Networking-Closed Group, 90 min); 15-minute rounding; voice ("2 hours of door knocking") | 3 |

### 6.4 The daily one-minute review (replaces "six minutes a day")

At the user's **Daily Reminder time** (Account Set Up), HERB sends one notification:

> **Today HERB logged:** 3 trips (41 mi) · 2 expenses ($112) · 2.5 h of activity · 1 new prospect.
> **Needs you:** 2 quick questions.

Tapping it opens a stack of cards ("Business trip?", "Which pillar was this lunch?"). The reminder only
fires if something needs attention. Unanswered items wait in the Review queue.

### 6.5 Connected financial accounts (FR-62)

| Option | Developer server? | Recommendation |
|---|---|---|
| **Statement import** (CSV/OFX/QFX shared from the bank app) | No | **Pilot default.** Works with any bank and no one but the user holds the data |
| **Apple FinanceKit** (accounts in Apple Wallet; confirm current coverage) | No | Use where available |
| **User's own QuickBooks Online** (OAuth tokens in the Keychain) | No | For users already on QuickBooks |
| **Aggregator** (Plaid, MX…) | **Yes** — needs a server to hold secrets and tokens | Later, as a paid tier, with a proper security program |

---

## 7. Screen map

Tabs: **Today · Log · Reports · Coach · More**

```
Today ─ Ask HERB bar · today's focus (top 3) · follow-ups due · Review queue badge · quick-add for the 6 logs
Log ─── Prospects · Closings · Income · Expenses · Mileage · Activity   (list → detail → input screen)
Reports ─ Logs · Quick Stats · Detailed Reports · Monthly & YTD · Annual Report   (view / print / email)
Coach ── Logsperity Index · Business Plan tracker · weekly check-in · insights · action plans
More ─── Account · Business Plan Set Up · Input Cheat Sheet · HERB Autopilot · Help · Data & privacy
```

| # | Screen | From 2018 model | Notes |
|---|---|---|---|
| S1 | Welcome (What is Logsperity? · Pricing · Join · Log In) | T1 | Sign in with Apple replaces the Logsperity password |
| S2 | Account Set Up | T4 | §8 |
| S3 | Today (dashboard) | T2 | The six-log buttons become quick-add + HERB |
| S4 | Help | T3 | §8.3 |
| S5 | Input Cheat Sheet | T11, QRG | Searchable, with the QRG icons |
| S6 | Business Plan Set Up | T12 | §9 |
| S7 | Prospect input | T13 | §10.1 |
| S8 | Closing input | T21 | §10.2 |
| S9 | Income input | T37 | §10.3 |
| S10 | Expense input | T41 | §10.4 |
| S11 | Mileage input | T47 | §10.5 |
| S12 | Activity input | T50 | §10.6 |
| S13 | Log lists (×6) | T14, 22, 38, 43, 48, 51 | Sort by any column; filter by Pillar/Category/Source/Activity/date |
| S14 | Reports menu | T9 | §14 |
| S15 | Report viewer | T44, T55–T61, AR | Print, email, share as PDF |
| S16 | Annual Report | AR | §15 |
| S17 | Coach | T56, T61, T62 | §16 |
| S18 | Review queue | new | §6.4 |
| S19 | Ask HERB (voice/chat) | new | Pilot design §5.2–5.3 |
| S20 | HERB Autopilot settings | new | §6.2 |

---

## 8. Account, onboarding and help screens

### 8.1 Account Set Up (S2)

| Field | Type | Required | Notes |
|---|---|---|---|
| Name | Text | ✓ | Prefilled from Sign in with Apple |
| Title | Text | | |
| Email | Email | ✓ | Prefilled; can be Apple's private relay address |
| Company Name | Text | | |
| Phone | Phone | | |
| Profession | Pick list | ✓ | Accountant, Appraiser, Architect, Attorney, Banker, Business Coach, Consultant, Contractor, Dentist, Designer, Doctor, Engineer, Escrow Officer, Financial Planner, Insurance Agent, Lender, Realtor, Salesperson, Therapist (+ Other). **Chooses the profession pack** |
| Address, Zip → City & State | Text | | City and state filled in from the zip; editable |
| Time for Daily Reminder | Time, 30-minute steps | ✓ | Default 5:30 pm; drives the daily review (§6.4) |
| Plan | Monthly $50 / Annual $500 ("20% savings") | ✓ | See below |

**Payment change from the 2018 model:** the app does **not** collect a credit card number, expiration
date or security code. Subscriptions sold inside an iPhone app go through **Apple In-App Purchase**
(Apple handles payment and renewal). US App Store rules also allow a link out to web checkout. Confirm
current rules and Apple's fee before launch.

### 8.2 Onboarding (first run, about 5 minutes, conversational with HERB)

1. Profession → load the profession pack (hides categories that don't apply).
2. Business Plan Set Up (§9). HERB asks the six questions out loud.
3. Permissions, each explained in one line: Location (mileage), Calendar (activities), Contacts (prospects), Camera (receipts), Notifications (daily review).
4. Optional: import last year's numbers or an existing Logsperity Excel workbook (§21 Q2).
5. Choose the HERB Autopilot style: **Hands-on** (levels 1–2) · **Balanced** (default) · **Max automation** (levels 3–4).

### 8.3 Help (S4)

Customer service (email from the app) · FAQs · Member forum (web link) · Input Cheat Sheet ·
Refer a friend · Other Prosperity Simplified products · **Ask HERB "how do I…"** (answers from the help content).

---

## 9. Business Plan Set Up screen

### 9.1 Inputs (from T12; Annual Report goals added)

| Field | Example | Notes |
|---|---|---|
| Desired Annual Gross Income (before expenses) | $150,000 | |
| Desired Annual Net Profit (after expenses) | $125,000 | Must be ≤ gross |
| Average Commission / Yield per Transaction | $6,500 | HERB suggests last 12 months' average once there is data |
| Average Transaction Size | $335,000 | Same |
| Desired Hours per Week | 40 | Total work hours, not only business-building |
| Desired Weeks of Vacation | 0 | |
| *New:* Plan year | 2027 | One plan per year; history kept |

### 9.2 Calculated ("This Is Your Business")

| Output | Formula | Example |
|---|---|---|
| Monthly Gross Income | gross ÷ 12 | $12,500 |
| Monthly Net Profit | net ÷ 12 | $10,417 |
| Annual Projected Expenses | gross − net | $25,000 |
| Average Monthly Projected Expenses | expenses ÷ 12 | $2,083 |
| Personal % Yield per Transaction | commission ÷ transaction size | 1.94% |
| Annual Transactions Needed | gross ÷ commission | 23.1 |
| Monthly Transactions Needed | annual ÷ 12 | 1.92 |
| Annual Volume Needed | transactions × size | $7,730,769 |
| Average Monthly Volume Needed | volume ÷ 12 | $644,231 |
| Annual Projected Work Hours | (52 − vacation weeks) × hours/week | 2,080 |
| Anticipated Hourly Rate (gross) | gross ÷ work hours | $72.12 |
| Anticipated Hourly Rate (net) | net ÷ work hours | $60.10 |

### 9.3 HERB extensions (working back further, once there's data)

The 2018 plan stops at transactions. HERB continues the chain using the user's own rates:

```
Transactions needed (23.1)
 ÷ conversion rate (40%)                     = prospects needed        57.7  → 1.2 / week
 × hours per prospect (6.24)                 = business-building hours 360   → 7.8 h / week
 split by pillar using each pillar's conversion and hours per closing (§11.4)
```

> "To reach $150k you need about 58 prospects and 8 business-building hours a week. Your Clients pillar
> converts best (58%) at 8.6 hours per closing, so put the most time there."

The plan becomes the **scorecard** HERB checks every week (§16).

---

## 10. Input screens (the six logs)

Shared behavior on all six screens:
- **Date** defaults to today and can be changed.
- **Save · Save & Next** (the 2018 "Next … Entry") · **Cancel**.
- Pillar → Category and Pillar → Activity are filtered lists; Source autocompletes from previous entries.
- A **mic button** fills the whole form from speech; a violet **auto** chip marks fields HERB filled in.
- Validation is light: only the fields marked ✓ are required.

### 10.1 Prospect input (S7, T13)

| Section | Field | Type | Req. | AI help |
|---|---|---|---|---|
| Contact | Last Name, First Name(s) | Text | ✓ (one) | From speech, contact card, business-card scan or caller ID |
| | Phone 1, Phone 2 + Type (mobile/work/home) | Phone | | |
| | Email 1, Email 2 | Email | | |
| | Address, Zip → City & State | Text | | |
| Attribution | Pillar | Pick 1 of 4 | ✓ | Suggested from the source (a past client → Clients, R2) |
| | Category | Filtered list | ✓ | Suggested |
| | Source | Autocomplete text | ✓ | Matched to existing sources ("Ruth at Cedar and Main" → *Ruth Alvarez*). "Unknown" is allowed and sends the prospect to the Review queue (D3) |
| | Activity Used | Filtered list | ✓ | Suggested from the calendar ("You were at the open house at 2 pm") |
| | Originally from | Link to a source | | New (R2) |
| Follow-up | Strength of Contact | 5 colors: Red Hot · Hot · Medium · Cold · No Go | | From tone/words ("ready to buy" → Hot) |
| | Plan of Action | Pick list (Appendix B) | | |
| | Follow-Up Date | 5, 7, 10, 15, 21, 30, 45, 60, 75, 90, 120, 180, 250, 365 days, or a calendar date | | Creates a reminder; HERB drafts the message |
| | Notes | Text | | Dictation |

### 10.2 Closing input (S8, T21)

| Field | Type | Req. | Notes |
|---|---|---|---|
| Choose from Prospects | Search | ✓* | *Or "new client" (then the contact fields appear). Carries over contact, Pillar, Category, Source, Activity |
| Contact fields | as §10.1 | | Read-only if carried over; editable |
| Pillar / Category / Source / Activity | as §10.1 | ✓ | Carried over |
| Transaction Size (volume) | Currency | ✓ | |
| Income Earned | Currency | ✓ | HERB suggests size × the user's usual yield % |
| Add to Income Log? | Yes/No (default Yes) | | Yes creates a linked Income-by-Transaction entry |
| + Additional transactions | Repeatable | | Rule R3 — these go to the Income log |
| Request Referral or Review | Yes · No · Ask in 7 / 14 / 21 / 30 / 45 days | | HERB drafts the request when it's due |
| Post-closing follow-up date | Date | | Was on T23; anniversaries, reviews |
| Notes | Text | | |

### 10.3 Income input (S9, T37)

Three modes, chosen with a segmented control:

| Mode | Fields | Notes |
|---|---|---|
| **By Transaction** | Choose from Closings (or enter Last Name, Transaction Size and Income by hand), Pillar/Category/Source/Activity (carried over), Income, Notes | For when "Add to Income Log" wasn't used, or for repeat clients (R4) |
| **Batch of Transactions** | Type, Number of Transactions, Income Amount (→ average per transaction) | Several deals paid together |
| **By Type** (non-transaction) | Type: Commission · Consulting Fees · Profit Sharing · Bonuses/Incentives · Base Wages · Allowance · Referral Fees; Amount; optional Pillar | Income that isn't tied to a deal |
| All | Date, Payer, Notes, *new:* 1099 expected (Y/N), Deposit matched (auto) | |

### 10.4 Expense input (S10, T41)

Several expense rows on one screen (the 2018 screen held three):

| Field | Type | Req. | Notes |
|---|---|---|---|
| Date | Date | ✓ | From the receipt |
| Vendor Name | Autocomplete | ✓ | From the receipt; remembered |
| Amount | Currency | ✓ | From the receipt (total, tax, tip) |
| Group (Pillar) | Clients · Relationships · Advertising-Internet · Advertising-Traditional · Prospecting · **No Pillar:** General · Self-Improvement · Technology · Travel | ✓ | Learned per vendor; meals linked to the meeting's pillar |
| Category | Filtered list (Appendix A) | ✓ | Shows its **IRS category** read-only (e.g. "→ Advertising") |
| *New:* Relationship sub-pillar | Personal / Professional | if Relationships | Fixes issue I4 (§19) |
| *New:* Linked Source / person | Autocomplete | | Lets HERB calculate cost per source |
| Check # | Text | | |
| Payment | Last 4 digits | | From the receipt; used for bank matching |
| Photo | Camera / photo library | | Read on the device; stored with the entry |
| *New:* Business purpose, with whom | Text | Meals | IRS substantiation; HERB fills it in from the calendar |
| Notes | Text | | |

### 10.5 Mileage input (S11, T47)

Several trips on one screen, plus a running **Grand Total for the day**:

| Field | Type | Req. | Notes |
|---|---|---|---|
| Date | Date | ✓ | |
| Reason | Remembered list (defaults to the business activities, Appendix B) | ✓ | Guessed from the calendar |
| Destination | Remembered list | ✓ | Learned places |
| Beginning / Ending odometer | Number | ✓* | *Or **GPS** start/stop, or automatic detection. Beginning defaults to the previous ending (R6) |
| Total miles | Calculated | | Ending − Beginning, or GPS distance |
| *New:* Business / Personal | Toggle | ✓ | Only business miles count |
| *New:* Linked Activity / Source | | | Feeds return on time |

**Mileage rate** comes from a dated table bundled with the app (2018: $0.565; 2026: $0.725 Jan–Jun and
$0.76 Jul–Dec), applied by trip date. Kilometers are a setting for users outside the US.

### 10.6 Activity input (S12, T50)

Several rows on one screen:

| Field | Type | Req. | Notes |
|---|---|---|---|
| Date | Date | ✓ | |
| Pillar | Pick 1 of 4 | ✓ | |
| Activity | Filtered list | ✓ | |
| Time | 15-minute steps | ✓ | A start/stop timer is also available |
| *New:* Source / with whom | Autocomplete | | |
| *New:* Notes | Text | | |

**Automation:** HERB proposes activity rows from the day's calendar and detected trips. The user
confirms them in the daily review.

---

## 11. Calculation specification

All of these are **Swift functions with unit tests**, calculated from the logs for any date range
(month, quarter, YTD, year, custom) and filterable by Pillar, Sub-pillar, Category, Activity or Source.

### 11.1 Business plan — see §9.2.

### 11.2 Counts and totals

| Metric | Definition |
|---|---|
| Prospects | count(Prospect entries) |
| Closings | count(Closing entries), at most one per prospect (R5) |
| Volume | Σ Closing.transactionSize |
| Closing income | Σ Closing.income |
| Non-transaction income | Σ Income(batch) + Σ Income(type) |
| **Total income (gross)** | Σ all Income entries (closing income is included through the linked entry; no double counting) |
| Expenses | Σ Expense.amount + mileage deduction (miles × rate by date) |
| Business-building hours | Σ Activity.minutes ÷ 60 |
| Total work hours | From the Business Plan (hours/week × weeks elapsed); optionally logged |

### 11.3 Conversion

| Metric | Formula | Sample |
|---|---|---|
| Conversion rate (overall or by Pillar/Category/Activity/Source) | closings ÷ prospects | 20 ÷ 50 = **40%** |
| Share of prospects / closings by dimension | count ÷ total | Clients 24% of prospects |
| Ranked list | Sort by rate (descending), then by closings | |
| **No-conversion list** | items with prospects > 0 and closings = 0, sorted by prospects | FTHB 0 of 3 |

When there are no prospects, show "—" instead of an error. Always show **n** (sample size) next to a rate.

### 11.4 Deal size and efficiency

| Metric | Formula | Sample |
|---|---|---|
| Average closing volume | volume ÷ closings | $335,500 |
| Average closing income | closing income ÷ closings | $6,534 |
| Hours per prospect | business-building hours ÷ prospects (overall and per pillar) | 6.24 |
| Hours per closing | business-building hours ÷ closings | 15.6 |
| Income per business-building hour | income ÷ business-building hours (per pillar and per activity) | $418.85 |
| Profit per business-building hour | (income − expenses) ÷ business-building hours | $343.17 |
| **Hourly rate (gross)** | gross income ÷ total work hours | $62.83 (÷ 2,080) |
| **Hourly rate (net)** | net profit ÷ total work hours | $51.48 |
| Business-building hours per week | hours ÷ weeks elapsed | 5.99 |
| Hours in car | miles ÷ 60 (assumes 1 mile per minute) | |

### 11.5 Profit and ROI

| Metric | Formula |
|---|---|
| Net profit | gross income − expenses |
| Profit margin | net profit ÷ gross income |
| **ROI without time** (per pillar) | (pillar income − pillar expenses) ÷ pillar expenses |
| Wages invested (per pillar) | pillar business-building hours × **gross hourly rate** (§11.4) |
| Capital invested | pillar expenses + wages invested |
| **ROI with time / Net ROI** | (pillar income − capital) ÷ capital; overall Net ROI uses the totals |
| Overhead | General + Self-Improvement + Technology + Travel expenses: shown as its own row and **included in the overall totals** (fixes issue I3) |

### 11.6 Business plan tracking

| Metric | Formula |
|---|---|
| Elapsed fraction | days elapsed in the plan year ÷ days in the year (replaces the 2018 "put a 1 in each month") |
| Projected to date | annual goal × elapsed fraction |
| % of pace | actual YTD ÷ projected to date |
| Year-end forecast | YTD + open prospects × conversion × average closing income + remaining weeks × trailing 8-week run rate |
| Monthly average | total ÷ **months in use** (not 12) |

---

## 12. The Logsperity Index

Prosperity Simplified's proprietary single score (T56; "will be trademarked").

```
Index = 100 × [ ( 0.5 × Net ROI  +  Profit margin ) ÷ 2.5  +  Conversion rate ]
```

| Input | Source | Sample |
|---|---|---|
| Net ROI | §11.5 (with time) | 2.386 |
| Profit margin | §11.5 | 81.9% |
| Conversion rate | §11.3 | 40% |
| **Index** | | **120** |

**How to read it:** 100 is the baseline for a healthy business, defined in the model as **30% conversion,
200% Net ROI and 75% of gross kept**: (0.5 × 2 + 0.75) ÷ 2.5 + 0.3 = 1.00 → **100**. Below 100 is
weaker; above is stronger. The model's scenarios: Weak 80 · Healthy 100 · Strong 150 · Super Strong 230.

**On the Coach screen:** a dial with the index; the three drivers as small bars, each against its healthy
benchmark; the trend by month; and HERB's line: "Your index is 120. The biggest lever is conversion
(40%); Net ROI is held back by Prospecting (1.18)."

> The playground tab (T57) also has an older formula ("Model 1"). This design uses **Model 2** as written
> in T56, scaled ×100 to match "100 is the baseline". Prosperity Simplified should confirm (§21 Q4).
> The formula ships inside the app, so it isn't published as a public formula.

---

## 13. Scorecards (internal)

The 2018 model's 12 scorecard tabs are pivot tables. In the app they are **one generic query**:

```
scorecard(log, measure, dimension, period)
  log:       prospects | closings | income | expenses | activity
  measure:   quantity | income | volume | amount | minutes
  dimension: pillar | subPillar | category | activity | source | irsCategory | month
  period:    month | quarter | YTD | year | custom
```

| 2018 tab | App equivalent |
|---|---|
| 15 Prospects SC Cat Quantity | scorecard(prospects, quantity, category, month) |
| 16 Prospects SC Act Quantity | scorecard(prospects, quantity, activity, month) |
| 26–28 Closings SC Cat Quantity / Income / Volume | scorecard(closings, quantity\|income\|volume, category, month) |
| 29–31 Closings SC Act Quantity / Income / Volume | scorecard(closings, …, activity, month) |
| 32–33 Conversion Rates SC | conversion(dimension) |
| 39 Income (Non-Transaction) SC | scorecard(income where type ≠ transaction, amount, type, month) |
| 45 Expenses Scorecard | scorecard(expenses, amount, category → group → IRS, month) |
| 52 Activity Scorecard | scorecard(activity, minutes, activity → subPillar, month) |

Each scorecard returns rows with month subtotals, sub-pillar subtotals, combined Relationships and
Advertising totals, and a YTD total. That's the same shape the 2018 sheets have.

---

## 14. Reports

### 14.1 Reports menu (S14, T9)

Four groups, as in the 2018 design, plus the Annual Report. Each item can be **viewed**; any number can be
checked and then **printed, emailed or shared as PDF** in one go. On a phone each group is its own page;
on iPad and Mac they share one page.

| Logs | Quick Stats | Detailed Reports | Monthly & YTD |
|---|---|---|---|
| Prospects | Prospects | Prospects Report | January … December (12) |
| Closings | Closings | Conversion Rate Report | Year to Date |
| Income | Profit | Closings Report | |
| Expenses | Current Month | Income Report | |
| Mileage | Annual Report YTD | Expense Report | |
| Activity | Annual Report Streamlined | Mileage Report | |
| All Logs | | Activity Report | |
| | | Input-to-Output Report | |
| | | Profit & Loss (traditional) | |
| | | Relationships & Ads Report | |
| | | Basic Overall Stats | |
| | | Coaching Advice | |
| | | Business Plan Report | |
| | | Logsperity Index | |
| | | Annual Report YTD · Streamlined · Complete | |

Every report has a **period picker** (month, quarter, YTD, year, custom), a **"compare to"** option
(previous period, same period last year, plan) and an **"Explain this" button** that has HERB summarize the report in three sentences.

### 14.2 Report specifications

Report style follows the 2018 Annual Report (§15.1): blue header bars, big serif numbers with the formula
underneath, taupe bars, blue/orange donuts.

| Report | Contents | Charts | 2018 tabs |
|---|---|---|---|
| **Log reports** (×6) | The log as a table; sortable; totals row (count, volume, income, amount, miles, hours) | — | 14, 22, 38, 43, 48, 51 |
| **Prospects Report** | Totals; count and % by Pillar, Category, Activity, Source; top 5 of each; monthly timeline; strength mix | Pie by pillar; bar of top-5 categories and top-5 activities; monthly bars | 17–20 |
| **Closings Report** | Count, volume, income by Pillar/Category/Activity/Source; average volume and income per closing, overall and per pillar/category/activity; top 5 of each; share by pillar for quantity, volume and income | Pie ×3 (quantity, volume, income share); bar of average volume | 23–25 |
| **Conversion Rate Report** | Rate, prospects, closings by Pillar, Category, Activity (catalog order and ranked); no-conversion list | Bars by pillar and category; top-5 activities | 32, 34, 35 |
| **Source Conversion Report** | Sources with conversion (ranked) and sources with none; prospects, closings, rate, income, cost (new) | Bar of top sources | 33, 36 |
| **Income Report** | Total, closing vs non-transaction income; by Pillar/Category/Activity; top 5 by income and by income per closing; monthly; projected annual income | Bars of top-5 categories and activities; monthly bars | 38–40 |
| **Expense Report** | By group and specific category, by IRS category, by month; % share by group; receipts missing | Pie by group | 43, 45, 46 |
| **Mileage Report** | Total miles, rate(s), deduction, average miles per month, estimated hours in the car; trips by reason and destination | Monthly bars | 48, 49 |
| **Activity Report** | Hours by pillar and activity (% share); hourly income rate per activity (income ÷ hours); top 5 | Pie by pillar; bar of hours; bar of $/hour | 51–54 |
| **Efficiency** (part of Activity) | Hours per prospect and per closing by pillar; gross and profit $/h; standard hourly rates; hours per week | 4 bars | 55 |
| **Input-to-Output Report** | Monthly hours in → prospects → closings → income out | Grouped monthly bars | AR p4 |
| **Profit & Loss (traditional)** | Gross receipts; expense lines in IRS order (Advertising, Car & Truck, Commissions, … Other with a Statement 1 itemization); net income | — | 44 |
| **Profit / ROI Report** | Profit and margin overall; per pillar: income, expenses, profit, margin, ROI without time; wages invested, capital, ROI with time; Best/Worst labels **calculated**; overhead row | Pie of profit by pillar; bars of income/expenses/profit | 58, AR p12 |
| **Relationships & Ads Report** | Personal vs Professional, Internet vs Traditional: prospects, closings, conversion, volume, income, hours, wages, expenses, profit | Paired bars | 59 |
| **Basic Overall Stats** | Totals and monthly averages (months in use) for prospects, closings, volume, income, expenses, profit | — | 60 |
| **Business Plan Report** | Current / Projected-to-date / Annual Goal for income, profit, closings, volume, monthly and totals; projected vs actual hourly rates (gross, net) with % | Progress bars; monthly lines | 61, AR p2 |
| **Logsperity Index** | Index, the three drivers vs benchmarks, monthly trend | Dial + trend line | 56 |
| **Coaching Advice** | HERB's advice generated from the numbers (§16.3), with the 2018 guidance as the base | — | 62 |
| **Monthly report** (×12) | Summary page (§15 page 1) for that month + changes vs the previous month | as §15 | T9 |
| **Quick Stats** | One-screen tiles: Prospects (count, conversion), Closings (count, volume, income), Profit (P&L bar), Current Month, Annual YTD | Small charts | T9 |

---

## 15. The Annual Report

The flagship output (AR sample, 13 pages, landscape). Three versions: **Complete** (all sections),
**Streamlined** (summary, plan tracker, top performers, coaching), **YTD** (complete, through today).

### 15.1 Visual style (from the sample)
- Large thin grey title per page ("2027 Prospects Report").
- Widgets in a 3–4 column grid, each with a **royal-blue header bar** (≈ `#2457A8`) and white all-caps label.
- **Big numbers in a dark serif** with a grey caption and the **formula in italics underneath** — "(0.54 = 69.75 / 129)".
- Bars taupe (`#B5ACA5`); donuts periwinkle (`#5B6BBF`) and orange (`#F7A35C`); P&L bar teal (`#8EE8E0`) for profit, orange for expenses.
- Logsperity brand: royal blue `#2B5DA8`, gold `#F9C46B`, near-black `#2A2A2A`; the four QRG icons (column, grid-target, org chart, runner) in the Top Performers widgets.

### 15.2 Sections

| Page | Section | Contents |
|---|---|---|
| 1 | **Complete Report Summary** | P&L stacked bar (profit vs expenses, % and $); conversion donut (closings of prospects); transaction summary (average closing volume and income); efficiency (hours per prospect and per closing); hourly rate (gross and net); YTD volume |
| 2 | **Business Plan Progress Tracker** | Income, Profit, Transactions, Volume: Current vs Projected-to-date vs Goal, with % |
| 3 | **Monthly Averages and Top Performers** | Monthly averages for six key metrics; top Pillar, Category, Source and Activity by conversion, volume and income |
| 4 | **Input-to-Output** | Monthly bars: hours → prospects → closings → income |
| 5 | **Prospects Report** | §14.2 |
| 6 | **Closings Report** | §14.2 |
| 7 | **Income Report** | §14.2, including projected annual income |
| 8 | **Conversion Rate Report** | By pillar, category and activity; converted vs not-converted tables |
| 9 | **Source Conversion** | Same tables for sources |
| 10 | **Mileage Report** | Miles, deduction, hours in the car |
| 11 | **Profit & Loss** | P&L, profit and expenses by pillar, traditional IRS-format P&L |
| 12 | **ROI by Pillar** | Income, expenses, profit, margin, ROI (with and without time); Best/Worst |
| 13 | **Coaching Advice** | HERB's data-driven advice (§16.3) |
| new | **Logsperity Index** | Index with drivers and trend (could be on page 1) |
| new | **HERB's year in review** | One page in plain English: what worked, what didn't, three recommendations for next year's plan |

Generated on the device as a PDF (SwiftUI `ImageRenderer` → PDF), so print, email and share all work
offline, and the CPA gets the same file.

---

## 16. HERB coaching

### 16.1 Coaching loop

```
Business Plan ─► Daily focus ─► Weekly check-in ─► Monthly report ─► Quarterly plan review ─► Annual Report
      ▲                                                                                        │
      └────────────────────────────── next year's plan uses this year's actual rates ◄─────────┘
```

### 16.2 Weekly check-in (default Monday 7:30 am, about 3 minutes, voice or cards)

1. **Score vs plan:** prospects, closings, income, business-building hours for last week and YTD pace.
2. **One win** with its numbers ("Partner Coaching produced 2 prospects from 3 hours").
3. **The biggest gap** and its likely cause.
4. **Last week's commitments:** done or not (checked automatically against the logs).
5. **This week's focus:** the top 3 actions (§16.4); add them to the calendar on approval.
6. **Logsperity Index** change, in one line.

### 16.3 Data-driven coaching rules

The 2018 Coaching Advice page (T62) is general text. HERB turns its guidance into **rules that fire on the
user's actual numbers**:

| Area | 2018 guidance (paraphrased) | HERB rule | Example message |
|---|---|---|---|
| Conversion | Watch a category or activity with 2–3 prospects and no closings; 4+ with none is a concern — maybe avoid it | prospects ≥ 2 & closings = 0 → **watch**; ≥ 4 & 0 → **concern** + action plan | "Door Knocking: 5 prospects, 0 closings. Consider dropping it or changing your approach." |
| Sources | A source sending 4–5 prospects that never convert — time to move on or coach them | source prospects ≥ 4 & closings = 0 | "FTHB seminar list: 4 prospects, none closed. Talk to the organizer or drop it?" |
| Closings | Keep working where you close; look at how to raise the number or size of closings | Top pillar/category by closings and by average volume | "Prospecting closes your biggest deals ($398k average vs $336k overall)." |
| Income | Find the pillars, categories and activities that pay the most per closing | Top income per closing | "Past Clients brought $32,100 from 5 closings — $6,420 each." |
| Activities | Efficiency: lower hours per prospect and per closing is better; move hours to efficient pillars | Pillar hours per closing > 2× the best pillar | "Prospecting takes 36.7 h per closing vs 8.6 h for Clients. Moving 4 h/week could add ~2 closings a year." |
| Profit / ROI | Find the pillars with the highest ROI, with and without time | Lowest ROI-with-time pillar, if < 1.5 | "Advertising returns $1.57 per $1 of time and money; Relationships return $3.88." |
| Plan | — (new) | % of pace < 95% | "You're 8% behind income pace. The smallest fix: 1 more closing by March." |
| Expenses | — (new) | Recurring expense with no linked prospects in 90 days | "You've paid $1,140 for LeadBoost this year with no prospects from it." |
| Logging | — (new) | No entries in 3 business days; meetings without activities | "Three meetings this week have no activity logged — add them?" |

Every message shows the numbers and sample size behind it. When a sample is too small to judge (fewer
than 5 outcomes), HERB calls it an "early signal" and doesn't recommend stopping anything.

### 16.4 "What should I focus on this week to make more money?"

1. **Gather (code):** plan gap, follow-ups due, prospects by strength (Red Hot/Hot first), referral/review
   requests due, best and worst pillars/activities by $/hour and conversion, triggered rules (§16.3).
2. **Score (code):** expected value = estimated income × probability ÷ hours needed; deadlines get a boost.
3. **Choose and explain (on-device model):** the top 3, plus one thing to stop.
4. **Schedule (user):** "Add these to my calendar?"

> **Three things this week:** (1) Call your 4 Red Hot prospects — $26k of potential income.
> (2) Two hours of Past Client Interaction — your best converter at 75%. (3) Ask the Moraleses for a
> review; it's been 14 days since closing. **One to drop:** Saturday's open house — 38 hours this year, 1 closing.

### 16.5 Action plans

When a rule fires with a "concern", HERB offers an action plan: the problem metric, 2–4 steps, a measure and
a review date. Prosperity Simplified's own coaching content can be added as a **library of plays** HERB
picks from (§21 Q6).

---

## 17. Voice commands

"Hey Siri, ask Logsperity…" or in-app "Hi HERB…" (App Intents; see the pilot design §6 for how iOS handles voice).

### 17.1 Commands

| Command | Example | Does |
|---|---|---|
| Log prospect | "New prospect, Kevin Morales, Ruth Alvarez sent him" | §10.1 draft, then follow-up questions (§17.2) |
| Several leads | "I have some leads to record" | One prospect after another until "that's all" |
| Update a contact | "I called Priya Shah, she's not ready, follow up in two weeks" / "Kevin Morales's email is …" | Updates the existing prospect: follow-up, note, phone, email, address, strength |
| Log closing | "Morales closed, 520 thousand, I made 6,500" | §10.2 draft |
| Log income | "Got a 2,000 referral fee from Lakeside" | §10.3 by Type |
| Log expense | "Lunch with Dana, 86 dollars" / "Scan a receipt" | §10.4 |
| Log trip | "Start a business trip" / "I drove to the title company" | §10.5 |
| Log activity | "Two hours of door knocking, got two leads" | §10.6, then offers to add the leads |
| Focus | "What should I focus on this week?" | §16.4 |
| Pace | "Am I on track for my plan?" | §11.6 |
| Conversion | "Which pillar converts best?" / "Which sources never close?" | §11.3 |
| Efficiency | "Where am I wasting time?" | §11.4 |
| ROI | "Which pillar has the best return?" | §11.5 |
| Index | "What's my Logsperity Index?" | §12 |
| Report | "Email me the March report" | Generates the PDF; opens Mail for the user to send |
| Review | "What does HERB need from me?" | Reads the Review queue |

### 17.2 Follow-up questions (conversational capture)

**The problem.** People rarely say everything in one sentence. If HERB only takes what was said, records come
out incomplete (no source, no phone, a guessed category), and the user ends up fixing them by hand on the form,
which defeats the point of voice. So when something is missing, **HERB asks for it, one short question at a time**,
the way a good assistant would, and still **saves nothing until the user says so**.

**Example — the user leaves out the address:**

> **You:** Hi Herb, new prospect, Tom Rodgers, 847-477-0619, follow up next week.
> **HERB:** Got it — Tom Rodgers, mobile (847) 477-0619, follow-up Monday, Nov 2. Do you want to add an address?
> **You:** Yes.
> **HERB:** What's the address?
> **You:** 216 Shadow Creek Lane, Hickory Creek, Texas.
> **HERB:** 216 Shadow Creek Lane, Hickory Creek, TX. Who referred Tom, or where did the lead come from?
> **You:** Ruth Alvarez sent him.
> **HERB:** Tom Rodgers, mobile (847) 477-0619, 216 Shadow Creek Lane, Hickory Creek, TX, from Ruth Alvarez,
> follow-up Monday, Nov 2. Save it?
> **You:** Yes.
> **HERB:** Saved Tom Rodgers. I'll remind you to follow up Monday, Nov 2.

**When the address and the phone are both missing,** HERB groups them into one question: *"Do you want to add an
address and phone number?"* Every answer works:

| The user says | HERB does |
|---|---|
| "Yes" | Asks each one in turn: "What's the address?" … "And the phone number?" |
| "No" | Skips both and moves on |
| "Phone number only" / "Just the phone" / "No address, just the phone" | "What's the phone number?"; the address is not offered again |
| Gives the phone number straight away ("847 477 0619") | Takes it, then asks "Do you want to add the address?" |
| Gives the address straight away | Takes it, then asks "Do you want to add the phone number?" |
| Something unrelated, or unclear | Asks once more ("you can say yes, no, or just tell me"), then moves on |

**The rules HERB follows (the dialog policy):**

1. **Take everything said, in any order.** Phone, email, address (street, city, state, zip), name, source,
   follow-up date, lead strength and loan details are pulled out of the same sentence. Spoken forms work:
   "tom dot rodgers at gmail dot com", "two weeks from now", "520 thousand".
2. **Ask only for what's missing, most important first,** in this order: what the record can't be saved without
   (*required*), then what makes it useful (*recommended*), then nice-to-haves (*thorough*). Each log has its own
   list — see the table below.
3. **One question per turn, short enough to say while driving.** Optional fields that belong together (address,
   phone, email) are offered in one yes/no question instead of three.
4. **Repeat back what was heard** ("Mobile (847) 477-0619.") so mistakes are caught right away, and read the
   whole record back before saving.
5. **Suggest a sensible default the user can accept with "yes":** the follow-up date (hot lead → next business
   day, medium → 3 days, cold → 2 weeks), or the income on a closing (loan amount × the user's own average yield).
6. **Everything can be corrected at any time:** "actually make it Tuesday", "the phone is …", "his last name is
   Rogers", "add a note: prefers text". Skip any optional question with "skip" or "no".
7. **Never trap the user.** "Cancel" discards, "Edit" opens the form with everything filled in, "what?" repeats
   the question, and after two misses HERB moves on, or for a required field suggests the form.
8. **Side questions don't lose the draft.** "Which sources never close?" in the middle of a new prospect gets
   answered, then: "Back to Tom Rodgers: do you want to add the address?"
9. **A new entry waits its turn.** "New prospect Mary Jones" while Tom is still open: "Should I save Tom Rodgers
   as it is first?" — then Mary.
10. **Nothing is saved without "yes / save".** "Finish later" (or "I'm driving") saves what's there to the
    **Review queue** with a note of what's missing ("HERB: still need the address and the source"), so incomplete
    records are never lost and never silently treated as complete.

**What HERB asks for, by log** (R = required, ● = recommended, ○ = Thorough mode only):

| Log | Asked for when missing |
|---|---|
| Prospect | R name (and last name) · R "same person?" if the name already exists · ● address + phone (one offer) · ○ email (joins the offer) · R **source** ("Who referred Tom, or where did the lead come from?"; "I don't know" is accepted — see below) · ● who a **new** source is (realtor, past client, friend or family, other professional — sets the Pillar and Category) · ● follow-up date (default offered) · ○ lead strength · ○ loan purpose and amount |
| Contact update | ● next follow-up date when a call, text or meeting is logged without one |
| Expense | R amount · R what it was for (category) · ● who a meal or gift was with · ● vendor / restaurant · ○ business purpose of a meal |
| Activity | R what kind · R how long · ● who it was with (relationship activities) |
| Income | R amount · R type (commission, referral fee, bonus, consulting) · ● who paid |
| Trip | R miles · ● destination · R business purpose (IRS) |
| Closing | R which client ("which one — Kevin or Ana Morales?" when two match) · R loan amount · R income (estimate offered) |

**The source is required, with "I don't know" as an answer (decision D3).** Logsperity's whole USP is knowing
which sources and activities pay, so a prospect without a source is the most expensive kind of incomplete record.
HERB asks for it on every new prospect, in every question style, unless it already worked it out from what was
said ("Ruth sent him", "from the open house", "Zillow"). The user can't skip it silently, but can say "I don't
know" (or "skip", "no", "nobody, they just called"):

- The source is recorded as **Unknown**. HERB says so ("I'll mark the source unknown and put Tom in your Review
  queue"), and the readback says "source unknown".
- The prospect is saved **unreviewed**, with the note "HERB: still need the source", and waits in the **Review
  queue** as *"Where did Tom Rodgers come from?"*
- Reports show **Unknown** as its own line, so the gap is visible. Coaching never treats Unknown as a source
  ("Unknown never converts" would be meaningless); instead HERB notes how many prospects have no source and points
  to the Review queue.
- Naming a real source later in the same conversation ("actually Ruth sent him") replaces Unknown.

A hard requirement with no way out was rejected: for walk-ins and unknown callers it pushes people to invent a
source, which corrupts the numbers, or to skip logging the lead, which breaks rule R1.

**Other places the same approach is used:**

| Situation | What HERB does |
|---|---|
| **Possible duplicate** | "You already have a Kevin Morales from Oct 27. Is this the same person?" — "same" turns the new details into an update of the existing record instead of a second prospect (keeps conversion honest, rule R5's spirit) |
| **New referral source** | "Sam Lee is new to me. Who is Sam to you — a realtor, a past client…?" so the prospect lands in the right Pillar and Category, and Sam is set up for next time |
| **Activity that produced leads** | "Two hours door knocking, got two leads" → after saving: "Want to add them now?" → "Lead 1 of 2 — what's the name?" with Category, Activity and Source already filled in |
| **Batch of leads** | "I have some leads to record" → one after another, "Next lead?" until "that's all" |
| **Logging a touch on an existing contact** | "I called Priya Shah, left a voicemail" → note "Oct 30: Called — left a voicemail" and "When should you follow up with Priya next?" |
| **Meals** | Asks who it was with (IRS substantiation). "Just me" → a gentle note that solo meals usually aren't deductible unless traveling overnight |
| **Repeat client closing** | Switches to the Income log automatically (rule R4) and says why |
| **Unknown expense category** | Asks; if still unclear, files it under General and puts it in the Review queue instead of guessing silently |

**Question style (user setting, in HERB Autopilot):**

| Style | Asks for |
|---|---|
| Quick | Required fields only (which includes the prospect's source) |
| **Balanced** (default) | Required + recommended |
| Thorough | Everything, including email, lead strength, loan details and meal purpose |

**HERB learns what the user doesn't want to be asked.** If the user skips the same optional field three times in a
row (e.g. addresses), HERB says once: *"I notice you usually skip addresses, so I'll stop asking. You can turn it
back on in HERB Autopilot."* Providing that field later resets the count. Required fields are never dropped.

**Voice turn-taking.** After HERB asks a question it listens for the answer for about 9 seconds **without**
needing "Hi Herb" again (a soft chime marks the window), then goes back to waiting for the wake phrase. On the
iPhone the same applies inside the app and in the Siri / App Intents conversation.

**Architecture.**
- **The dialog state travels with each request:** the draft, what's known, skipped and pending, and the current
  question. The server (in the simulator) stays stateless, and on the iPhone the state simply lives in the app.
- **AI extracts, code decides, AI phrases.** On the iPhone, Apple's on-device Foundation Models fill the record
  from what was said (*guided generation* into the same frame), and can phrase questions more naturally. Which
  question comes next, what is required, the defaults and the "never save without yes" rule stay in plain,
  tested code, so behaviour is predictable and auditable.
- **The simulator** implements this policy in `herb-sim/dialog.py` with rule-based extraction, and
  `herb-sim/tests/test_dialog.py` covers the conversations above.

---

## 18. Data model

SwiftData, synced to the user's own iCloud private database (pilot design §11–12); 🔒 = end-to-end encrypted field.

```swift
// Taxonomy (bundled, versioned; user can add custom items)
enum Pillar: String { case clients, relationships, advertising, prospecting }
enum SubPillar: String { case clients, personal, professional, internet, traditional, prospecting }
@Model final class TaxonomyItem { var id = ""; var kind: TaxonomyKind = .category   // category | activity
    var pillar: Pillar = .clients; var subPillar: SubPillar = .clients
    var name = ""; var hidden = false; var custom = false; var taxonomyVersion = 1 }
@Model final class Source { var name = ""; var normalizedName = ""; var person: Person?; var createdAt = Date.now }

// Shared attribution for prospects, closings, income and activity
struct Attribution: Codable { var pillar: Pillar?; var subPillar: SubPillar?
    var categoryID: String?; var activityID: String?; var sourceID: PersistentIdentifier? }

@Model final class Person { @Attribute(.allowsCloudEncryption) var lastName = ""      // 🔒
    @Attribute(.allowsCloudEncryption) var firstNames = ""                               // 🔒
    @Attribute(.allowsCloudEncryption) var phones: [LabeledValue] = []                   // 🔒
    @Attribute(.allowsCloudEncryption) var emails: [LabeledValue] = []                   // 🔒
    @Attribute(.allowsCloudEncryption) var address: String?                              // 🔒
    var zip: String?; var city: String?; var state: String? }

@Model final class Prospect { var date = Date.now; var person: Person?; var attribution = Attribution()
    var originallyFrom: Source?                       // rule R2
    var strength: Strength = .medium                  // redHot, hot, medium, cold, noGo
    var planOfAction: PlanOfAction?; var followUp: Date?
    @Attribute(.allowsCloudEncryption) var notes: String?
    var closing: Closing?                             // at most one (rule R5)
    var captureSource: CaptureSource = .manual; var reviewed = true }

@Model final class Closing { var date = Date.now; var prospect: Prospect?; var attribution = Attribution()
    var transactionSize: Decimal = 0; var income: Decimal = 0
    var referralRequest: ReferralRequest = .no        // yes, no, askIn(days)
    var postClosingFollowUp: Date?; var notes: String? }

@Model final class IncomeEntry { var date = Date.now; var mode: IncomeMode = .transaction  // transaction, batch, type
    var closing: Closing?; var attribution = Attribution()
    var type: IncomeType?                             // commission, consultingFees, profitSharing, bonuses, baseWages, allowance, referralFees
    var transactionCount: Int?; var amount: Decimal = 0; var payer: String?; var expect1099 = true
    var matchedBankTxnID: String? }

@Model final class Expense { var date = Date.now; var vendor = ""; var amount: Decimal = 0
    var group: ExpenseGroup = .general                // clients, relationships, adInternet, adTraditional, prospecting, general, selfImprovement, technology, travel
    var relationshipSubPillar: SubPillar?             // personal | professional (fixes I4)
    var categoryID = ""                               // Appendix A → irsCategory derived
    var source: Source?; var checkNumber: String?; var cardLast4: String?
    var purpose: String?; var withWhom: String?
    @Attribute(.externalStorage) var receiptImage: Data?
    var matchedBankTxnID: String?; var captureSource: CaptureSource = .manual; var reviewed = true }

@Model final class Trip { var date = Date.now; var reason = ""; var destination = ""
    var odometerStart: Double?; var odometerEnd: Double?; var gpsMiles: Double?
    var isBusiness = true; var activity: ActivityEntry?; var source: Source?
    var miles: Double { gpsMiles ?? max(0, (odometerEnd ?? 0) - (odometerStart ?? 0)) } }

@Model final class ActivityEntry { var date = Date.now; var attribution = Attribution()   // pillar + activity
    var minutes = 0                                   // 15-minute steps
    var notes: String?; var calendarEventID: String?; var captureSource: CaptureSource = .manual; var reviewed = true }

@Model final class BusinessPlan { var year = 2027
    var grossIncomeGoal: Decimal = 0; var netProfitGoal: Decimal = 0
    var avgCommission: Decimal = 0; var avgTransactionSize: Decimal = 0
    var hoursPerWeek: Decimal = 40; var vacationWeeks: Decimal = 0 }   // outputs computed (§9.2)

@Model final class Account { var title: String?; var company: String?; var profession = ""
    var dailyReminder = DateComponents(hour: 17, minute: 30); var mileageUnit: Unit = .miles }

// HERB
@Model final class AutomationRule { var matcher = ""; var field = ""; var value = ""; var confirmations = 0; var level = 2 }
@Model final class CheckIn { var date = Date.now; var scoreJSON = ""; var commitments: [Commitment]? = [] }
@Model final class Commitment { var text = ""; var activityID: String?; var target: Int?; var achieved: Int?; var due = Date.now }
@Model final class ActionPlan { var ruleID = ""; var metric = ""; var baseline = 0.0; var stepsJSON = ""; var reviewDate = Date.now; var result: Double? }
@Model final class Insight { var ruleID = ""; var date = Date.now; var impact: Decimal = 0; var sampleSize = 0; var text = ""; var dismissed = false }
```

Scorecards, analyses, reports and the index are **calculated on demand**; none are stored.

---

## 19. Issues found in the 2018 model

Found while reading the workbook and the sample report. The app calculates everything from the logs, so
most of these go away. Some need a decision (§21).

| # | Issue | Fix in the app |
|---|---|---|
| I1 | Many scorecard and analysis cells are typed values or point at the wrong rows (tabs 17, 20, 34, 44, 46, 53) | Everything calculated from the logs; unit tests built from the 2018 sample data |
| I2 | Traditional P&L (T44) leaves out Meals ($600): net $107,669 vs $107,069 in Profit Analysis | One expense → IRS mapping (Appendix A) used by every report |
| I3 | Pillar ROI leaves out General/Self-Improvement/Technology/Travel expenses ($4,621) and non-transaction income | Show an **overhead** row; include it in overall ROI |
| I4 | Relationship expenses aren't split Personal/Professional, so Personal shows $0 expense | New sub-pillar field on Relationship expenses |
| I5 | Monthly averages divide by 12 even mid-year | Divide by months in use |
| I6 | Business Plan Report marks elapsed months by hand ("put a 1") | Elapsed fraction from the date |
| I7 | Activity names differ between logs ("Relationship Building" vs "…-Personal/-Professional"); typos | One versioned taxonomy with IDs |
| I8 | Sources are free text, so "Zillow" and "zillow.com" count separately | Normalization + "merge sources" + HERB suggestions |
| I9 | The sample report shows 300% conversion for one source | Enforce one closing per prospect (R5) |
| I10 | Two Logsperity Index formulas (Model 1 = 145.8, Model 2 = 1.205 in the sample) | Use Model 2 × 100; confirm (§21 Q4) |
| I11 | Net ROI prices time at actual gross ÷ planned hours, so it partly depends on itself | Keep it for continuity; offer the plan's anticipated hourly rate as a setting |
| I12 | Hours totals disagree slightly (311 / 311.5 / 312) | One calculation |
| I13 | Total work hours: the plan uses 2,080/year; the sample report uses 1,040 for six months | Plan hours × elapsed fraction; optional logged hours |
| I14 | "Marketing for Current Client" activity isn't on any scorecard (T63) | Generic scorecards include every taxonomy item |
| I15 | The "person-based vs place-based sources" counts have no rule | New optional Source type: Person / Company / Venue / Online |
| I16 | Account Set Up collects card numbers | Apple In-App Purchase; no card data in the app |

---

## 20. Roadmap

| Phase | Weeks | Delivers |
|---|---|---|
| **0. Prototype** (no Mac needed) | 1–2 | Clickable web prototype of Today, the six input screens, Reports menu, the Summary page and Coach, filled with the 2018 sample data; reviewed with Prosperity Simplified and the pilot user |
| **1. Core Logsperity** | 3–8 | Account set up, Business Plan, taxonomy, six input screens, six logs, calculation engine (§11) with tests from the 2018 sample, Reports menu, the main reports and PDF export |
| **2. HERB Assistant** | 9–12 | Voice entry, receipt reading, auto-trips, calendar → activities, Review queue, daily review, statement import |
| **3. HERB Analyst & Coach** | 13–16 | Coaching rules (§16.3), weekly check-in, focus-of-the-week, Logsperity Index screen, Annual Report (Complete/Streamlined/YTD), year in review |
| **4. Autopilot & broaden** | 17+ | Level-4 learning, FinanceKit/QuickBooks, profession packs, Prosperity Simplified coaching library, iPad/Mac layouts |

---

## 21. Open questions for Prosperity Simplified

1. **Names:** Logsperity is the app and HERB the coach — correct? Is "HERB" cleared as a trademark?
2. **Existing users:** are people using the Excel model today? Should the app import a workbook?
3. **Platforms:** "smartphone, tablet or computer" — is iPhone/iPad/Mac enough, or are Android, Windows or web required? (That changes the technology choice.)
4. **Logsperity Index:** confirm Model 2 and the ×100 scale; confirm the healthy benchmarks (30% / 200% / 75%).
5. **Pricing:** keep $50/month and $500/year? Is there a cheaper "single log" tier (the USP mentions using one log)? Does HERB coaching cost extra?
6. **Coaching content:** which Prosperity Simplified scripts, plans and plays should HERB use?
7. **Professions:** which profession packs come first after mortgage/real estate? Which categories should each hide or add?
8. **Bank connections:** is statement import acceptable for the pilot, or is a live bank feed required (it needs a server)?
9. **Human coaches:** will Prosperity Simplified coaches see clients' reports? That needs explicit sharing by the user and changes the privacy design.
10. **Mileage rate and units:** confirm IRS rates by date and kilometers for non-US users.

---

## 22. Decision log and pending items

### Decided

| # | Date | Decision | Where it applies |
|---|---|---|---|
| D1 | Oct 30, 2026 | **No card numbers in the app.** The 2018 Account Set Up collected card number, expiration and security code. Logsperity now sells its Monthly ($50) and Annual ($500) plans through **Apple In-App Purchase**: Apple takes payment, renews and refunds, and the app never sees card data. The Account screen shows the plan, status and renewal date, plus a "Manage subscription" link | §8.1, issue I16; built into the simulator's Account screen |
| D2 | Oct 31, 2026 | **HERB asks follow-up questions instead of creating incomplete records.** One short question at a time; optional fields that belong together are offered together ("Do you want to add an address and phone number?"); yes, no, "phone only" or the value itself are all valid answers; nothing is saved without the user's yes; "finish later" parks the entry in the Review queue | §17.2; built into the simulator (`dialog.py`) for every log |
| D3 | Oct 31, 2026 | **The source is required on every new prospect, with "I don't know" as a valid answer.** HERB always asks (all question styles) unless it can tell from what was said. "I don't know" records the source as Unknown and puts the prospect in the Review queue ("Where did Tom Rodgers come from?"). Unknown shows as its own line in reports and is excluded from source coaching. Matches the form, where Source was already required (§10.1) | §17.2, §10.1; built into the simulator |

### Pending — keep in view, not yet decided

| # | Item | Current working assumption | Needs |
|---|---|---|---|
| P1 | **Errors in the 2018 workbook** (§19: typed values, wrong cell references, P&L missing $600 of meals, totals that disagree) | The app calculates everything from the logs, so the errors don't carry over | Prosperity Simplified to confirm the corrected numbers are the intended ones |
| P2 | **Which Logsperity Index formula is official** (Model 1 vs Model 2; 1.205 vs 120.5) | Model 2 × 100, so a healthy business = 100 (§12) | Owner confirmation (§21 Q4) |
| P3 | **"Smartphone, tablet or computer"** — does "computer" mean Windows, Android or the web? | iPhone first; iPad and Mac from the same SwiftUI code | Owner decision (§21 Q3); Windows/web would change the technology choice |
| P4 | **Live bank feed vs statement import** | Statement import (CSV/OFX) for the pilot; no server | Owner decision (§21 Q8); a live feed (Plaid etc.) needs a server and a security program |
| P5 | **CPA review of the expense → IRS mapping** | Appendix A as written in 2018, with notes | CPA review: Referral Fee → Advertising (RESPA §8 risk for mortgage/real estate users), Entertainment (generally not deductible), Meals (generally 50%), Donation (not a Schedule C expense), Bank Charges and Phone placement |
| P6 | **Which fields HERB insists on** (§17.2 table) | Balanced by default; the source is settled (D3) | Owner to confirm the required/recommended split for the other fields in each log |

---

## 23. Windows simulator (before the Mac)

A working simulation of this design runs on Windows today so the screens, numbers and voice can be
tried before the Mac and Xcode are set up. It lives in `herb-sim/` (see `herb-sim/CONTRACT.md` and `herb-sim/README.md`).

| Part | Simulator | Real iPhone app |
|---|---|---|
| Device | Browser page drawn as an iPhone 16 (390 × 844 pt), Dynamic Island, tab bar | SwiftUI on iOS 27 |
| Database | **SQLite** file on the PC (`herb-sim/data/logsperity.db`) | SwiftData on the phone, synced to the user's iCloud |
| Server | Python 3 standard library (nothing to install) | None — everything on the phone |
| Data | Synthetic year for a fictional mortgage broker (seed 42), rebuilt with one click | The user's own entries |
| Calculations | `calc.py` implements §11–§12 with unit tests | Swift port of the same functions and the same tests |
| HERB's answers | Deterministic intent parser + templated replies over the calculations | Apple Foundation Models (on-device) choosing tools; same "code computes, AI narrates" rule |
| Follow-up questions (§17.2) | `dialog.py`: rule-based extraction + the dialog policy; state sent with each request | On-device model extracts into the same frame (guided generation); the same policy, ported to Swift, decides what to ask |
| Voice in | Browser microphone (Edge/Chrome speech service): push-to-talk, or **"Hi Herb" wake word while the page is open** | Speech framework on-device; "Hey Siri, ask Logsperity…", Action Button. iOS doesn't let apps run their own always-on wake word |
| Voice out | Windows voices via the browser | iOS voices |
| Receipt / card scan, GPS trips | Simulated buttons (sample receipt, sample card, simulated GPS miles) | VisionKit, Vision OCR, Core Location |
| Billing | Simulated Apple purchase sheet; no card fields (D1) | Apple In-App Purchase (StoreKit) |

**Moving to the Mac:** Xcode's iOS Simulator runs only on macOS. Claude Code's desktop app on a Mac can build
the app and drive that simulator (see Claude Code's *desktop iOS simulator* documentation). The plan:
1. Create the SwiftUI project.
2. Port `taxonomy.py` and `calc.py` first, along with their tests.
3. Rebuild the screens to match the simulator.
4. Swap the simulated pieces for the real Apple frameworks listed above.

---

## Appendix A — Expense categories and IRS mapping

From T42. The app shows the IRS category read-only once a category is chosen.

| Group | Category → IRS category |
|---|---|
| **Clients** | Database Marketing → Advertising · Client Appreciation Party → Advertising · Client Refund → Other · Closing Gift → Advertising · Entertainment → Meals/Entertainment · Mailers → Advertising · Meal → Meals/Entertainment · Newsletter → Advertising · Printing → Other · Referral Fee → Advertising · Thank You Gifts → Advertising |
| **Relationships** | Database Marketing → Advertising · Entertainment → Meals/Entertainment · Mailers → Advertising · Meal → Meals/Entertainment · Networking Dues → Advertising · Newsletter → Advertising · Printing → Other · Referral Fee → Advertising · Thank You Gifts → Advertising |
| **Advertising-Internet** | Domain Registration, Internet Provider, Website Ad, Web Developer, Web Hosting, Video Production → Advertising |
| **Advertising-Traditional** | Billboard Ad, Car Wrap, Flyer Set Up, Lead Generation, Promotion Set Up, Magazine Ad, Mailers, Mailing Cost, Newsletter, Newspaper Ad, Radio Ad, Signs, Sponsorship, Swag, TV Ad → Advertising · Printing → Other |
| **Prospecting** | Leave Behind Material, Seminar Production, Staging, Trade Show → Advertising · Printing → Other |
| **General** | Bank Charges, Clothing, Donation, Drycleaning, Dues, License, Membership, Phone, Postage, Printing, Subscription → Other · Equipment, Office Fees, Office Supplies, Shipping → Office · Insurance → Insurance · Legal, Professional Services, Tax Preparation → Legal/Professional · Photography → Advertising · Repairs → Repairs · Wages → Wages |
| **Self-Improvement** | Coaching Fees, Marketing Consultant → Legal/Professional · Education, Event, Seminar, Training → Other |
| **Technology** | Data Storage → Office · Internet Provider → Advertising · Software, Technology → Other |
| **Travel** | Car Expenses, Car Wash → Car & Truck · Lodging, Meal, Transportation → Travel · *Mileage deduction → Car & Truck* |

**IRS categories:** Advertising · Car & Truck · Commissions/Fees · Insurance · Interest-Other ·
Legal/Professional · Office · Meals/Entertainment · Rent · Repairs · Supplies · Taxes · Travel · Utilities ·
Wages · Other.

**Needs CPA review before launch:**
- Several 2018 mappings should be checked against current rules. For example, "Referral Fee → Advertising" raises RESPA §8 concerns for mortgage and real estate users. Entertainment is generally no longer deductible. Business meals are generally 50% deductible.
- Charitable "Donation" isn't a Schedule C expense.
- Bank Charges and Phone are better placed under their own lines.

---

## Appendix B — Pick lists

| List | Values |
|---|---|
| **Strength of Contact** (5 colors) | Red Hot · Hot · Medium · Cold · No Go |
| **Plan of Action** | Call · Email · Mail Business Cards · Mail Letter · Mail Information · Mail Promotion · Mail Newsletter · Add to Database · Add to Email Campaign · Add to Phone Campaign · Add to Mail Campaign · Visit · Refer to Other · Refer to Notes · Nothing Now |
| **Follow-Up Date** | 5, 7, 10, 15, 21, 30, 45, 60, 75, 90, 120, 180, 250, 365 days, or pick a date |
| **Request Referral / Review** | Yes · No · Ask in 7 / 14 / 21 / 30 / 45 days |
| **Income types (non-transaction)** | Commission · Consulting Fees · Profit Sharing · Bonuses/Incentives · Base Wages · Allowance · Referral Fees |
| **Mileage reasons** (default list; user can add) | Past/Current/Prospective Client Interaction · Personal Visit · Relationship Building-Personal/-Professional · Community Involvement-Personal/-Professional · Socializing · Networking-Closed/Open Group · Partner Coaching · Committee Involvement · Organization Involvement · Door Knocking · Office Visits · Open Houses · Seminar · Trade Show |
| **Expense No-Pillar groups** | General · Self-Improvement · Technology · Travel |
| **Professions** | Accountant · Appraiser · Architect · Attorney · Banker · Business Coach · Consultant · Contractor · Dentist · Designer · Doctor · Engineer · Escrow Officer · Financial Planner · Insurance Agent · Lender · Realtor · Salesperson · Therapist · Other |
| **Phone type** | Mobile · Work · Home · Other |
