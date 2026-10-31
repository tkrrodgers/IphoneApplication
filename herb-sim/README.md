# Logsperity + HERB — Windows simulator

A working simulation of the Logsperity iPhone app with the HERB AI coach. It's drawn as an iPhone 16 in your
browser, backed by a SQLite database filled with a synthetic year of data. You can talk to HERB and
HERB talks back.

Design: `../HerbFeaturesDesign.md` (v0.4). Architecture and API: `CONTRACT.md`.

## Start it

1. On Windows, double-click **`run.bat`**, or run:
   ```
   python server.py
   ```
   On a Mac, run `python3 server.py` from this folder in Terminal.
2. Open **http://localhost:8765** in **Microsoft Edge** or **Google Chrome**. Those two browsers support the microphone.
3. The first time, click **Allow** when the browser asks to use the microphone.

Needs only Python 3.10 or newer. No packages, no PostgreSQL. On the first run it creates the database with the
synthetic data. On a Mac, install Python from python.org if `python3 --version` shows an older version.

## Talk to HERB

- **"Hi Herb" wake word:** click **Listen for "Hi Herb"** in the right-hand panel, then say, for example:
  - "Hi Herb, what should I focus on this week?"
  - "Hi Herb … who do I need to follow up with?" (pause after "Hi Herb" and HERB waits for your question)
- **Push to talk:** tap the big mic in the HERB sheet, or click **Push to talk**.
- **Typing:** works in any browser.
- **When you leave something out, HERB asks** (design §17.2), one question at a time. Answer with yes, no,
  "phone only", or just say the value. You can also say "actually make it Tuesday", "skip", "edit", "cancel",
  "what?" or "finish later". Nothing is saved until you say yes. In wake-word mode, after HERB asks a question
  you can answer for about 9 seconds without saying "Hi Herb" again (listen for the chime).
- **Question style:** More → HERB Autopilot → Follow-up questions (Quick, Balanced or Thorough).
- **Where a prospect came from is always asked** (design D3). "I don't know" is fine: the source is saved as
  Unknown and the prospect waits in the Review queue ("Where did Tom Rodgers come from?").

Things to try:

| Say | HERB does |
|---|---|
| "New prospect Tom Rodgers, 847-477-0619, follow up next week" | "Do you want to add an address?", then asks who referred Tom, then reads it back to save |
| "New prospect Tom Rodgers, follow up next week" → "phone number only" | "What's the phone number?" — and doesn't offer the address again |
| "I spent 45 dollars" | Asks what it was for, who the meal was with, which restaurant |
| "Two hours of door knocking, got two leads" | Saves the time, then "Lead 1 of 2 — what's the name?" |
| "I called Priya Shah, she's not ready yet" | Adds a note to Priya and asks when to follow up next |
| "I have some leads to record" | One lead after another until "that's all" |
| "The Morales loan closed" | Asks the loan amount and offers an income estimate |
| "Am I on track for my plan?" / "What's my Logsperity Index?" | Answers from the calculation engine |
| "Which sources never close?" / "Where am I wasting time?" | Coaching answers (also works mid-entry; HERB comes back to the question) |

The microphone uses the browser's speech service: Edge sends audio to Microsoft, Chrome to Google. That's
fine for synthetic data. The real iPhone app recognizes speech on the device.

## What's in the app

- **Today:**
  - Ask HERB
  - Key numbers
  - Review queue (things HERB logged on its own)
  - This week's focus
  - Follow-ups
  - HERB noticed
  - Quick add
- **Log:** the six logs. Each has a list, search, period filter, and add/edit/delete screens with every field from design §10. Pillar-filtered categories and activities, remembered sources, multi-row expenses, trips and activities.
- **Reports:** the menu in four groups. Every report has a period picker, Print/PDF, Email and Explain (HERB). There's also the Annual Report in Complete, Streamlined and YTD versions.
- **Coach:**
  - Logsperity Index dial
  - Plan pace
  - This week's focus
  - Insights
  - Weekly check-in, spoken by HERB
- **More:**
  - Account & subscription (Apple billing, **no card fields**)
  - Business Plan Set Up
  - Input Cheat Sheet
  - HERB Autopilot: follow-up question style and automation levels
  - Help
  - Data & privacy
  - Reset synthetic data

**Simulated, not real:**
- Receipt reading ("Scan sample")
- Business-card scan
- GPS trips
- Apple purchase sheet
- Email (opens your mail app with the report text)

## Data

- Database: `data/logsperity.db` (SQLite). To rebuild it, use **More → Reset synthetic data**, or run `python seed.py --reset`.
- The synthetic data covers one year for "Marcus Reed", a fictional Denton, TX mortgage broker. All people are fictional.
- Today is the real date by default. To change it: `set SIM_TODAY=2026-12-31` before `python server.py`.

## Tests

```
python -m unittest discover -s tests
```

## Moving to the Mac

Xcode's iOS Simulator runs only on macOS. On the MacBook:
1. Install Xcode from the App Store and turn on Apple Intelligence (System Settings → Apple Intelligence & Siri).
   The Simulator uses the Mac's on-device model for HERB.
2. Clone this repository, then run this simulator once with `python3 server.py` to have the reference next to Xcode.
3. Create the SwiftUI project.
4. Port `taxonomy.py` and `calc.py` first, along with their tests, then `dialog.py` (follow-up questions).
5. Rebuild these screens.
6. Test on an iPhone 15 Pro or newer for the microphone, GPS trips, receipt scanning and the real speed of on-device AI.

The API and calculation rules here are the reference the Swift code follows.
