import Foundation
import Darwin

enum ServerState: Equatable {
    case stopped
    case starting
    case running(pid: Int32)
    case failed(String)

    var title: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case let .running(pid):
            return "Running (pid \(pid))"
        case let .failed(message):
            return "Failed: \(message.clipped(to: 70))"
        }
    }

    var canStop: Bool {
        switch self {
        case .starting, .running:
            return true
        case .stopped, .failed:
            return false
        }
    }

    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }

    var usesFilledIcon: Bool {
        switch self {
        case .starting, .running:
            return true
        case .stopped, .failed:
            return false
        }
    }
}

final class OpenCodeServer {
    var onStateChanged: ((ServerState) -> Void)?

    private let settingsProvider: () -> ServerSettings
    private var process: Process?
    private var outputPipe: Pipe?
    private var requestedStop = false

    private(set) var state: ServerState = .stopped {
        didSet { onStateChanged?(state) }
    }

    private(set) var runtimePort: Int?

    private(set) var recentOutput = ""

    init(settingsProvider: @escaping () -> ServerSettings) {
        self.settingsProvider = settingsProvider
    }

    func start() {
        guard process == nil else { return }

        var settings = settingsProvider()
        requestedStop = false
        recentOutput = ""

        if let actualPort = PortFinder.findAvailable(startingFrom: settings.port), actualPort != settings.port {
            appendOutput("Port \(settings.port) is in use; using \(actualPort) instead.\n")
            settings.port = actualPort
        }
        runtimePort = settings.port

        appendOutput("$ \(settings.displayCommand)\n")
        state = .starting

        let executable = settings.executable.trimmingCharacters(in: .whitespacesAndNewlines)
        let environment = settings.environment(merging: ProcessInfo.processInfo.environment)

        guard let executableURL = ExecutableLocator.resolve(executable, environment: environment) else {
            let message = "Could not find '\(executable)' in PATH. Set Executable in Settings to an absolute path, or install opencode in ~/.opencode/bin, ~/.bun/bin, /opt/homebrew/bin, or /usr/local/bin."
            appendOutput("\(message)\n")
            state = .failed(message)
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = settings.arguments

        process.currentDirectoryURL = URL(fileURLWithPath: settings.expandedWorkingDirectory, isDirectory: true)
        process.environment = environment

        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput(chunk)
            }
        }
        process.standardOutput = pipe
        process.standardError = pipe
        outputPipe = pipe

        process.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async {
                self?.handleTermination(of: terminatedProcess)
            }
        }

        do {
            try process.run()
            self.process = process
            state = .running(pid: process.processIdentifier)
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            outputPipe = nil
            runtimePort = nil
            appendOutput("Failed to start: \(error.localizedDescription)\n")
            state = .failed(error.localizedDescription)
        }
    }

    func stop(waitUntilExit: Bool = false) {
        guard let process else {
            state = .stopped
            return
        }

        requestedStop = true
        if process.isRunning {
            process.terminate()
        }

        if waitUntilExit {
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
    }

    func restart() {
        stop(waitUntilExit: true)
        start()
    }

    private func handleTermination(of terminatedProcess: Process) {
        guard process === terminatedProcess else { return }

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        runtimePort = nil

        if requestedStop || terminatedProcess.terminationStatus == 0 {
            state = .stopped
        } else {
            let message = terminationMessage(for: terminatedProcess.terminationStatus)
            appendOutput("\(message)\n")
            state = .failed(message)
        }

        requestedStop = false
    }

    private func appendOutput(_ chunk: String) {
        recentOutput += chunk
        if recentOutput.count > 12_000 {
            recentOutput = String(recentOutput.suffix(12_000))
        }
    }

    private func terminationMessage(for status: Int32) -> String {
        if status == 127 {
            return "opencode exited with code 127 (command not found). Check the Executable setting."
        }
        return "opencode exited with code \(status)"
    }
}

private extension String {
    func clipped(to limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(limit)) + "..."
    }
}
