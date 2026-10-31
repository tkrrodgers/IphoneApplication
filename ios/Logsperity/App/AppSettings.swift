import Foundation

/// Account Set Up (design §8.1) and app preferences. No card fields, ever (decision D1).
struct AppSettings: Codable, Equatable {
    var onboarded = false
    var name = ""
    var title = ""
    var email = ""
    var company = ""
    var phone = ""
    var profession = ""
    var address = ""
    var zip = ""
    var city = ""
    var state = ""
    /// Daily reminder, in minutes after midnight (30-minute steps; default 5:30 pm).
    var reminderMinutes = 17 * 60 + 30
    var remindersOn = false
    /// HERB follow-up question style (§17.2): quick | balanced | thorough.
    var questionStyle = "balanced"
    /// HERB Autopilot style chosen at onboarding (§8.2): handsOn | balanced | max.
    var autopilotStyle = "balanced"
    var herbSpeaks = true
    /// Insight keys the user dismissed on the Coach screen.
    var dismissedInsights: [String] = []
    /// Optional fields the user keeps skipping (§17.2 "HERB learns what the user doesn't want to be asked").
    var herbSkipCounts: [String: Int] = [:]
    /// Fields HERB stopped offering after three skips in a row.
    var herbNeverAsk: [String] = []
    var usingSampleData = false

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? "" }

    var reminderTime: DateComponents { DateComponents(hour: reminderMinutes / 60, minute: reminderMinutes % 60) }

    init() {}

    /// Missing keys keep their defaults, so settings saved by an older build still load after an update.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? d }
        let d = AppSettings()
        onboarded = v(.onboarded, d.onboarded)
        name = v(.name, d.name)
        title = v(.title, d.title)
        email = v(.email, d.email)
        company = v(.company, d.company)
        phone = v(.phone, d.phone)
        profession = v(.profession, d.profession)
        address = v(.address, d.address)
        zip = v(.zip, d.zip)
        city = v(.city, d.city)
        state = v(.state, d.state)
        reminderMinutes = v(.reminderMinutes, d.reminderMinutes)
        remindersOn = v(.remindersOn, d.remindersOn)
        questionStyle = v(.questionStyle, d.questionStyle)
        autopilotStyle = v(.autopilotStyle, d.autopilotStyle)
        herbSpeaks = v(.herbSpeaks, d.herbSpeaks)
        dismissedInsights = v(.dismissedInsights, d.dismissedInsights)
        herbSkipCounts = v(.herbSkipCounts, d.herbSkipCounts)
        herbNeverAsk = v(.herbNeverAsk, d.herbNeverAsk)
        usingSampleData = v(.usingSampleData, d.usingSampleData)
    }
}
