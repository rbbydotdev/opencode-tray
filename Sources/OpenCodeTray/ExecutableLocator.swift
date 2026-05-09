import Foundation

enum ExecutableLocator {
    static func resolve(_ executable: String, environment: [String: String]) -> URL? {
        let fileManager = FileManager.default
        let trimmedExecutable = executable.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedExecutable.contains("/") {
            let path = NSString(string: trimmedExecutable).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }

        for directory in searchPath(merging: environment["PATH"]).split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent(trimmedExecutable).path
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
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
}
