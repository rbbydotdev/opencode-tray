import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem()
    private let serverURLMenuItem = NSMenuItem()
    private let localURLMenuItem = NSMenuItem()
    private let startStopMenuItem = NSMenuItem(title: "Start Server", action: nil, keyEquivalent: "")
    private let openDocsMenuItem = NSMenuItem(title: "Open Server Docs", action: nil, keyEquivalent: "")
    private let copyURLMenuItem = NSMenuItem(title: "Copy Server URL", action: nil, keyEquivalent: "")
    private let copyLocalURLMenuItem = NSMenuItem(title: "Copy Local URL", action: nil, keyEquivalent: "")
    private let showQRMenuItem = NSMenuItem(title: "Show Server QR", action: nil, keyEquivalent: "")
    private let copyLogsMenuItem = NSMenuItem(title: "Copy Recent Logs", action: nil, keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(title: "Start at Login", action: nil, keyEquivalent: "")
    private let settingsMenuItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
    private let quitMenuItem = NSMenuItem(title: "Quit OpenCode Tray", action: nil, keyEquivalent: "q")

    private var settings = ServerSettings.load()
    private let qrPopover = QRCodePopoverController()

    private lazy var server = OpenCodeServer(settingsProvider: { [weak self] in
        self?.settings ?? .defaults
    })

    private lazy var settingsWindowController = SettingsWindowController(settings: settings) { [weak self] newSettings in
        self?.applySettings(newSettings, restartIfActive: true) ?? false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settings.launchAtLogin = LaunchAgentManager.shared.isEnabled
        settings.save()

        setupStatusItem()
        setupMenu()

        server.onStateChanged = { [weak self] _ in
            self?.updateMenu()
        }

        updateMenu()

        if settings.startServerOnLaunch {
            server.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop(waitUntilExit: true)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        item.menu = menu
        statusItem = item
    }

    private func setupMenu() {
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        serverURLMenuItem.isEnabled = false
        menu.addItem(serverURLMenuItem)
        localURLMenuItem.isEnabled = false
        menu.addItem(localURLMenuItem)
        menu.addItem(NSMenuItem.separator())

        configure(startStopMenuItem, action: #selector(toggleServer(_:)))
        configure(openDocsMenuItem, action: #selector(openServerDocs(_:)))
        configure(copyURLMenuItem, action: #selector(copyServerURL(_:)))
        configure(copyLocalURLMenuItem, action: #selector(copyLocalURL(_:)))
        configure(showQRMenuItem, action: #selector(showServerQR(_:)))
        configure(copyLogsMenuItem, action: #selector(copyRecentLogs(_:)))

        menu.addItem(startStopMenuItem)
        menu.addItem(openDocsMenuItem)
        menu.addItem(copyURLMenuItem)
        menu.addItem(copyLocalURLMenuItem)
        menu.addItem(showQRMenuItem)
        menu.addItem(copyLogsMenuItem)
        menu.addItem(NSMenuItem.separator())

        configure(launchAtLoginMenuItem, action: #selector(toggleLaunchAtLogin(_:)))
        configure(settingsMenuItem, action: #selector(openSettings(_:)))

        menu.addItem(launchAtLoginMenuItem)
        menu.addItem(settingsMenuItem)
        menu.addItem(NSMenuItem.separator())

        configure(quitMenuItem, action: #selector(quit(_:)))
        menu.addItem(quitMenuItem)
    }

    private func configure(_ item: NSMenuItem, action: Selector) {
        item.target = self
        item.action = action
    }

    private func updateMenu() {
        let state = server.state
        statusItem?.button?.image = TrayIconFactory.image(running: state.usesFilledIcon)
        statusItem?.button?.toolTip = "OpenCode: \(state.title)"

        statusMenuItem.title = "OpenCode: \(state.title)"
        let accessTarget = ServerURLResolver.accessTarget(for: settings)
        serverURLMenuItem.title = "Server URL: \(accessTarget.displayURLString)"

        if accessTarget.baseURLString == settings.serverURLString {
            localURLMenuItem.isHidden = true
            copyLocalURLMenuItem.isHidden = true
        } else {
            let localTarget = ServerURLResolver.localTarget(for: settings)
            localURLMenuItem.isHidden = false
            localURLMenuItem.title = "Local URL: \(localTarget.displayURLString)"
            copyLocalURLMenuItem.isHidden = false
        }

        startStopMenuItem.title = state.canStop ? "Stop Server" : "Start Server"
        startStopMenuItem.isEnabled = !state.isStarting
        openDocsMenuItem.isEnabled = true
        copyURLMenuItem.isEnabled = true
        showQRMenuItem.isEnabled = true
        copyLogsMenuItem.isEnabled = !server.recentOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let launchEnabled = LaunchAgentManager.shared.isEnabled
        launchAtLoginMenuItem.state = launchEnabled ? .on : .off
        if settings.launchAtLogin != launchEnabled {
            settings.launchAtLogin = launchEnabled
            settings.save()
        }
    }

    private func applySettings(_ newSettings: ServerSettings, restartIfActive: Bool) -> Bool {
        do {
            try LaunchAgentManager.shared.setEnabled(newSettings.launchAtLogin)
        } catch {
            showError("Could not update login item: \(error.localizedDescription)")
            return false
        }

        let shouldRestart = restartIfActive && server.state.canStop
        settings = newSettings
        settings.launchAtLogin = LaunchAgentManager.shared.isEnabled
        settings.save()

        if shouldRestart {
            server.restart()
        }

        updateMenu()
        return true
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OpenCode Tray"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func toggleServer(_ sender: Any?) {
        if server.state.canStop {
            server.stop()
        } else {
            server.start()
        }
        updateMenu()
    }

    @objc private func openServerDocs(_ sender: Any?) {
        guard let url = URL(string: "\(ServerURLResolver.accessTarget(for: settings).urlString)/doc") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyServerURL(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ServerURLResolver.accessTarget(for: settings).urlString, forType: .string)
    }

    @objc private func copyLocalURL(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ServerURLResolver.localTarget(for: settings).urlString, forType: .string)
    }

    @objc private func showServerQR(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        qrPopover.show(target: ServerURLResolver.accessTarget(for: settings), relativeTo: button)
    }

    @objc private func copyRecentLogs(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(server.recentOutput, forType: .string)
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        var updated = settings
        updated.launchAtLogin = !LaunchAgentManager.shared.isEnabled
        _ = applySettings(updated, restartIfActive: false)
    }

    @objc private func openSettings(_ sender: Any?) {
        settingsWindowController.show(settings: settings)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
