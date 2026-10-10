import Foundation

/// A Chromium profile read from the browser's `Local State` file.
struct ChromeProfile {
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

    /// Profiles in Chrome's own menu order. Empty if the browser is unsupported or the file is unreadable.
    static func list(for bundleID: String) -> [ChromeProfile] {
        guard let folder = dataFolders[bundleID] else { return [] }
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
            NSLog("Ferry: could not read \(bundleID) profiles: \(error)")
            return []
        }
    }

    /// Resolve a config value that may be a folder name, display name, or email.
    static func resolve(_ value: String, for bundleID: String) -> String {
        let needle = value.lowercased()
        let match = list(for: bundleID).first {
            $0.directory.lowercased() == needle || $0.name.lowercased() == needle || $0.email?.lowercased() == needle
        }
        return match?.directory ?? value
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
