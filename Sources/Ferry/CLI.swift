import AppKit
import Swiftcur

/// Command-line interface for people and agents, built on swiftcur.
/// Every command returns structured data, so `--json`, `--llms`, `--mcp`, and `skills add` work for free.
enum FerryCLI {
    static let version = "0.2.0"

    static func make() -> CLI {
        CLI(
            "ferry",
            description: "Route links to the right browser and Chrome profile",
            version: version,
            sync: SyncOptions(
                cwd: resourcesPath,
                depth: 0,
                include: ["skills/*"],
                suggestions: ["open YouTube in my personal Chrome profile", "send Devin links to my work profile"]
            ),
            mcp: McpOptions(instructions: "Run browsers first to get real browser and profile names. Never invent a profile name.")
        )
        .command("setup", setup)
        .command("browsers", browsers)
        .command("config", config)
        .command("default", setDefault)
        .command("rules", rules)
        .command("add", add)
        .command("remove", remove)
        .command("move", move)
        .command("set", retarget)
        .command("test", test)
        .command("open", open)
        .command("status", status)
        .command("system-browser", systemBrowser)
        .command("login", login)
        .command("edit", edit)
        .command("quit", quit)
    }

    /// `Ferry.app/Contents/Resources`, found through the symlink in `~/.local/bin`.
    private static var resourcesPath: String? {
        guard let executable = Bundle.main.executablePath else { return nil }
        return URL(fileURLWithPath: executable).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources").path
    }

    private static let readOnly = ToolExposure.annotations(ToolAnnotations(readOnlyHint: true))

    // MARK: Read commands

    static let browsers = Command(
        description: "List browsers and their Chrome profiles; the names work in every other command",
        mcp: readOnly
    ) { _ in
        _ = ProfileAccess.requestFromApp()
        let list: [JSON] = Browser.installed().map { browser in
            let profiles = ChromeProfile.list(for: browser.bundleID).map { profile -> JSON in
                ["name": .string(profile.name), "directory": .string(profile.directory), "email": profile.email.map(JSON.string) ?? nil]
            }
            return ["name": .string(browser.name), "bundleID": .string(browser.bundleID), "profiles": .array(profiles)]
        }
        let unreadable = Browser.installed().contains { ChromeProfile.supports($0.bundleID) && ChromeProfile.list(for: $0.bundleID).isEmpty }
        return .ok(["browsers": .array(list)], cta: unreadable ? [Cta("setup", description: "allow access to Chrome profiles")] : nil)
    }

    static let config = Command(
        description: "Show the default browser and rules",
        options: ["path": .boolean.default(false).describe("Print only the config file path")],
        mcp: readOnly
    ) { context in
        if context.options["path"] == true { return .ok(.string(Config.fileURL.path)) }
        let config = Config.load()
        return .ok([
            "path": .string(Config.fileURL.path),
            "default": .string(describe(config.defaultBrowser, config.defaultProfile) ?? "ask every time"),
            "rules": rulesJSON(config),
        ])
    }

    static let rules = Command(description: "List rules in match order (first match wins)", mcp: readOnly) { _ in
        .ok(["rules": rulesJSON(Config.load())])
    }

    static let test = Command(
        description: "Show where a link would open, without opening it",
        args: ["url": .string.describe("Link to check")],
        options: ["fromApp": .string.optional().describe("App the link is clicked in (name or bundle ID)")],
        examples: [Example(args: [("url", "https://www.youtube.com/watch?v=x")])],
        mcp: readOnly
    ) { context in
        try route(context, open: false)
    }

    static let open = Command(
        description: "Route a link for real",
        args: ["url": .string.describe("Link to open")],
        options: ["fromApp": .string.optional().describe("App the link is clicked in (name or bundle ID)")]
    ) { context in
        try route(context, open: true)
    }

    static let status = Command(description: "System browser, launch at login, and profile access", mcp: readOnly) { _ in
        guard let reply = AppControl.send(.status) else { return notResponding }
        let profiles = ChromeProfile.list(for: ProfileAccess.chromeID)
        var cta: [Cta] = []
        if !isSystemBrowser { cta.append(Cta("system-browser", description: "route clicked links through Ferry")) }
        if profiles.isEmpty { cta.append(Cta("setup", description: "allow access to Chrome profiles")) }
        return .ok([
            "systemBrowser": .bool(isSystemBrowser),
            "launchAtLogin": .bool(reply == "login=true"),
            "chromeProfiles": .array(profiles.map { .string($0.name) }),
            "config": .string(Config.fileURL.path),
        ], cta: cta.isEmpty ? nil : CtaBlock(commands: cta))
    }

    // MARK: Rule commands

    static let setDefault = Command(
        description: "Set where links go when no rule matches",
        args: ["browser": .string.optional().describe("Browser name or bundle ID")],
        options: [
            "profile": .string.optional().describe("Chrome profile: display name, email, or folder"),
            "ask": .boolean.default(false).describe("Show the picker instead of a default browser"),
        ],
        examples: [Example(args: [("browser", "chrome")], options: [("profile", "Personal")]), Example(options: [("ask", true)])]
    ) { context in
        var config = Config.load()
        if context.options["ask"] == true {
            config.defaultBrowser = nil
            config.defaultProfile = nil
        } else {
            guard let name = context.args["browser"]?.stringValue else {
                return .error(code: "MISSING_BROWSER", message: "Pass a browser, or --ask to show the picker.", cta: ["browsers"])
            }
            let profile = context.options["profile"]?.stringValue
            switch resolveTarget(browser: name, profile: profile) {
            case .failure(let failure): return failure.response
            case .success(let target):
                config.defaultBrowser = target.bundleID
                config.defaultProfile = target.profile
            }
        }
        config.save()
        return .ok(["default": .string(describe(config.defaultBrowser, config.defaultProfile) ?? "ask every time")])
    }

    static let add = Command(
        description: "Add a rule; a rule with the same match replaces the old one",
        options: [
            "browser": .string.describe("Browser name or bundle ID"),
            "profile": .string.optional().describe("Chrome profile: display name, email, or folder"),
            "host": .string.optional().describe("Site to match; subdomains included"),
            "regex": .string.optional().describe("Regular expression tested against the full URL"),
            "fromApp": .string.optional().describe("Only links clicked in this app (name or bundle ID)"),
            "at": .int.min(1).optional().describe("Position in the rule list (default: last)"),
        ],
        examples: [
            Example(options: [("host", "youtube.com"), ("browser", "chrome"), ("profile", "Personal")]),
            Example(options: [("from-app", "slack"), ("browser", "chrome"), ("profile", "Work")]),
        ],
        hint: "youtube.com also covers www. and m.youtube.com, but youtu.be needs its own rule."
    ) { context in
        let options = context.options
        let target: (bundleID: String, profile: String?)
        let browser = options["browser"]!.stringValue!, profile = options["profile"]?.stringValue
        switch resolveTarget(browser: browser, profile: profile) {
        case .failure(let failure): return failure.response
        case .success(let value): target = value
        }
        let host = options["host"]?.stringValue
        let regex = options["regex"]?.stringValue
        let fromApp = options["fromApp"]?.stringValue.map(resolveApp)
        guard host != nil || regex != nil || fromApp != nil else {
            return .error(code: "INVALID_RULE", message: "A rule needs at least one of --host, --regex, or --from-app.")
        }
        if let regex, (try? NSRegularExpression(pattern: regex)) == nil {
            return .error(code: "INVALID_RULE", message: "Invalid regex: \(regex)")
        }
        var config = Config.load()
        let rule = Rule(host: host, regex: regex, fromApp: fromApp, browser: target.bundleID, profile: target.profile)
        config.upsert(rule, at: (options["at"]?.intValue ?? config.rules.count + 1) - 1)
        config.save()
        let check = host.map { Cta("test https://\($0)", description: "check where it opens") }
        return .ok(["rules": rulesJSON(config)], cta: check.map { CtaBlock(commands: [$0]) })
    }

    static let remove = Command(
        description: "Remove a rule by number",
        args: ["n": .int.coerce().describe("Rule number from `ferry rules`")],
        destructive: true
    ) { context in
        var config = Config.load()
        guard let index = ruleIndex(context.args["n"], in: config) else { return ruleNotFound }
        config.rules.remove(at: index)
        config.save()
        return .ok(["rules": rulesJSON(config)])
    }

    static let move = Command(
        description: "Move a rule to another position (first match wins)",
        args: ["from": .int.coerce().describe("Rule number"), "to": .int.coerce().describe("New position")]
    ) { context in
        var config = Config.load()
        guard let from = ruleIndex(context.args["from"], in: config), let to = ruleIndex(context.args["to"], in: config) else {
            return ruleNotFound
        }
        config.rules.insert(config.rules.remove(at: from), at: to)
        config.save()
        return .ok(["rules": rulesJSON(config)])
    }

    static let retarget = Command(
        description: "Change where a rule opens",
        args: ["n": .int.coerce().describe("Rule number from `ferry rules`")],
        options: [
            "browser": .string.describe("Browser name or bundle ID"),
            "profile": .string.optional().describe("Chrome profile: display name, email, or folder"),
        ]
    ) { context in
        var config = Config.load()
        guard let index = ruleIndex(context.args["n"], in: config) else { return ruleNotFound }
        let browser = context.options["browser"]!.stringValue!, profile = context.options["profile"]?.stringValue
        switch resolveTarget(browser: browser, profile: profile) {
        case .failure(let failure): return failure.response
        case .success(let target):
            config.rules[index].browser = target.bundleID
            config.rules[index].profile = target.profile
        }
        config.save()
        return .ok(["rules": rulesJSON(config)])
    }

    // MARK: App commands

    static let setup = Command(description: "Ask Ferry.app for access to Chrome profiles (shows the macOS prompt)") { _ in
        guard ProfileAccess.requestFromApp() else {
            return .error(code: "PROFILES_UNREADABLE", message: """
                Still can't read Chrome profiles. If you clicked Don't Allow, enable Ferry under System Settings → \
                Privacy & Security → App Management or Full Disk Access, then run `ferry setup` again.
                """)
        }
        let profiles = ChromeProfile.list(for: ProfileAccess.chromeID)
        let cta: CtaBlock? = isSystemBrowser ? nil : [Cta("system-browser", description: "route clicked links through Ferry")]
        return .ok(["chromeProfiles": .array(profiles.map { ["name": .string($0.name), "directory": .string($0.directory)] })], cta: cta)
    }

    static let systemBrowser = Command(description: "Make Ferry the system browser (macOS asks to confirm)") { _ in
        if isSystemBrowser { return .ok(["systemBrowser": true]) }
        guard AppControl.send(.systemBrowser) != nil else { return notResponding }
        return .ok(["requested": true, "next": "Confirm the macOS dialog."], cta: [Cta("status", description: "check the result")])
    }

    static let login = Command(
        description: "Turn launch at login on or off",
        args: ["state": .choice("on", "off").describe("on or off")]
    ) { context in
        let command: AppControl.Command = context.args["state"] == "on" ? .loginOn : .loginOff
        guard let reply = AppControl.send(command) else { return notResponding }
        return .ok(["launchAtLogin": .bool(reply == "login=true")])
    }

    static let edit = Command(description: "Open the config file in your text editor") { _ in
        Config.openInEditor()
        return .ok(["path": .string(Config.fileURL.path)])
    }

    static let quit = Command(description: "Quit the menu bar app") { _ in
        AppControl.quit() ? .ok(["quit": true]) : .error(code: "NOT_RUNNING", message: "Ferry is not running.")
    }

    // MARK: Helpers

    private struct Failure: Error {
        let response: Response
    }

    private static let notResponding = Response.error(code: "APP_NOT_RESPONDING", message: "Ferry.app did not respond.", retryable: true)
    private static let ruleNotFound = Response.error(code: "RULE_NOT_FOUND", message: "No rule with that number.", cta: ["rules"])

    private static func route(_ context: Context, open: Bool) throws -> Response {
        let text = context.args["url"]!.stringValue!
        guard let url = URL(string: text), url.scheme != nil else {
            return .error(code: "INVALID_URL", message: "Not a URL: \(text). Include the scheme, e.g. https://")
        }
        let source = context.options["fromApp"]?.stringValue.map(resolveApp)
        switch Decision.make(for: url, source: source, config: Config.load()) {
        case let .open(id, profile, reason):
            if open { Browser.find(id)?.open([url], profile: profile) }
            return .ok(["opens": .string(describe(id, profile) ?? id), "browser": .string(id),
                        "profile": profile.map(JSON.string) ?? nil, "reason": .string(reason)])
        case let .picker(reason):
            if open { NSWorkspace.shared.open(url) }
            return .ok(["opens": "picker", "browser": nil, "profile": nil, "reason": .string(reason)])
        }
    }

    private static var isSystemBrowser: Bool {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        return handler.flatMap { Bundle(url: $0)?.bundleIdentifier } == AppControl.bundleID
    }

    private static func rulesJSON(_ config: Config) -> JSON {
        .array(config.rules.enumerated().map { index, rule in
            let match = [rule.host.map { "host=\($0)" }, rule.regex.map { "regex=\($0)" }, rule.fromApp.map { "from=\($0)" }]
                .compactMap { $0 }.joined(separator: " ")
            return ["n": .number(Double(index + 1)), "match": .string(match),
                    "opens": .string(describe(rule.browser, rule.profile) ?? rule.browser), "browser": .string(rule.browser)]
        })
    }

    private static func describe(_ bundleID: String?, _ profile: String?) -> String? {
        guard let bundleID else { return nil }
        let name = Browser.find(bundleID)?.name ?? "\(bundleID) (not installed)"
        guard let profile else { return name }
        let label = ChromeProfile.list(for: bundleID).first { $0.directory == profile }?.name ?? profile
        return "\(name) – \(label)"
    }

    private static func ruleIndex(_ value: JSON?, in config: Config) -> Int? {
        guard let number = value?.intValue, config.rules.indices.contains(number - 1) else { return nil }
        return number - 1
    }

    /// Browser by bundle ID or name; profile checked against the browser's real profiles when readable.
    private static func resolveTarget(browser: String, profile: String?) -> Result<(bundleID: String, profile: String?), Failure> {
        let installed = Browser.installed()
        let needle = browser.lowercased()
        let match = installed.first { $0.bundleID.lowercased() == needle || $0.name.lowercased() == needle }
            ?? installed.first { $0.name.lowercased().contains(needle) }
        guard let match else {
            return .failure(Failure(response: .error(
                code: "BROWSER_NOT_FOUND",
                message: "No browser matches '\(browser)'. Installed: \(installed.map(\.name).joined(separator: ", "))",
                cta: ["browsers"]
            )))
        }
        guard let profile else { return .success((match.bundleID, nil)) }
        if ChromeProfile.supports(match.bundleID), !ChromeProfile.isFolderName(profile) {
            _ = ProfileAccess.requestFromApp()
        }
        guard let directory = ChromeProfile.resolve(profile, for: match.bundleID) else {
            let profiles = ChromeProfile.list(for: match.bundleID)
            guard !profiles.isEmpty else {
                return .failure(Failure(response: .error(
                    code: "PROFILES_UNREADABLE",
                    message: "Can't read \(match.name)'s profiles, so '\(profile)' can't be checked. Run `ferry setup` and click Allow, or use a folder name like 'Default' or 'Profile 1'.",
                    cta: [Cta("setup", description: "allow access to Chrome profiles")]
                )))
            }
            let names = profiles.map { "\($0.name) [\($0.directory)]" }.joined(separator: ", ")
            return .failure(Failure(response: .error(
                code: "PROFILE_NOT_FOUND", message: "\(match.name) has no profile '\(profile)'. Profiles: \(names)", cta: ["browsers"]
            )))
        }
        return .success((match.bundleID, directory))
    }

    /// Bundle ID for an app name; anything already shaped like a bundle ID passes through.
    private static func resolveApp(_ value: String) -> String {
        if value.contains("."), NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) != nil { return value }
        let path = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"].lazy
            .compactMap { directory in
                try? FileManager.default.contentsOfDirectory(atPath: directory)
                    .first { $0.lowercased().hasSuffix(".app") && $0.lowercased().contains(value.lowercased()) }
                    .map { "\(directory)/\($0)" }
            }
            .first
        return path.flatMap { Bundle(path: $0)?.bundleIdentifier } ?? value
    }
}
