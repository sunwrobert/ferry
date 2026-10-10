import AppKit
import ServiceManagement

/// Settings that only the app bundle itself can change (login item, system browser).
/// The menu calls these directly; the CLI forwards them to the running app.
@MainActor
enum AppControl {
    nonisolated static let bundleID = "com.sunwrobert.ferry"

    static var isSystemBrowser: Bool {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        return handler.flatMap { Bundle(url: $0)?.bundleIdentifier } == bundleID
    }

    static var isLaunchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS asks the user to confirm the change.
    static func becomeSystemBrowser() {
        guard let me = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: scheme) { error in
                if let error { NSLog("Ferry: could not set default for \(scheme): \(error)") }
            }
        }
    }

    static func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            if isEnabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Ferry: launch at login failed: \(error)")
        }
    }

    // MARK: CLI channel

    nonisolated private static let request = Notification.Name("com.sunwrobert.ferry.command")
    nonisolated private static let reply = Notification.Name("com.sunwrobert.ferry.commandDone")

    enum Command: String {
        case loginOn = "login-on"
        case loginOff = "login-off"
        case systemBrowser = "system-browser"
        case status
    }

    /// App side.
    static func listen() {
        DistributedNotificationCenter.default().addObserver(forName: request, object: nil, queue: .main) { note in
            let text = note.object as? String
            MainActor.assumeIsolated {
                switch text.flatMap(Command.init(rawValue:)) {
                case .loginOn: setLaunchAtLogin(true)
                case .loginOff: setLaunchAtLogin(false)
                case .systemBrowser: becomeSystemBrowser()
                case .status, nil: break
                }
                let state = "login=\(isLaunchAtLogin)"
                DistributedNotificationCenter.default().postNotificationName(
                    reply, object: state, userInfo: nil, deliverImmediately: true)
            }
        }
    }

    /// CLI side: launch the app if needed, run the command there, and return its reply
    /// (`login=true|false`), or nil on timeout.
    nonisolated static func send(_ command: Command, timeout: TimeInterval = 10) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        var answer: String?
        let observer = DistributedNotificationCenter.default().addObserver(forName: reply, object: nil, queue: nil) { note in
            answer = note.object as? String
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        let deadline = Date().addingTimeInterval(timeout)
        var nextPost = Date()
        while answer == nil, Date() < deadline {
            if Date() >= nextPost {
                DistributedNotificationCenter.default().postNotificationName(
                    request, object: command.rawValue, userInfo: nil, deliverImmediately: true)
                // Repeats only reach the app before it is listening; every command is idempotent anyway.
                nextPost = Date().addingTimeInterval(1)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return answer
    }

    nonisolated static func quit() -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.forEach { $0.terminate() }
        return !running.isEmpty
    }
}
