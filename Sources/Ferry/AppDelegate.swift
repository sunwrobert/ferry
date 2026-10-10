import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let router = Router()
    private var statusItem: NSStatusItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Ferry")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Local .html files and webloc drops arrive here instead of as URL events.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { router.route($0, from: nil) }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let source = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        router.route(url, from: source)
    }

    // MARK: Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = Config.load()

        let defaultItem = NSMenuItem(title: "Default Browser", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(makeDefaultChoice(title: "Ask Every Time", id: nil, current: config.defaultBrowser))
        submenu.addItem(.separator())
        for browser in Browser.installed() {
            let choice = makeDefaultChoice(title: browser.name, id: browser.bundleID, current: config.defaultBrowser)
            choice.image = browser.icon
            submenu.addItem(choice)
        }
        defaultItem.submenu = submenu
        menu.addItem(defaultItem)

        menu.addItem(makeItem("Edit Rules…", #selector(editConfig), key: ","))
        menu.addItem(.separator())

        if !isSystemDefault {
            menu.addItem(makeItem("Make Ferry the System Browser", #selector(becomeSystemDefault)))
        }
        let login = makeItem("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Ferry", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeDefaultChoice(title: String, id: String?, current: String?) -> NSMenuItem {
        let item = makeItem(title, #selector(setDefault(_:)))
        item.representedObject = id
        item.state = id == current ? .on : .off
        return item
    }

    @objc private func setDefault(_ sender: NSMenuItem) {
        var config = Config.load()
        config.defaultBrowser = sender.representedObject as? String
        config.save()
    }

    @objc private func editConfig() {
        _ = Config.load() // creates the starter file if missing
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", Config.fileURL.path]
        try? process.run()
    }

    private var isSystemDefault: Bool {
        let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        return current.flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
    }

    @objc private func becomeSystemDefault() {
        let me = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: scheme) { error in
                if let error { NSLog("Ferry: could not set default for \(scheme): \(error)") }
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Ferry: launch at login failed: \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
