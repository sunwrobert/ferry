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
        if let rule = config.rules.first(where: { $0.matches(url, source: source) }),
           let browser = Browser.find(rule.browser) {
            browser.open([url], profile: rule.profile)
            return
        }
        if let id = config.defaultBrowser, let browser = Browser.find(id) {
            browser.open([url])
            return
        }
        showPicker(for: url, config: config)
    }

    private func showPicker(for url: URL, config: Config) {
        pendingURL = url
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: Self.truncate(url.absoluteString), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for (index, browser) in Browser.installed(hiding: config.hiddenBrowsers ?? []).enumerated() {
            let key = index < 9 ? String(index + 1) : ""
            let item = NSMenuItem(title: browser.name, action: #selector(pick(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = []
            item.target = self
            item.image = browser.icon
            item.representedObject = browser.bundleID
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let copy = NSMenuItem(title: "Copy Link", action: #selector(copyLink), keyEquivalent: "c")
        copy.target = self
        menu.addItem(copy)

        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let url = pendingURL, let id = sender.representedObject as? String,
              let browser = Browser.find(id) else { return }
        browser.open([url])
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
