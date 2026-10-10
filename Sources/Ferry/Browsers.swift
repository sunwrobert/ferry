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
                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                return Browser(bundleID: id, name: name, appURL: url)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func find(_ bundleID: String) -> Browser? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return Browser(bundleID: bundleID, name: name, appURL: url)
    }

    func open(_ urls: [URL], profile: String? = nil) {
        if let profile, let executable = Bundle(url: appURL)?.executableURL {
            // Chromium forwards to the running instance and opens the link in that profile.
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--profile-directory=\(profile)"] + urls.map(\.absoluteString)
            do {
                try process.run()
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
                return
            } catch {
                NSLog("Ferry: profile launch failed, opening normally: \(error)")
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
    }
}
