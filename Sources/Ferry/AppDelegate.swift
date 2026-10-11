import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let router = Router()
    private let rulesMenu = RulesMenu()
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
        ProfileAccess.listen()
        AppControl.listen()
        // Refresh the profile cache the CLI reads.
        _ = ChromeProfile.list(for: ProfileAccess.chromeID)
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
        let ask = makeItem("Ask Every Time", #selector(setDefault(_:)))
        ask.state = config.defaultBrowser == nil ? .on : .off
        submenu.addItem(ask)
        submenu.addItem(.separator())
        for target in Target.all(hiding: config.hiddenBrowsers ?? []) {
            let choice = makeItem(target.title, #selector(setDefault(_:)))
            choice.image = target.browser.icon
            choice.representedObject = target
            choice.state = isDefault(target, config) ? .on : .off
            submenu.addItem(choice)
        }
        defaultItem.submenu = submenu
        menu.addItem(defaultItem)

        rulesMenu.build(into: menu, config: config)
        menu.addItem(makeItem("Edit Config File…", #selector(editConfig), key: ","))
        menu.addItem(.separator())

        if ChromeProfile.list(for: ProfileAccess.chromeID).isEmpty,
           NSWorkspace.shared.urlForApplication(withBundleIdentifier: ProfileAccess.chromeID) != nil {
            menu.addItem(makeItem("Allow Access to Chrome Profiles…", #selector(requestProfileAccess)))
        }

        if !AppControl.isSystemBrowser {
            menu.addItem(makeItem("Make Ferry the System Browser", #selector(becomeSystemDefault)))
        }
        let login = makeItem("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = AppControl.isLaunchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Ferry", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func isDefault(_ target: Target, _ config: Config) -> Bool {
        guard target.browser.bundleID == config.defaultBrowser else { return false }
        guard let profile = target.profile else { return config.defaultProfile == nil }
        return config.defaultProfile.flatMap { ChromeProfile.resolve($0, for: target.browser.bundleID) } == profile.directory
    }

    @objc private func setDefault(_ sender: NSMenuItem) {
        let target = sender.representedObject as? Target
        var config = Config.load()
        config.defaultBrowser = target?.browser.bundleID
        config.defaultProfile = target?.profile?.ref
        config.save()
    }

    /// Reading Chrome's data is what makes macOS show the prompt; retry while the user answers it.
    @objc private func requestProfileAccess() {
        ProfileAccess.requestAccess()
    }

    @objc private func editConfig() {
        Config.openInEditor()
    }

    @objc private func becomeSystemDefault() {
        AppControl.becomeSystemBrowser()
    }

    @objc private func toggleLaunchAtLogin() {
        AppControl.setLaunchAtLogin(!AppControl.isLaunchAtLogin)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
