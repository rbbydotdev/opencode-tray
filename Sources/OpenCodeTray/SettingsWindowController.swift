import AppKit

final class SettingsWindowController: NSWindowController {
    private let onSave: (ServerSettings) -> Bool

    private let executableField = NSTextField()
    private let detectExecutableButton = NSButton(title: "Detect", target: nil, action: nil)
    private let browseExecutableButton = NSButton(title: "Browse...", target: nil, action: nil)
    private let workingDirectoryField = NSTextField()
    private let hostnameField = NSTextField()
    private let portField = NSTextField()
    private let mdnsCheckbox = NSButton(checkboxWithTitle: "Enable mDNS discovery", target: nil, action: nil)
    private let mdnsDomainField = NSTextField()
    private let corsTextView = NSTextView()
    private let authUsernameField = NSTextField()
    private let authPasswordField = NSSecureTextField()
    private let includeAuthInSharedURLsCheckbox = NSButton(checkboxWithTitle: "Include auth in QR and copied URLs", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Start at Login", target: nil, action: nil)
    private let startOnLaunchCheckbox = NSButton(checkboxWithTitle: "Run server when OpenCode Tray opens", target: nil, action: nil)

    init(settings: ServerSettings, onSave: @escaping (ServerSettings) -> Bool) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 674),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenCode Server Settings"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        buildContent()
        load(settings)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(settings: ServerSettings) {
        load(settings)
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
        ])

        addSection("opencode")
        addRow("Executable", makeExecutableControl(), to: stack)
        addRow("Working Directory", workingDirectoryField, to: stack)

        addSection("Server")
        addRow("Hostname", hostnameField, to: stack)
        addRow("Port", portField, to: stack)
        addCheckboxRow(mdnsCheckbox, to: stack)
        addRow("mDNS Domain", mdnsDomainField, to: stack)
        addRow("CORS Origins", makeCORSEditor(), to: stack, alignTop: true)

        addSection("Authentication")
        addRow("Username", authUsernameField, to: stack)
        addRow("Password", authPasswordField, to: stack)
        addCheckboxRow(includeAuthInSharedURLsCheckbox, to: stack)

        addSection("App")
        addCheckboxRow(launchAtLoginCheckbox, to: stack)
        addCheckboxRow(startOnLaunchCheckbox, to: stack)

        let note = NSTextField(wrappingLabelWithString: "Saving settings restarts the server if it is running; no macOS reboot is needed. Password is optional and stored in Keychain. Auth URLs embed the password, so only enable them for trusted devices/networks.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        note.translatesAutoresizingMaskIntoConstraints = false
        note.widthAnchor.constraint(equalToConstant: 500).isActive = true
        stack.addArrangedSubview(note)

        stack.addArrangedSubview(makeButtonRow())

        mdnsCheckbox.target = self
        mdnsCheckbox.action = #selector(toggleMDNS(_:))
        detectExecutableButton.target = self
        detectExecutableButton.action = #selector(detectExecutable(_:))
        browseExecutableButton.target = self
        browseExecutableButton.action = #selector(browseExecutable(_:))
    }

    private func addSection(_ title: String) {
        guard let stack = window?.contentView?.subviews.first as? NSStackView else { return }
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
    }

    private func addRow(_ label: String, _ control: NSView, to stack: NSStackView, alignTop: Bool = false) {
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 350).isActive = true

        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.textColor = .secondaryLabelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = alignTop ? .top : .firstBaseline
        stack.addArrangedSubview(row)
    }

    private func addCheckboxRow(_ checkbox: NSButton, to stack: NSStackView) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 142).isActive = true

        let row = NSStackView(views: [spacer, checkbox])
        row.orientation = .horizontal
        row.spacing = 0
        row.alignment = .centerY
        stack.addArrangedSubview(row)
    }

    private func makeExecutableControl() -> NSStackView {
        executableField.placeholderString = "opencode or /path/to/opencode"
        executableField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [executableField, detectExecutableButton, browseExecutableButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func makeCORSEditor() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 82).isActive = true

        corsTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        corsTextView.isVerticallyResizable = true
        corsTextView.isHorizontallyResizable = false
        corsTextView.autoresizingMask = [.width]
        corsTextView.textContainer?.containerSize = NSSize(width: 350, height: CGFloat.greatestFiniteMagnitude)
        corsTextView.textContainer?.widthTracksTextView = true
        scrollView.documentView = corsTextView

        return scrollView
    }

    private func makeButtonRow() -> NSStackView {
        let resetButton = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults(_:)))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        let row = NSStackView(views: [resetButton, spacer, cancelButton, saveButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return row
    }

    private func load(_ settings: ServerSettings) {
        executableField.stringValue = settings.executable
        workingDirectoryField.stringValue = settings.workingDirectory
        hostnameField.stringValue = settings.hostname
        portField.stringValue = String(settings.port)
        mdnsCheckbox.state = settings.enableMDNS ? .on : .off
        mdnsDomainField.stringValue = settings.mdnsDomain
        corsTextView.string = settings.corsOrigins.joined(separator: "\n")
        authUsernameField.stringValue = settings.authUsername
        authPasswordField.stringValue = settings.authPassword
        includeAuthInSharedURLsCheckbox.state = settings.includeAuthInSharedURLs ? .on : .off
        launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off
        startOnLaunchCheckbox.state = settings.startServerOnLaunch ? .on : .off
        mdnsDomainField.isEnabled = mdnsCheckbox.state == .on
    }

    private func collectSettings() -> ServerSettings? {
        let executable = executableField.stringValue.trimmed
        guard !executable.isEmpty else {
            showValidationError("Set the opencode executable. Use 'opencode' if it is available on PATH, or an absolute path such as /opt/homebrew/bin/opencode.")
            return nil
        }

        let workingDirectory = workingDirectoryField.stringValue.trimmed
        guard !workingDirectory.isEmpty else {
            showValidationError("Set a working directory for opencode serve.")
            return nil
        }

        var isDirectory: ObjCBool = false
        let expandedWorkingDirectory = NSString(string: workingDirectory).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedWorkingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            showValidationError("The working directory does not exist or is not a folder.")
            return nil
        }

        let hostname = hostnameField.stringValue.trimmed
        guard !hostname.isEmpty else {
            showValidationError("Hostname cannot be empty.")
            return nil
        }

        guard let port = Int(portField.stringValue.trimmed), (1...65_535).contains(port) else {
            showValidationError("Port must be a number between 1 and 65535.")
            return nil
        }

        let enableMDNS = mdnsCheckbox.state == .on
        let mdnsDomain = mdnsDomainField.stringValue.trimmed
        if enableMDNS && mdnsDomain.isEmpty {
            showValidationError("mDNS domain cannot be empty when mDNS discovery is enabled.")
            return nil
        }

        let corsOrigins = corsTextView.string
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .filter { !$0.isEmpty }

        let authUsername = authUsernameField.stringValue.trimmed
        let authPassword = authPasswordField.stringValue
        if !authPassword.isEmpty && authUsername.isEmpty {
            showValidationError("Username cannot be empty when password authentication is enabled.")
            return nil
        }

        return ServerSettings(
            executable: executable,
            workingDirectory: workingDirectory,
            hostname: hostname,
            port: port,
            enableMDNS: enableMDNS,
            mdnsDomain: mdnsDomain,
            corsOrigins: corsOrigins,
            authUsername: authUsername,
            authPassword: authPassword,
            includeAuthInSharedURLs: includeAuthInSharedURLsCheckbox.state == .on,
            launchAtLogin: launchAtLoginCheckbox.state == .on,
            startServerOnLaunch: startOnLaunchCheckbox.state == .on
        )
    }

    private func showValidationError(_ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Check Settings"
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }

    @objc private func toggleMDNS(_ sender: Any?) {
        mdnsDomainField.isEnabled = mdnsCheckbox.state == .on
    }

    @objc private func detectExecutable(_ sender: Any?) {
        let currentValue = executableField.stringValue.trimmed
        let requestedExecutable = currentValue.isEmpty ? "opencode" : currentValue
        let environment = ServerSettings.defaults.environment(merging: ProcessInfo.processInfo.environment)

        if let url = ExecutableLocator.resolve(requestedExecutable, environment: environment) ?? ExecutableLocator.resolve("opencode", environment: environment) {
            executableField.stringValue = url.path
        } else {
            showValidationError("Could not find opencode. Install it first, or use Browse to select the executable manually.")
        }
    }

    @objc private func browseExecutable(_ sender: Any?) {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.title = "Select opencode Executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Use Executable"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.executableField.stringValue = url.path
        }
    }

    @objc private func resetDefaults(_ sender: Any?) {
        load(.defaults)
    }

    @objc private func cancel(_ sender: Any?) {
        close()
    }

    @objc private func save(_ sender: Any?) {
        guard let settings = collectSettings() else { return }
        if onSave(settings) {
            close()
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
