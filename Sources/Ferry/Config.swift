import Foundation

/// A routing rule. Every field that is set must match; the first matching rule wins.
struct Rule: Codable {
    /// Host to match. `github.com` also matches `gist.github.com`. A leading `*.` is ignored.
    var host: String?
    /// Regular expression tested against the full URL.
    var regex: String?
    /// Bundle ID of the app the link was clicked in, e.g. `com.tinyspeck.slackmacgap`.
    var fromApp: String?
    /// Bundle ID of the browser to open, e.g. `com.google.Chrome`.
    var browser: String
    /// Chromium profile directory, e.g. `Default` or `Profile 1`.
    var profile: String?

    func matches(_ url: URL, source: String?) -> Bool {
        if let host, !Self.hostMatches(url.host?.lowercased(), pattern: host.lowercased()) { return false }
        if let fromApp, fromApp != source { return false }
        if let regex {
            guard url.absoluteString.range(of: regex, options: .regularExpression) != nil else { return false }
        }
        return true
    }

    private static func hostMatches(_ host: String?, pattern: String) -> Bool {
        guard let host else { return false }
        let bare = pattern.hasPrefix("*.") ? String(pattern.dropFirst(2)) : pattern
        return host == bare || host.hasSuffix("." + bare)
    }
}

struct Config: Codable {
    /// Browser bundle ID used when no rule matches. `nil` shows the picker.
    var defaultBrowser: String?
    var rules: [Rule]
    /// Browser bundle IDs to leave out of the picker.
    var hiddenBrowsers: [String]?

    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ferry/config.json")

    static let starter = Config(
        defaultBrowser: "com.apple.Safari",
        rules: [
            Rule(host: "meet.google.com", browser: "com.google.Chrome"),
            Rule(fromApp: "com.tinyspeck.slackmacgap", browser: "com.google.Chrome", profile: "Default"),
        ],
        hiddenBrowsers: []
    )

    /// Read from disk on every call: the file is tiny, and edits apply without a reload.
    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL) else {
            starter.save()
            return starter
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            NSLog("Ferry: invalid config, showing picker: \(error)")
            return Config(defaultBrowser: nil, rules: [], hiddenBrowsers: nil)
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("Ferry: failed to save config: \(error)")
        }
    }
}
