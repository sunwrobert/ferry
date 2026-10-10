import AppKit

/// "Rules" section of the status menu: list, add, retarget, reorder, and delete rules without the CLI.
@MainActor
final class RulesMenu: NSObject {
    func build(into menu: NSMenu, config: Config) {
        let rulesItem = NSMenuItem(title: "Rules (\(config.rules.count))", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, rule) in config.rules.enumerated() {
            submenu.addItem(ruleItem(rule, index: index, count: config.rules.count, hidden: config.hiddenBrowsers ?? []))
        }
        if !config.rules.isEmpty { submenu.addItem(.separator()) }
        submenu.addItem(makeItem("Add Rule…", #selector(addRule), key: "n"))
        rulesItem.submenu = submenu
        menu.addItem(rulesItem)
    }

    // MARK: Menu building

    private func ruleItem(_ rule: Rule, index: Int, count: Int, hidden: [String]) -> NSMenuItem {
        let item = NSMenuItem(title: "\(Self.matchText(rule)) → \(Self.targetText(rule.browser, rule.profile))",
                              action: nil, keyEquivalent: "")
        item.image = Browser.find(rule.browser)?.icon
        let actions = NSMenu()

        let open = NSMenuItem(title: "Open In", action: nil, keyEquivalent: "")
        let targets = NSMenu()
        for target in Target.all(hiding: hidden) {
            let choice = makeItem(target.title, #selector(retarget(_:)))
            choice.image = target.browser.icon
            choice.representedObject = RetargetChoice(index: index, target: target)
            choice.state = Self.isSame(target, rule.browser, rule.profile) ? .on : .off
            targets.addItem(choice)
        }
        open.submenu = targets
        actions.addItem(open)
        actions.addItem(.separator())

        let up = makeItem("Move Up", #selector(moveUp(_:)))
        up.tag = index
        up.isEnabled = index > 0
        actions.addItem(up)
        let down = makeItem("Move Down", #selector(moveDown(_:)))
        down.tag = index
        down.isEnabled = index < count - 1
        actions.addItem(down)
        actions.addItem(.separator())
        let delete = makeItem("Delete", #selector(deleteRule(_:)))
        delete.tag = index
        actions.addItem(delete)

        item.submenu = actions
        return item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func addRule() {
        let config = Config.load()
        let targets = Target.all(hiding: config.hiddenBrowsers ?? [])
        guard let (host, target) = Self.promptForRule(targets: targets) else { return }
        Self.save(rule: Rule(host: host, browser: target.browser.bundleID, profile: target.profile?.directory), at: nil)
    }

    @objc private func retarget(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? RetargetChoice else { return }
        Self.update { config in
            guard config.rules.indices.contains(choice.index) else { return }
            config.rules[choice.index].browser = choice.target.browser.bundleID
            config.rules[choice.index].profile = choice.target.profile?.directory
        }
    }

    @objc private func moveUp(_ sender: NSMenuItem) { Self.move(sender.tag, by: -1) }
    @objc private func moveDown(_ sender: NSMenuItem) { Self.move(sender.tag, by: 1) }

    @objc private func deleteRule(_ sender: NSMenuItem) {
        Self.update { config in
            guard config.rules.indices.contains(sender.tag) else { return }
            config.rules.remove(at: sender.tag)
        }
    }

    // MARK: Shared with the link picker

    /// Add or replace a host rule. A new rule goes first so it beats broader ones.
    static func save(rule: Rule, at index: Int?) {
        update { $0.upsert(rule, at: index ?? 0) }
    }

    /// Host without `www.`, so a rule made from a link covers the whole site.
    static func siteHost(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: Helpers

    private static func update(_ change: (inout Config) -> Void) {
        var config = Config.load()
        change(&config)
        config.save()
    }

    private static func move(_ index: Int, by offset: Int) {
        update { config in
            let destination = index + offset
            guard config.rules.indices.contains(index), config.rules.indices.contains(destination) else { return }
            config.rules.swapAt(index, destination)
        }
    }

    private static func promptForRule(targets: [Target]) -> (String, Target)? {
        let alert = NSAlert()
        alert.messageText = "Add Rule"
        alert.informativeText = "Links to this site and its subdomains open in the chosen browser."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 32, width: 300, height: 24))
        field.placeholderString = "youtube.com"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26), pullsDown: false)
        for target in targets {
            popup.addItem(withTitle: target.title)
            popup.lastItem?.image = target.browser.icon
        }
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        stack.addSubview(field)
        stack.addSubview(popup)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let host = normalizeHost(field.stringValue)
        guard !host.isEmpty, targets.indices.contains(popup.indexOfSelectedItem) else { return nil }
        return (host, targets[popup.indexOfSelectedItem])
    }

    /// Accept a pasted URL or a bare host.
    private static func normalizeHost(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: trimmed), url.host != nil { return siteHost(url) ?? trimmed }
        return trimmed.split(separator: "/").first.map(String.init) ?? trimmed
    }

    private static func matchText(_ rule: Rule) -> String {
        [rule.host, rule.regex.map { "/\($0)/" }, rule.fromApp.map { "from \(appName($0))" }]
            .compactMap { $0 }
            .joined(separator: " + ")
    }

    static func targetText(_ bundleID: String, _ profile: String?) -> String {
        let name = Browser.find(bundleID)?.name ?? bundleID
        guard let profile else { return name }
        let profileName = ChromeProfile.list(for: bundleID).first { $0.directory == profile }?.name ?? profile
        return "\(name) – \(profileName)"
    }

    private static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private static func isSame(_ target: Target, _ bundleID: String, _ profile: String?) -> Bool {
        guard target.browser.bundleID == bundleID else { return false }
        guard let profile else { return target.profile == nil }
        return ChromeProfile.resolve(profile, for: bundleID) == target.profile?.directory
    }
}

private struct RetargetChoice {
    let index: Int
    let target: Target
}
