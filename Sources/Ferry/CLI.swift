import AppKit

/// Command-line interface for scripts and agents. Every command that changes config prints the result.
enum CLI {
    static let usage = """
    ferry: route links to the right browser and Chrome profile

    USAGE
      ferry setup                       Ask Ferry.app for access to Chrome profiles (shows the macOS prompt)
      ferry browsers [--json]           List browsers and Chrome profiles (names usable below)
      ferry config [--json | --path]    Show the config
      ferry default <browser> [--profile <p>]
      ferry default --ask               Show the picker when no rule matches
      ferry rules                       List rules with their numbers
      ferry add --browser <b> [--profile <p>] [--host <h>] [--regex <r>] [--from-app <a>] [--at <n>]
      ferry remove <n>                  Remove rule n
      ferry move <n> <m>                Move rule n to position m (first match wins)
      ferry test <url> [--from-app <a>] Show where a link would go, without opening it
      ferry open <url> [--from-app <a>] Route a link for real

    <browser> is a bundle ID or app name (chrome, "Google Chrome", com.google.Chrome).
    <p> is a Chrome profile folder, display name, or email.
    <a> is a bundle ID or app name (slack, com.tinyspeck.slackmacgap).
    Config: ~/.config/ferry/config.json. Edits apply to the next link.
    """

    static func run(_ command: String, _ args: [String]) -> Int32 {
        let result: Result<Void, CLIError>
        switch command {
        case "setup": result = setup()
        case "browsers": result = browsers(args)
        case "config": result = config(args)
        case "default": result = setDefault(args)
        case "rules": result = .success(printRules(Config.load()))
        case "add": result = add(args)
        case "remove": result = remove(args)
        case "move": result = move(args)
        case "test": result = test(args, open: false)
        case "open": result = test(args, open: true)
        case "help", "-h", "--help": result = .success(print(usage))
        default: result = .failure(CLIError("unknown command '\(command)'\n\n\(usage)"))
        }
        switch result {
        case .success: return 0
        case let .failure(error):
            FileHandle.standardError.write(Data("ferry: \(error.message)\n".utf8))
            return 1
        }
    }

    // MARK: Commands

    private static func setup() -> Result<Void, CLIError> {
        guard ProfileAccess.requestFromApp() else {
            return .failure(CLIError(
                "still can't read Chrome profiles. If you clicked Don't Allow, enable Ferry under "
                    + "System Settings → Privacy & Security → App Management / Full Disk Access, then run `ferry setup` again."))
        }
        let profiles = ChromeProfile.list(for: ProfileAccess.chromeID)
        print("Chrome profiles: \(profiles.map { "\($0.name) [\($0.directory)]" }.joined(separator: ", "))")
        if !isSystemBrowser { print("Next: choose \"Make Ferry the System Browser\" in Ferry's menu so clicked links are routed.") }
        return .success(())
    }

    private static var isSystemBrowser: Bool {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        return handler.flatMap { Bundle(url: $0)?.bundleIdentifier } == "com.sunwrobert.ferry"
    }

    private static func browsers(_ args: [String]) -> Result<Void, CLIError> {
        _ = ProfileAccess.requestFromApp()
        let list = Browser.installed().map { browser in
            BrowserInfo(
                name: browser.name,
                bundleID: browser.bundleID,
                profiles: ChromeProfile.list(for: browser.bundleID).map {
                    ProfileInfo(directory: $0.directory, name: $0.name, email: $0.email)
                }
            )
        }
        if args.contains("--json") { return printJSON(list) }
        for browser in list {
            print("\(browser.name)  \(browser.bundleID)")
            for profile in browser.profiles {
                print("    \(profile.name)  [\(profile.directory)]\(profile.email.map { "  \($0)" } ?? "")")
            }
            if ChromeProfile.supports(browser.bundleID) && browser.profiles.isEmpty {
                print("    (profiles unknown: run `ferry setup`)")
            }
        }
        return .success(())
    }

    private static func config(_ args: [String]) -> Result<Void, CLIError> {
        if args.contains("--path") { return .success(print(Config.fileURL.path)) }
        let config = Config.load()
        if args.contains("--json") { return printJSON(config) }
        print("Config: \(Config.fileURL.path)")
        print("Default: \(describe(config.defaultBrowser, config.defaultProfile) ?? "ask every time")")
        printRules(config)
        return .success(())
    }

    private static func setDefault(_ args: [String]) -> Result<Void, CLIError> {
        var config = Config.load()
        if args.contains("--ask") {
            config.defaultBrowser = nil
            config.defaultProfile = nil
        } else {
            var options = Options(args)
            guard let name = options.positional.first else { return .failure(CLIError("usage: ferry default <browser> [--profile <p>]")) }
            let resolved = resolveTarget(browser: name, profile: options.take("--profile"))
            guard case let .success((id, profile)) = resolved else { return resolved.map { _ in } }
            config.defaultBrowser = id
            config.defaultProfile = profile
        }
        config.save()
        print("Default: \(describe(config.defaultBrowser, config.defaultProfile) ?? "ask every time")")
        return .success(())
    }

    private static func add(_ args: [String]) -> Result<Void, CLIError> {
        var options = Options(args)
        guard let browserName = options.take("--browser") else { return .failure(CLIError("--browser is required")) }
        let resolved = resolveTarget(browser: browserName, profile: options.take("--profile"))
        guard case let .success((id, profile)) = resolved else { return resolved.map { _ in } }

        let host = options.take("--host")
        let regex = options.take("--regex")
        let fromApp = options.take("--from-app").map(resolveApp)
        guard host != nil || regex != nil || fromApp != nil else {
            return .failure(CLIError("a rule needs at least one of --host, --regex, or --from-app"))
        }
        if let regex, (try? NSRegularExpression(pattern: regex)) == nil {
            return .failure(CLIError("invalid regex: \(regex)"))
        }

        var config = Config.load()
        let rule = Rule(host: host, regex: regex, fromApp: fromApp, browser: id, profile: profile)
        let position = options.take("--at").flatMap(Int.init) ?? config.rules.count + 1
        config.rules.insert(rule, at: min(max(position, 1), config.rules.count + 1) - 1)
        config.save()
        printRules(config)
        return .success(())
    }

    private static func remove(_ args: [String]) -> Result<Void, CLIError> {
        var config = Config.load()
        guard let index = ruleIndex(args.first, in: config) else { return .failure(CLIError("usage: ferry remove <n> (see `ferry rules`)")) }
        config.rules.remove(at: index)
        config.save()
        printRules(config)
        return .success(())
    }

    private static func move(_ args: [String]) -> Result<Void, CLIError> {
        var config = Config.load()
        guard args.count == 2, let from = ruleIndex(args[0], in: config), let to = ruleIndex(args[1], in: config) else {
            return .failure(CLIError("usage: ferry move <n> <m> (see `ferry rules`)"))
        }
        config.rules.insert(config.rules.remove(at: from), at: to)
        config.save()
        printRules(config)
        return .success(())
    }

    private static func test(_ args: [String], open: Bool) -> Result<Void, CLIError> {
        var options = Options(args)
        let source = options.take("--from-app").map(resolveApp)
        guard let text = options.positional.first, let url = URL(string: text), url.scheme != nil else {
            return .failure(CLIError("usage: ferry \(open ? "open" : "test") <url> [--from-app <a>]"))
        }
        switch Decision.make(for: url, source: source, config: Config.load()) {
        case let .open(id, profile, reason):
            print("\(describe(id, profile) ?? id)  (\(reason))")
            if open { Browser.find(id)?.open([url], profile: profile) }
        case let .picker(reason):
            print("picker  (\(reason))")
            if open { NSWorkspace.shared.open(url) }
        }
        return .success(())
    }

    // MARK: Helpers

    private static func printRules(_ config: Config) {
        guard !config.rules.isEmpty else { return print("No rules.") }
        for (index, rule) in config.rules.enumerated() {
            let match = [
                rule.host.map { "host=\($0)" },
                rule.regex.map { "regex=\($0)" },
                rule.fromApp.map { "from=\($0)" },
            ].compactMap { $0 }.joined(separator: " ")
            print("\(index + 1). \(match) → \(describe(rule.browser, rule.profile) ?? rule.browser)")
        }
    }

    private static func describe(_ bundleID: String?, _ profile: String?) -> String? {
        guard let bundleID else { return nil }
        let name = Browser.find(bundleID)?.name ?? "\(bundleID) (not installed)"
        return profile.map { "\(name) – \($0)" } ?? name
    }

    /// Browser by bundle ID or name; profile checked against the browser's real profiles when readable.
    private static func resolveTarget(browser: String, profile: String?) -> Result<(String, String?), CLIError> {
        let installed = Browser.installed()
        let needle = browser.lowercased()
        let match = installed.first { $0.bundleID.lowercased() == needle || $0.name.lowercased() == needle }
            ?? installed.first { $0.name.lowercased().contains(needle) }
        guard let match else {
            return .failure(CLIError("no browser matches '\(browser)'. Installed: \(installed.map(\.name).joined(separator: ", "))"))
        }
        guard let profile else { return .success((match.bundleID, nil)) }
        if ChromeProfile.supports(match.bundleID), !ChromeProfile.isFolderName(profile) {
            _ = ProfileAccess.requestFromApp()
        }
        guard let directory = ChromeProfile.resolve(profile, for: match.bundleID) else {
            let profiles = ChromeProfile.list(for: match.bundleID)
            guard !profiles.isEmpty else {
                return .failure(CLIError(
                    "can't read \(match.name)'s profiles, so '\(profile)' can't be checked. "
                        + "Run `ferry setup` and click Allow, or use a folder name like 'Default' or 'Profile 1'."))
            }
            let names = profiles.map { "\($0.name) [\($0.directory)]" }.joined(separator: ", ")
            return .failure(CLIError("\(match.name) has no profile '\(profile)'. Profiles: \(names)"))
        }
        return .success((match.bundleID, directory))
    }

    /// Bundle ID for an app name; anything already shaped like a bundle ID passes through.
    private static func resolveApp(_ value: String) -> String {
        if value.contains("."), NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) != nil { return value }
        let path = NSWorkspace.shared.fullPath(forApplication: value)
            ?? ["/Applications", "/System/Applications"].lazy
                .compactMap { dir in try? FileManager.default.contentsOfDirectory(atPath: dir).first {
                    $0.lowercased().hasSuffix(".app") && $0.lowercased().contains(value.lowercased())
                }.map { "\(dir)/\($0)" } }
                .first
        return path.flatMap { Bundle(path: $0)?.bundleIdentifier } ?? value
    }

    private static func ruleIndex(_ text: String?, in config: Config) -> Int? {
        guard let text, let number = Int(text), config.rules.indices.contains(number - 1) else { return nil }
        return number - 1
    }

    private static func printJSON<T: Encodable>(_ value: T) -> Result<Void, CLIError> {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return .failure(CLIError("could not encode JSON")) }
        print(String(decoding: data, as: UTF8.self))
        return .success(())
    }
}

struct CLIError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private struct BrowserInfo: Encodable {
    let name: String
    let bundleID: String
    let profiles: [ProfileInfo]
}

private struct ProfileInfo: Encodable {
    let directory: String
    let name: String
    let email: String?
}

/// Minimal `--flag value` parser; whatever is left is positional.
private struct Options {
    private var args: [String]

    init(_ args: [String]) { self.args = args }

    mutating func take(_ flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        let value = args[index + 1]
        args.removeSubrange(index...index + 1)
        return value
    }

    var positional: [String] { args.filter { !$0.hasPrefix("--") } }
}
