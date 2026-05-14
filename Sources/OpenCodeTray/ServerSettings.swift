import Foundation

struct ServerSettings: Equatable {
    var executable: String
    var workingDirectory: String
    var hostname: String
    var port: Int
    var enableMDNS: Bool
    var mdnsDomain: String
    var corsOrigins: [String]
    var enableBasicAuth: Bool
    var authUsername: String
    var authPassword: String
    var includeAuthInSharedURLs: Bool
    var launchAtLogin: Bool
    var startServerOnLaunch: Bool
    var caffeinateEnabled: Bool
    var caffeinateAllowLidClosed: Bool
    var caffeinateOnBattery: Bool

    static let defaults = ServerSettings(
        executable: "opencode",
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
        hostname: "0.0.0.0",
        port: 4096,
        enableMDNS: false,
        mdnsDomain: "opencode.local",
        corsOrigins: [],
        enableBasicAuth: false,
        authUsername: "opencode",
        authPassword: "",
        includeAuthInSharedURLs: false,
        launchAtLogin: false,
        startServerOnLaunch: true,
        caffeinateEnabled: false,
        caffeinateAllowLidClosed: false,
        caffeinateOnBattery: false
    )

    private enum Key {
        static let executable = "server.executable"
        static let workingDirectory = "server.workingDirectory"
        static let hostname = "server.hostname"
        static let migratedWildcardBindDefault = "server.migratedWildcardBindDefault"
        static let port = "server.port"
        static let enableMDNS = "server.enableMDNS"
        static let mdnsDomain = "server.mdnsDomain"
        static let corsOrigins = "server.corsOrigins"
        static let enableBasicAuth = "server.enableBasicAuth"
        static let authUsername = "server.authUsername"
        static let authPassword = "server.authPassword"
        static let includeAuthInSharedURLs = "server.includeAuthInSharedURLs"
        static let launchAtLogin = "app.launchAtLogin"
        static let startServerOnLaunch = "app.startServerOnLaunch"
        static let caffeinateEnabled = "app.caffeinateEnabled"
        static let caffeinateAllowLidClosed = "app.caffeinateAllowLidClosed"
        static let caffeinateOnBattery = "app.caffeinateOnBattery"
    }

    var expandedWorkingDirectory: String {
        NSString(string: workingDirectory).expandingTildeInPath
    }

    var arguments: [String] {
        var result = [
            "serve",
            "--port", String(port),
            "--hostname", hostname,
        ]

        if enableMDNS {
            result.append("--mdns")
            if !mdnsDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(contentsOf: ["--mdns-domain", mdnsDomain])
            }
        }

        for origin in corsOrigins.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            result.append(contentsOf: ["--cors", origin])
        }

        return result
    }

    var serverURLString: String {
        "http://\(urlHost):\(port)"
    }

    var localURLHost: String {
        urlHost
    }

    var docURLString: String {
        "\(serverURLString)/doc"
    }

    var effectiveAuthUsername: String {
        let username = authUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? "opencode" : username
    }

    var basicAuthEnabled: Bool {
        enableBasicAuth && !authPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayCommand: String {
        ([executable] + arguments).map(shellQuoted).joined(separator: " ")
    }

    func environment(merging base: [String: String]) -> [String: String] {
        var environment = base
        environment["PATH"] = mergedPath(existing: base["PATH"])

        let password = authPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if enableBasicAuth && !password.isEmpty {
            environment["OPENCODE_SERVER_PASSWORD"] = authPassword
            let username = authUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty && username != "opencode" {
                environment["OPENCODE_SERVER_USERNAME"] = username
            } else {
                environment.removeValue(forKey: "OPENCODE_SERVER_USERNAME")
            }
        } else {
            environment.removeValue(forKey: "OPENCODE_SERVER_PASSWORD")
            environment.removeValue(forKey: "OPENCODE_SERVER_USERNAME")
        }

        return environment
    }

    static func load(from defaults: UserDefaults = .standard) -> ServerSettings {
        var settings = ServerSettings.defaults
        settings.executable = defaults.string(forKey: Key.executable) ?? settings.executable
        settings.workingDirectory = defaults.string(forKey: Key.workingDirectory) ?? settings.workingDirectory
        settings.hostname = defaults.string(forKey: Key.hostname) ?? settings.hostname

        if defaults.object(forKey: Key.migratedWildcardBindDefault) == nil {
            if settings.hostname == "127.0.0.1" {
                settings.hostname = ServerSettings.defaults.hostname
            }
            defaults.set(true, forKey: Key.migratedWildcardBindDefault)
        }

        let savedPort = defaults.integer(forKey: Key.port)
        if savedPort > 0 {
            settings.port = savedPort
        }

        if defaults.object(forKey: Key.enableMDNS) != nil {
            settings.enableMDNS = defaults.bool(forKey: Key.enableMDNS)
        }
        settings.mdnsDomain = defaults.string(forKey: Key.mdnsDomain) ?? settings.mdnsDomain
        settings.corsOrigins = defaults.stringArray(forKey: Key.corsOrigins) ?? settings.corsOrigins
        if defaults.object(forKey: Key.enableBasicAuth) != nil {
            settings.enableBasicAuth = defaults.bool(forKey: Key.enableBasicAuth)
        }
        settings.authUsername = defaults.string(forKey: Key.authUsername) ?? settings.authUsername
        settings.authPassword = defaults.string(forKey: Key.authPassword) ?? settings.authPassword
        if defaults.object(forKey: Key.includeAuthInSharedURLs) != nil {
            settings.includeAuthInSharedURLs = defaults.bool(forKey: Key.includeAuthInSharedURLs)
        }

        if defaults.object(forKey: Key.launchAtLogin) != nil {
            settings.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        }
        if defaults.object(forKey: Key.startServerOnLaunch) != nil {
            settings.startServerOnLaunch = defaults.bool(forKey: Key.startServerOnLaunch)
        }
        if defaults.object(forKey: Key.caffeinateEnabled) != nil {
            settings.caffeinateEnabled = defaults.bool(forKey: Key.caffeinateEnabled)
        }
        if defaults.object(forKey: Key.caffeinateAllowLidClosed) != nil {
            settings.caffeinateAllowLidClosed = defaults.bool(forKey: Key.caffeinateAllowLidClosed)
        }
        if defaults.object(forKey: Key.caffeinateOnBattery) != nil {
            settings.caffeinateOnBattery = defaults.bool(forKey: Key.caffeinateOnBattery)
        }

        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(executable, forKey: Key.executable)
        defaults.set(workingDirectory, forKey: Key.workingDirectory)
        defaults.set(hostname, forKey: Key.hostname)
        defaults.set(port, forKey: Key.port)
        defaults.set(enableMDNS, forKey: Key.enableMDNS)
        defaults.set(mdnsDomain, forKey: Key.mdnsDomain)
        defaults.set(corsOrigins, forKey: Key.corsOrigins)
        defaults.set(enableBasicAuth, forKey: Key.enableBasicAuth)
        defaults.set(authUsername, forKey: Key.authUsername)
        defaults.set(authPassword, forKey: Key.authPassword)
        defaults.set(includeAuthInSharedURLs, forKey: Key.includeAuthInSharedURLs)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(startServerOnLaunch, forKey: Key.startServerOnLaunch)
        defaults.set(caffeinateEnabled, forKey: Key.caffeinateEnabled)
        defaults.set(caffeinateAllowLidClosed, forKey: Key.caffeinateAllowLidClosed)
        defaults.set(caffeinateOnBattery, forKey: Key.caffeinateOnBattery)

    }

    private var urlHost: String {
        if hostname == "0.0.0.0" || hostname == "::" {
            return "localhost"
        }
        if hostname.contains(":") && !hostname.hasPrefix("[") {
            return "[\(hostname)]"
        }
        return hostname
    }

    private func mergedPath(existing: String?) -> String {
        ExecutableLocator.searchPath(merging: existing)
    }

    private func shellQuoted(_ value: String) -> String {
        guard value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "'\\\"$`"))) != nil else {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
