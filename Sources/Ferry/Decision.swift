import Foundation

/// Where a link should go. Shared by the app and `ferry test`.
enum Decision {
    case open(bundleID: String, profile: String?, reason: String)
    case picker(reason: String)

    static func make(for url: URL, source: String?, config: Config) -> Decision {
        if let (index, rule) = config.rules.enumerated().first(where: { $0.element.matches(url, source: source) }) {
            guard Browser.find(rule.browser) != nil else {
                return .picker(reason: "rule \(index + 1) names \(rule.browser), which is not installed")
            }
            return .open(bundleID: rule.browser, profile: rule.profile, reason: "rule \(index + 1)")
        }
        guard let id = config.defaultBrowser else { return .picker(reason: "no rule matched and no default is set") }
        guard Browser.find(id) != nil else { return .picker(reason: "default browser \(id) is not installed") }
        return .open(bundleID: id, profile: config.defaultProfile, reason: "default")
    }
}
