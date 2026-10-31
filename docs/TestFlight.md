# TestFlight pilot — what to enter in App Store Connect

Drafts for the fields App Store Connect asks for when you set up external testing. Edit freely.

## App record (App Store Connect → Apps → +)

| Field | Value |
|---|---|
| Platform | iOS |
| Name | Logsperity (if taken: "Logsperity by Prosperity Simplified") |
| Primary language | English (U.S.) |
| Bundle ID | `com.prosperitysimplified.logsperity` |
| SKU | `logsperity-ios` |
| User access | Full access |

## TestFlight → Test Information

**Beta App Description**

> Logsperity helps sales professionals know their numbers. Log prospects, closings, income, expenses, mileage and
> business-building time in about a minute a day, and see conversion rates, hourly rates, ROI by pillar and the
> Logsperity Index. HERB, the built-in coach, logs entries from what you say or type, asks for anything missing,
> and tells you what to focus on this week.

**What to Test** (shown to testers with each build)

> Thanks for piloting Logsperity! Please try:
> 1. First run: set up your account and business plan (or tap "Explore with a sample year first").
> 2. Log a week of real work: prospects, a closing, income, expenses, trips and activity time.
> 3. Ask HERB by voice or text, e.g. "New prospect Kevin Morales, 940-555-0137, Ruth Alvarez sent him" or
>    "Am I on track for my plan?" Check that HERB asks for what's missing and saves only when you say yes.
> 4. Open Reports and Coach. Do the numbers match what you expect?
>
> To send feedback, take a screenshot in the app and tap Share Beta Feedback, or open TestFlight → Logsperity → Send Beta Feedback.
> Your logs stay on your iPhone; we can't see them unless you send them to us.

**Feedback Email**: the Prosperity Simplified support address (see `ios/Logsperity/App/AppConfig.swift`).

**Marketing URL** (optional) and **Privacy Policy URL** (required for external testing): host `docs/privacy-policy.md`
on the Prosperity Simplified website, or turn on GitHub Pages for this repository.

**Beta App Review Information**: contact name, phone and email for Apple's reviewer. No sign-in is required, so
leave "Sign-in required" unchecked. Notes for the reviewer:

> No account or sign-in is needed. On first launch, tap "Explore with a sample year first" to see the app with
> fictional data. The microphone is used only when the user taps the mic in "Ask HERB".

## Export compliance

The app's Info.plist sets `ITSAppUsesNonExemptEncryption = NO` (it uses no encryption beyond Apple's own), so
uploads skip the export-compliance question.

## External group

TestFlight → External Testing → **+** → group name "Pilot". Add testers by email (**not** a public link), so only
the people you invite can install it. Submit the first build for Beta App Review; once approved, testers get an
email invitation.
