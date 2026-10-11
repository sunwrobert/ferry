import AppKit

/// Lets the CLI ask the menu bar app to read Chrome profiles. macOS attributes a terminal command's
/// file access to the terminal, so only the app itself can trigger Ferry's own permission prompt.
enum ProfileAccess {
    static let chromeID = "com.google.Chrome"
    private static let request = Notification.Name("com.sunwrobert.ferry.refreshProfiles")
    private static let reply = Notification.Name("com.sunwrobert.ferry.profilesRefreshed")

    /// App side: answer refresh requests, asking the user for access first if needed.
    @MainActor
    static func listen() {
        DistributedNotificationCenter.default().addObserver(forName: request, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { requestAccess() }
        }
    }

    private static let bookmarkKey = "chromeDataBookmark"

    /// The app's own defaults; the CLI (same binary, no bundle) reads them by suite name.
    private static var defaults: UserDefaults? {
        Bundle.main.bundleIdentifier == AppControl.bundleID ? .standard : UserDefaults(suiteName: AppControl.bundleID)
    }
    private static var isAsking = false

    /// Reads profiles, or asks the user to grant access to Chrome's data folder through an Open panel.
    /// Choosing a folder in an Open panel counts as consent, so no privacy prompt or certificate is needed.
    @MainActor
    static func requestAccess() {
        if !ChromeProfile.list(for: chromeID).isEmpty || isAsking {
            if !isAsking { answer() }
            return
        }
        isAsking = true
        defer {
            isAsking = false
            answer()
        }

        let folder = ChromeProfile.defaultDataFolder(for: chromeID)
        let panel = NSOpenPanel()
        panel.message = "Ferry needs to read your Chrome profile names. Click Grant Access to allow it."
        panel.prompt = "Grant Access"
        panel.directoryURL = folder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("Local State").path) else {
            let alert = NSAlert()
            alert.messageText = "That isn't Chrome's data folder"
            alert.informativeText = "Choose \(folder.path) and click Grant Access."
            alert.runModal()
            return
        }
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults?.set(bookmark, forKey: bookmarkKey)
        }
        _ = ChromeProfile.list(for: chromeID)
    }

    /// Chrome's data folder from the saved grant, if any.
    static func grantedFolder() -> URL? {
        guard let data = defaults?.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    @MainActor
    private static func answer() {
        let count = ChromeProfile.list(for: chromeID).count
        DistributedNotificationCenter.default().postNotificationName(reply, object: String(count), userInfo: nil, deliverImmediately: true)
    }

    /// CLI side: launch the app if needed, ask it to read profiles, and wait while the user answers the prompt.
    static func requestFromApp(timeout: TimeInterval = 600) -> Bool {
        if !ChromeProfile.list(for: chromeID).isEmpty { return true }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.sunwrobert.ferry") else {
            FileHandle.standardError.write(Data("ferry: Ferry.app is not installed\n".utf8))
            return false
        }

        let answered = Reply()
        let observer = DistributedNotificationCenter.default().addObserver(forName: reply, object: nil, queue: nil) { note in
            answered.set(note.object as? String)
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        FileHandle.standardError.write(Data(
            "ferry: Ferry.app needs access to Chrome's profiles. In the window that opens, click Grant Access (waiting up to \(Int(timeout))s)…\n".utf8))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        // Send until the app is up; it replies once profiles are readable or it gives up.
        answered.wait(timeout: timeout, posts: 1) {
            DistributedNotificationCenter.default().postNotificationName(
                request, object: nil, userInfo: nil, deliverImmediately: true)
        }
        return !ChromeProfile.list(for: chromeID).isEmpty
    }
}
