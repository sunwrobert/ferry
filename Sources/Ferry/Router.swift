import AppKit

@MainActor
final class Router: NSObject {
    private var pendingURL: URL?

    func route(_ url: URL, from source: String?) {
        let config = Config.load()
        if NSEvent.modifierFlags.contains(.option) {
            showPicker(for: url, config: config)
            return
        }
        switch Decision.make(for: url, source: source, config: config) {
        case let .open(bundleID, profile, _):
            Browser.find(bundleID)?.open([url], profile: profile)
        case .picker:
            showPicker(for: url, config: config)
        }
    }

    private func showPicker(for url: URL, config: Config) {
        pendingURL = url
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: Self.truncate(url.absoluteString), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for (index, target) in Target.all(hiding: config.hiddenBrowsers ?? []).enumerated() {
            let key = index < 9 ? String(index + 1) : ""
            let item = NSMenuItem(title: target.title, action: #selector(pick(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = []
            item.target = self
            item.image = target.browser.icon
            item.representedObject = target
            menu.addItem(item)
        }

        if let host = RulesMenu.siteHost(url) {
            let always = NSMenuItem(title: "Always Open \(host) In", action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for target in Target.all(hiding: config.hiddenBrowsers ?? []) {
                let choice = NSMenuItem(title: target.title, action: #selector(pickAlways(_:)), keyEquivalent: "")
                choice.target = self
                choice.image = target.browser.icon
                choice.representedObject = target
                choices.addItem(choice)
            }
            always.submenu = choices
            menu.addItem(.separator())
            menu.addItem(always)
        }

        menu.addItem(.separator())
        let copy = NSMenuItem(title: "Copy Link", action: #selector(copyLink), keyEquivalent: "c")
        copy.target = self
        menu.addItem(copy)

        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let url = pendingURL, let target = sender.representedObject as? Target else { return }
        target.browser.open([url], profile: target.profile?.directory)
        pendingURL = nil
    }

    /// Open the link and save a rule so this site skips the picker next time.
    @objc private func pickAlways(_ sender: NSMenuItem) {
        guard let url = pendingURL, let host = RulesMenu.siteHost(url),
              let target = sender.representedObject as? Target else { return }
        RulesMenu.save(rule: Rule(host: host, browser: target.browser.bundleID, profile: target.profile?.directory), at: nil)
        target.browser.open([url], profile: target.profile?.directory)
        pendingURL = nil
    }

    @objc private func copyLink() {
        guard let url = pendingURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        pendingURL = nil
    }

    private static func truncate(_ text: String) -> String {
        text.count > 60 ? String(text.prefix(57)) + "…" : text
    }
}
