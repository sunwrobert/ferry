import Foundation

/// A Chromium profile read from the browser's `Local State` file.
struct ChromeProfile: Codable {
    /// Folder name passed to `--profile-directory`, e.g. `Default` or `Profile 1`.
    let directory: String
    let name: String
    let email: String?

    /// Application Support folders for the Chromium browsers Ferry knows how to read.
    private static let dataFolders: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
    ]

    static func supports(_ bundleID: String) -> Bool {
        dataFolders[bundleID] != nil
    }

    /// Last list the menu bar app read. Terminals often lack permission to read Chrome's data,
    /// so the CLI falls back to this copy.
    private static let cacheURL = Config.fileURL.deletingLastPathComponent().appendingPathComponent("profiles.json")

    /// Profiles in Chrome's own menu order. Empty if the browser is unsupported or nothing is readable.
    static func list(for bundleID: String) -> [ChromeProfile] {
        guard dataFolders[bundleID] != nil else { return [] }
        if let fresh = readLocalState(for: bundleID) {
            writeCache(fresh, for: bundleID)
            return fresh
        }
        return readCache()[bundleID] ?? []
    }

    private static func readLocalState(for bundleID: String) -> [ChromeProfile]? {
        guard let folder = dataFolders[bundleID] else { return nil }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(folder)/Local State")
        do {
            let state = try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: url))
            let cache = state.profile.infoCache
            let order = state.profile.profilesOrder ?? cache.keys.sorted()
            return order.compactMap { directory in
                guard let info = cache[directory] else { return nil }
                let email = info.userName.flatMap { $0.isEmpty ? nil : $0 }
                return ChromeProfile(directory: directory, name: info.name, email: email)
            }
        } catch {
            return nil
        }
    }

    private static func readCache() -> [String: [ChromeProfile]] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: [ChromeProfile]].self, from: data)) ?? [:]
    }

    private static func writeCache(_ profiles: [ChromeProfile], for bundleID: String) {
        var cache = readCache()
        guard cache[bundleID]?.map(\.directory) != profiles.map(\.directory)
            || cache[bundleID]?.map(\.name) != profiles.map(\.name) else { return }
        cache[bundleID] = profiles
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(cache).write(to: cacheURL, options: .atomic)
    }

    /// Folder for a config value that may be a folder name, display name, or email.
    /// `nil` when it cannot be resolved: passing an unknown name to Chrome would create a new empty profile.
    static func resolve(_ value: String, for bundleID: String) -> String? {
        let needle = value.lowercased()
        let profiles = list(for: bundleID)
        if let match = profiles.first(where: {
            $0.directory.lowercased() == needle || $0.name.lowercased() == needle || $0.email?.lowercased() == needle
        }) {
            return match.directory
        }
        return profiles.isEmpty && isFolderName(value) ? value : nil
    }

    /// Chrome's own folder names, safe to pass through even when the profile list is unreadable.
    static func isFolderName(_ value: String) -> Bool {
        value == "Default" || value.range(of: #"^Profile \d+$"#, options: .regularExpression) != nil
    }
}

private struct LocalState: Decodable {
    struct Profile: Decodable {
        struct Info: Decodable {
            let name: String
            let userName: String?

            enum CodingKeys: String, CodingKey {
                case name
                case userName = "user_name"
            }
        }

        let infoCache: [String: Info]
        let profilesOrder: [String]?

        enum CodingKeys: String, CodingKey {
            case infoCache = "info_cache"
            case profilesOrder = "profiles_order"
        }
    }

    let profile: Profile
}
