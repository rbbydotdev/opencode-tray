import Foundation
import HelperProtocol

enum HelperInstaller {
    enum Outcome {
        case ok
        case userCancelled
        case failed(String)
    }

    static func install(completion: @escaping (Outcome) -> Void) {
        guard let helperURL = bundledHelperURL() else {
            completion(.failed("Helper binary not found in app bundle."))
            return
        }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            completion(.failed("Helper binary is not executable: \(helperURL.path)"))
            return
        }
        runWithAdminPrivileges(
            shellScript: installShellScript(helperSource: helperURL.path),
            completion: completion
        )
    }

    static func uninstall(completion: @escaping (Outcome) -> Void) {
        runWithAdminPrivileges(shellScript: uninstallShellScript, completion: completion)
    }

    private static func bundledHelperURL() -> URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OpenCodeTrayHelper")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func installShellScript(helperSource: String) -> String {
        return """
        set -e
        LABEL='\(HelperServiceConstants.label)'
        HELPER_DEST='\(HelperServiceConstants.installedHelperPath)'
        PLIST_DEST='\(HelperServiceConstants.installedPlistPath)'

        if launchctl print "system/$LABEL" >/dev/null 2>&1; then
            launchctl bootout "system/$LABEL" || true
        fi

        install -d -m 0755 "$(dirname "$HELPER_DEST")"
        install -m 0755 -o root -g wheel \(shellQuote(helperSource)) "$HELPER_DEST"

        cat > "$PLIST_DEST" <<'PLIST_EOF'
        \(plistContent)
        PLIST_EOF

        chown root:wheel "$PLIST_DEST"
        chmod 0644 "$PLIST_DEST"
        launchctl bootstrap system "$PLIST_DEST"
        """
    }

    private static let uninstallShellScript: String = """
    LABEL='\(HelperServiceConstants.label)'
    /usr/bin/pmset -b disablesleep 0 >/dev/null 2>&1 || true
    if launchctl print "system/$LABEL" >/dev/null 2>&1; then
        launchctl bootout "system/$LABEL" || true
    fi
    rm -f '\(HelperServiceConstants.installedPlistPath)' '\(HelperServiceConstants.installedHelperPath)'
    """

    private static let plistContent: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(HelperServiceConstants.label)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(HelperServiceConstants.installedHelperPath)</string>
        </array>
        <key>MachServices</key>
        <dict>
            <key>\(HelperServiceConstants.machServiceName)</key>
            <true/>
        </dict>
        <key>ProcessType</key>
        <string>Background</string>
    </dict>
    </plist>
    """

    private static func runWithAdminPrivileges(shellScript: String, completion: @escaping (Outcome) -> Void) {
        let tempScriptURL: URL
        do {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            tempScriptURL = dir.appendingPathComponent("opencode-tray-installer-\(UUID().uuidString).sh")
            try shellScript.write(to: tempScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempScriptURL.path)
        } catch {
            completion(.failed("Could not stage installer script: \(error.localizedDescription)"))
            return
        }

        let cmdLine = "/bin/bash " + shellQuote(tempScriptURL.path)
        let appleScript = "do shell script \"\(escapeForAppleScript(cmdLine))\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", appleScript]

            let stderr = Pipe()
            task.standardError = stderr

            do {
                try task.run()
                task.waitUntilExit()
                let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                try? FileManager.default.removeItem(at: tempScriptURL)

                let outcome: Outcome
                if task.terminationStatus == 0 {
                    outcome = .ok
                } else if errText.contains("User canceled") || errText.contains("(-128)") {
                    outcome = .userCancelled
                } else {
                    outcome = .failed(errText.isEmpty ? "Exit code \(task.terminationStatus)" : errText)
                }
                DispatchQueue.main.async { completion(outcome) }
            } catch {
                try? FileManager.default.removeItem(at: tempScriptURL)
                DispatchQueue.main.async { completion(.failed(error.localizedDescription)) }
            }
        }
    }

    private static func shellQuote(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
