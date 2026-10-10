import AppKit

struct Browser {
    let bundleID: String
    let name: String
    let appURL: URL

    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    /// Every installed app that can open https links, except Ferry.
    static func installed(hiding hidden: [String] = []) -> [Browser] {
        let probe = URL(string: "https://example.com")!
        let ownID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .compactMap { url -> Browser? in
                guard let id = Bundle(url: url)?.bundleIdentifier,
                      id != ownID, !hidden.contains(id), seen.insert(id).inserted else { return nil }
                return Browser(bundleID: id, name: displayName(url), appURL: url)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func find(_ bundleID: String) -> Browser? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return Browser(bundleID: bundleID, name: displayName(url), appURL: url)
    }

    /// `profile` may be a Chrome folder name, display name, or email.
    func open(_ urls: [URL], profile: String? = nil) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard let profile else {
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
            return
        }
        // Same as `open -na Chrome --args`: the new instance hands the link to the running one
        // in the requested profile, then exits.
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--profile-directory=\(ChromeProfile.resolve(profile, for: bundleID))"]
            + urls.map(\.absoluteString)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error { NSLog("Ferry: profile launch failed: \(error)") }
        }
    }

    private static func displayName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// One pickable destination: a browser, or one profile of a Chromium browser.
struct Target {
    let browser: Browser
    let profile: ChromeProfile?

    var title: String {
        guard let profile else { return browser.name }
        let email = profile.email.map { " (\($0))" } ?? ""
        return "\(browser.name) – \(profile.name)\(email)"
    }

    /// Browsers with readable profiles are expanded into one target per profile.
    static func all(hiding hidden: [String] = []) -> [Target] {
        Browser.installed(hiding: hidden).flatMap { browser -> [Target] in
            let profiles = ChromeProfile.list(for: browser.bundleID)
            if profiles.isEmpty { return [Target(browser: browser, profile: nil)] }
            return profiles.map { Target(browser: browser, profile: $0) }
        }
    }
}
