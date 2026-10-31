import Foundation

/// Values Prosperity Simplified needs to confirm before the pilot ships.
enum AppConfig {
    // TODO(owner): confirm the support address testers should write to.
    static let supportEmail = "support@prosperitysimplified.com"
    static var supportURL: URL { URL(string: "mailto:\(supportEmail)?subject=Logsperity%20pilot")! }
}
