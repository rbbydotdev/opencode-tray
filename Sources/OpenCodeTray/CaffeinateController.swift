import AppKit
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

final class CaffeinateController {
    enum Status: Equatable {
        case off
        case active(allowsLidClosed: Bool, forcingOnBattery: Bool)
        case suspendedOnBattery(allowsLidClosed: Bool)

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }

        var summary: String {
            switch self {
            case .off:
                return "Off"
            case .active(let lid, let forced):
                var parts: [String] = []
                if lid { parts.append("Lid OK") }
                if forced { parts.append("Battery Forced") }
                return parts.isEmpty ? "On" : "On (\(parts.joined(separator: ", ")))"
            case .suspendedOnBattery:
                return "Paused (on battery)"
            }
        }
    }

    private(set) var status: Status = .off
    var onStatusChanged: ((Status) -> Void)?

    private var enabled = false
    private var allowLidClosed = false
    private var keepAwakeOnBattery = false

    private var idleAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0
    private var hasIdleAssertion = false
    private var hasSystemAssertion = false
    private var pmsetForced = false

    private var powerSourceRunLoopSource: CFRunLoopSource?

    init() {
        registerPowerSourceObserver()
    }

    deinit {
        releaseAssertions()
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func apply(enabled: Bool, allowLidClosed: Bool, keepAwakeOnBattery: Bool) {
        self.enabled = enabled
        self.allowLidClosed = allowLidClosed
        self.keepAwakeOnBattery = keepAwakeOnBattery
        refresh()
    }

    /// Synchronously revert any persistent system state (pmset). Call on app quit.
    func shutdown() {
        releaseAssertions()
        if pmsetForced {
            _ = HelperClient.shared.setSleepDisabledOnBatterySync(false, timeout: 2.0)
            pmsetForced = false
        }
    }

    private func refresh() {
        let onBattery = !isOnACPower()
        let newStatus: Status

        if !enabled {
            releaseAssertions()
            setPmsetForced(false)
            newStatus = .off
        } else if onBattery && !keepAwakeOnBattery {
            releaseAssertions()
            setPmsetForced(false)
            newStatus = .suspendedOnBattery(allowsLidClosed: allowLidClosed)
        } else {
            ensureIdleAssertion()
            if allowLidClosed {
                ensureSystemAssertion()
            } else {
                releaseSystemAssertion()
            }
            let usingHelper = onBattery && HelperClient.shared.isInstalled
            setPmsetForced(usingHelper)
            newStatus = .active(allowsLidClosed: allowLidClosed, forcingOnBattery: usingHelper)
        }

        if newStatus != status {
            status = newStatus
            onStatusChanged?(newStatus)
        }
    }

    private func setPmsetForced(_ forced: Bool) {
        guard forced != pmsetForced else { return }
        if forced && !HelperClient.shared.isInstalled { return }
        let target = forced
        HelperClient.shared.setSleepDisabledOnBattery(target) { [weak self] success in
            guard let self else { return }
            if success {
                self.pmsetForced = target
            }
        }
        // Optimistically update local state so we don't spam the helper while it's processing.
        pmsetForced = forced
    }

    private func ensureIdleAssertion() {
        guard !hasIdleAssertion else { return }
        var newID: IOPMAssertionID = 0
        let reason = "OpenCode Tray Keep Awake" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newID
        )
        if result == kIOReturnSuccess {
            idleAssertionID = newID
            hasIdleAssertion = true
        }
    }

    private func releaseIdleAssertion() {
        guard hasIdleAssertion else { return }
        IOPMAssertionRelease(idleAssertionID)
        hasIdleAssertion = false
    }

    private func ensureSystemAssertion() {
        guard !hasSystemAssertion else { return }
        var newID: IOPMAssertionID = 0
        let reason = "OpenCode Tray Keep Awake (lid closed)" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newID
        )
        if result == kIOReturnSuccess {
            systemAssertionID = newID
            hasSystemAssertion = true
        }
    }

    private func releaseSystemAssertion() {
        guard hasSystemAssertion else { return }
        IOPMAssertionRelease(systemAssertionID)
        hasSystemAssertion = false
    }

    private func releaseAssertions() {
        releaseIdleAssertion()
        releaseSystemAssertion()
    }

    private func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        else {
            return true
        }
        return providing == kIOPMACPowerKey
    }

    private func registerPowerSourceObserver() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let controller = Unmanaged<CaffeinateController>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.refresh()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceRunLoopSource = source
        }
    }
}
