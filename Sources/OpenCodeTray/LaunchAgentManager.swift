import Foundation

final class LaunchAgentManager {
    static let shared = LaunchAgentManager()

    private let label = "ai.opencode.tray"
    private let fileManager = FileManager.default

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    private func enable() throws {
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": launchProgramArguments(),
            "RunAtLoad": true,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    private func disable() throws {
        guard isEnabled else { return }
        try fileManager.removeItem(at: plistURL)
    }

    private func launchProgramArguments() -> [String] {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return ["/usr/bin/open", bundleURL.path]
        }

        if let executableURL = Bundle.main.executableURL {
            return [executableURL.path]
        }

        return [CommandLine.arguments[0]]
    }
}
