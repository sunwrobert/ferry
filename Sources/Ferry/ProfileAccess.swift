import AppKit

/// Lets the CLI ask the menu bar app to read Chrome profiles. macOS attributes a terminal command's
/// file access to the terminal, so only the app itself can trigger Ferry's own permission prompt.
enum ProfileAccess {
    static let chromeID = "com.google.Chrome"
    private static let request = Notification.Name("com.sunwrobert.ferry.refreshProfiles")
    private static let reply = Notification.Name("com.sunwrobert.ferry.profilesRefreshed")

    /// App side: answer refresh requests once profiles are readable or the user had time to answer.
    @MainActor
    static func listen() {
        DistributedNotificationCenter.default().addObserver(forName: request, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { readUntilAllowed(attemptsLeft: 60) }
        }
    }

    /// The first failed read shows the macOS prompt without blocking, so keep retrying while it is on screen.
    @MainActor
    private static func readUntilAllowed(attemptsLeft: Int) {
        let count = ChromeProfile.list(for: chromeID).count
        guard count == 0, attemptsLeft > 0 else {
            DistributedNotificationCenter.default().postNotificationName(
                reply, object: String(count), userInfo: nil, deliverImmediately: true)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated { readUntilAllowed(attemptsLeft: attemptsLeft - 1) }
        }
    }

    /// CLI side: launch the app if needed, ask it to read profiles, and wait while the user answers the prompt.
    static func requestFromApp(timeout: TimeInterval = 90) -> Bool {
        if !ChromeProfile.list(for: chromeID).isEmpty { return true }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.sunwrobert.ferry") else {
            FileHandle.standardError.write(Data("ferry: Ferry.app is not installed\n".utf8))
            return false
        }

        var answered = false
        let observer = DistributedNotificationCenter.default().addObserver(forName: reply, object: nil, queue: nil) { _ in
            answered = true
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        FileHandle.standardError.write(Data(
            "ferry: asking Ferry.app to read Chrome profiles. If macOS asks, click Allow (waiting up to \(Int(timeout))s)…\n".utf8))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        // Send until the app is up; it replies once profiles are readable or it gives up.
        let deadline = Date().addingTimeInterval(timeout)
        var nextPost = Date()
        var sends = 0
        while !answered, Date() < deadline {
            if Date() >= nextPost, sends < 5 {
                DistributedNotificationCenter.default().postNotificationName(
                    request, object: nil, userInfo: nil, deliverImmediately: true)
                sends += 1
                nextPost = Date().addingTimeInterval(1)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !ChromeProfile.list(for: chromeID).isEmpty
    }
}
