import Foundation

enum ExecutableLocator {
    static func resolve(_ executable: String, environment: [String: String]) -> URL? {
        let fileManager = FileManager.default
        let trimmedExecutable = normalizedExecutable(executable)

        if trimmedExecutable.contains("/") {
            let path = NSString(string: trimmedExecutable).expandingTildeInPath
            guard fileManager.isExecutableFile(atPath: path) else { return nil }
            let url = URL(fileURLWithPath: path)
            return nativeExecutable(forShimAt: url) ?? url
        }

        for directory in searchPath(merging: environment["PATH"]).split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent(trimmedExecutable).path
            if fileManager.isExecutableFile(atPath: path) {
                let url = URL(fileURLWithPath: path)
                return nativeExecutable(forShimAt: url) ?? url
            }
        }

        return nil
    }

    static func searchPath(merging existing: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaults = [
            "\(home)/.opencode/bin",
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")

        guard let existing, !existing.isEmpty else { return defaults }
        return "\(defaults):\(existing)"
    }

    private static func normalizedExecutable(_ executable: String) -> String {
        let trimmed = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last, (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func nativeExecutable(forShimAt url: URL) -> URL? {
        guard isOpencodeNodeShim(url) else { return nil }

        let scriptDirectory = url.deletingLastPathComponent()
        let cachedBinary = scriptDirectory.appendingPathComponent(".opencode")
        if FileManager.default.isExecutableFile(atPath: cachedBinary.path) {
            return cachedBinary
        }

        return nativeExecutableNearNodeModules(startingAt: scriptDirectory) ?? nativeExecutableInBunCache()
    }

    private static func isOpencodeNodeShim(_ url: URL) -> Bool {
        guard url.lastPathComponent == "opencode" else { return false }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        guard let prefix = String(data: data.prefix(4096), encoding: .utf8) else { return false }
        return prefix.contains("#!/usr/bin/env node") && prefix.contains("opencode-")
    }

    private static func nativeExecutableNearNodeModules(startingAt directory: URL) -> URL? {
        var current = directory

        while true {
            let nodeModules = current.appendingPathComponent("node_modules", isDirectory: true)
            if let native = nativeExecutable(inPackageDirectory: nodeModules) {
                return native
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    private static func nativeExecutableInBunCache() -> URL? {
        let cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bun", isDirectory: true)
            .appendingPathComponent("install", isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)

        return nativeExecutable(inPackageDirectory: cacheDirectory)
    }

    private static func nativeExecutable(inPackageDirectory directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }

        let packagePrefix = nativePackagePrefix()
        let candidates = entries.compactMap { entry -> (url: URL, date: Date)? in
            guard entry.lastPathComponent.hasPrefix(packagePrefix) else { return nil }
            let binary = entry.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("opencode")
            guard fileManager.isExecutableFile(atPath: binary.path) else { return nil }
            let date = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (binary, date)
        }

        return candidates.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.url.path > rhs.url.path
            }
            return lhs.date > rhs.date
        }.first?.url
    }

    private static func nativePackagePrefix() -> String {
        #if arch(arm64)
        return "opencode-darwin-arm64"
        #elseif arch(x86_64)
        return "opencode-darwin-x64"
        #else
        return "opencode-darwin"
        #endif
    }
}
