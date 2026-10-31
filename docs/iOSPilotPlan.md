# Logsperity iPhone pilot — architecture and release plan

| | |
|---|---|
| Goal | A pilot build of Logsperity + HERB that the team installs through **TestFlight**, by email invitation only |
| Based on | `HerbFeaturesDesign.md` v0.4 and the simulator in `herb-sim/` (the reference for every number and every HERB rule) |
| Branch | `ios-pilot` |
| Date | October 31, 2026 |

## 1. Decisions for the pilot

| Decision | Choice | Why |
|---|---|---|
| Minimum iOS | **iOS 26** | Testers who haven't updated to iOS 27 can still install it. Everything the pilot uses exists on iOS 26 |
| Apple Developer account | **Individual** enrollment (Tom Rodgers) | Fastest path to TestFlight. The app can be transferred to a Prosperity Simplified organization account before the public App Store release |
| Testers | **External testers invited by email**, no public link | Only the people you invite can install it. Apple reviews the first build (usually within a day); later builds of the same version usually skip review |
| Bundle ID | `com.prosperitysimplified.logsperity` | Can be changed until the App ID is registered |

## 2. Where this plan differs from the design doc, and why

| Design doc | Pilot | Reason |
|---|---|---|
| HERB runs on Apple's on-device Foundation Models (§6.1, §17.2) | HERB's **rule-based engine, ported from the simulator**, runs on every iPhone. Foundation Models plugs in behind the same interface later, on phones that support Apple Intelligence | Foundation Models needs an iPhone 15 Pro or newer with Apple Intelligence turned on. Not every tester will have that. The rule-based engine is predictable and already covered by tests, and the design's rule "code decides what to ask" stays the same either way |
| Sign in with Apple; Monthly/Annual plans through In-App Purchase (§8.1, D1) | **No sign-in and no purchase in the pilot** | All data stays on the phone and in the user's own iCloud, so there's no Logsperity server to sign in to. Pilot testers aren't charged. In-App Purchase is added before the App Store release (it needs the paid-apps agreement and tax/banking setup in App Store Connect) |
| SwiftData synced to iCloud (§18) | **SwiftData on the phone first; iCloud sync turned on once the developer account exists** | iCloud sync needs an iCloud container registered to the developer account. The data model is written to iCloud's rules from day one (every field optional or defaulted, no unique constraints), so turning sync on later is a setting, not a rewrite |
| Money as `Decimal` (§18) | Money as `Double` dollars, rounded to cents on entry | Matches the simulator's engine, so the ported tests carry over number for number. Sums of a year's entries stay exact to the cent |
| Rule R5 "one closing per prospect" enforced by the database | Enforced in code (`LogRules.checkOneClosing`) | iCloud sync doesn't allow unique constraints |
| Phase 2 automation: receipt scanning, GPS trips, calendar → activities, bank import (§6.3, §20) | **Not in the first pilot build** | These need permissions, background work and careful testing. The pilot proves the logs, numbers, reports and HERB first. They're the next milestone |

## 3. Architecture

```
┌──────────────────────────── Logsperity app (SwiftUI, iOS 26+) ────────────────────────────┐
│  Today · Log · Reports · Coach · More          Ask HERB (text + on-device speech)         │
│        │                                                     │                            │
│  SwiftData store (on the phone; iCloud later)  ── snapshot ──► LogBook (plain values)     │
└────────────────────────────────────────────────────────────────┼──────────────────────────┘
                                                                 ▼
┌──────────────── LogsperityCore (Swift package, no UI, tested with `swift test`) ──────────┐
│  Taxonomy · Day/Period · Ledger (§11) · Index (§12) · Plan tracking · Scorecards (§13)    │
│  Logging rules R2–R6 · Reports → widgets (§14) · HERB intents, coaching, dialog (§16–17)  │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

- **"Code computes, HERB narrates."** Every number comes from `LogsperityCore`. The app only stores entries and draws screens.
- **The engine is a separate Swift package** (`ios/LogsperityCore`). It has no SwiftUI or SwiftData, so it builds
  and tests on any Mac, even without Xcode, and the simulator's Python tests are ported test for test.
- **The Xcode project is generated** from `ios/project.yml` with XcodeGen, so the project file is readable text and
  doesn't cause merge conflicts.

```
ios/
  LogsperityCore/          Swift package: the engine and its tests (./test.sh)
  Logsperity/              the app: SwiftUI screens, SwiftData models, speech
  project.yml              XcodeGen spec → Logsperity.xcodeproj
docs/iOSPilotPlan.md       this file
```

## 4. Pilot scope

**In the pilot**
- First run: Account Set Up (name, profession, reminder time) and Business Plan Set Up with the "This Is Your Business" outputs.
- **Today:** key numbers, this week's focus, follow-ups due, Review queue, Ask HERB.
- **Log:** the six logs (list, add, edit, delete) with the design's rules: filtered pick lists, source autocomplete,
  R2 past-client referrals, R3 additional transactions → income, R4 repeat clients, R5 one closing per prospect,
  R6 odometer default, 15-minute activity steps, IRS category shown for expenses.
- **Reports:** Quick Stats and the main detailed reports (Prospects, Closings, Conversion, Source Conversion, Income,
  Expense, Mileage, Activity, Profit/ROI, P&L, Business Plan, Logsperity Index), with a period picker and Share as PDF.
- **Coach:** Logsperity Index with its drivers, Business Plan tracker, coaching insights (§16.3).
- **HERB:** typed or spoken (on-device speech recognition, push to talk), the follow-up questions of §17.2
  (decisions D2 and D3), "nothing is saved without yes", and answers to the coaching questions. HERB speaks replies.
- **Review queue** and the **daily reminder** notification.
- **Sample data:** "Load a sample year" in More, so testers can explore before they've logged anything.

**After the pilot** (in order): iCloud sync · receipt scanning · GPS trips · calendar → activities · statement import ·
Annual Report PDF (Complete/Streamlined) · weekly check-in · Siri / App Intents · In-App Purchase · iPad layout.

## 5. Milestones

| # | Milestone | Needs | Status |
|---|---|---|---|
| M1 | Engine: taxonomy, periods, ledger, index, plan tracking, scorecards, logging rules + tests | — | **Done** (32 tests) |
| M2 | Engine: report builders and coaching insights + tests | — | Next |
| M3 | Engine: HERB intents, replies and the follow-up dialog, ported with the simulator's dialog tests | — | |
| M4 | App: SwiftData models, the five tabs, the six log forms | **Xcode installed** | |
| M5 | App: Reports and Coach screens, PDF share | Xcode | |
| M6 | App: Ask HERB with speech, Review queue, daily reminder, sample data | Xcode | |
| M7 | Run in the iOS Simulator and on a real iPhone; fix what the team finds | Xcode, an iPhone | |
| M8 | TestFlight: archive, upload, invite testers | **Apple Developer account** | |

## 6. Apple accounts and TestFlight — who does what

| Step | Who | Notes |
|---|---|---|
| 1. Install **Xcode** from the Mac App Store | Tom | Free, large download. Open it once to finish installing components, including the iOS 26 simulator |
| 2. Enroll in the **Apple Developer Program**: <https://developer.apple.com/programs/enroll/> | Tom | Individual, $99/year, with your Apple Account (two-factor authentication on). Approval is often within a day or two |
| 3. Sign in to Xcode with that Apple Account (Xcode → Settings → Accounts) | Tom | Lets Xcode sign builds for your team |
| 4. Register the App ID and create the app record in **App Store Connect** (<https://appstoreconnect.apple.com>) | Claude guides, Tom clicks | Name "Logsperity" (if taken, e.g. "Logsperity by Prosperity Simplified"), bundle ID above, SKU `logsperity-ios` |
| 5. Archive and upload the build (Xcode → Product → Archive → Distribute → TestFlight) | Claude prepares, Tom confirms | Needs the export-compliance answer: the app uses no non-exempt encryption (set in `Info.plist`) |
| 6. Fill in **Test Information** (what to test, feedback email, privacy policy URL) and create the external group "Pilot" | Tom, with drafts from Claude | External testing needs a privacy policy URL and beta review contact details |
| 7. Add testers **by email** to the "Pilot" group; submit for Beta App Review | Tom | Testers get an email, install the TestFlight app and then Logsperity. No public link is created |

## 7. Risks and open items

- **Design §21 questions are still open** (index formula P2, CPA review of the IRS mapping P5). The pilot uses the
  working assumptions in the design doc. Reports label the IRS mapping "for review with your CPA".
- **Privacy policy URL** is required for external TestFlight testing. A one-page policy ("data stays on your iPhone
  and in your iCloud; Prosperity Simplified receives nothing") can be hosted on the Prosperity Simplified website.
- **App name availability** on the App Store is first-come; reserve it as soon as the account is active.
- **Mileage rates** for 2027 must be added to the bundled table once the IRS publishes them (usually December).
