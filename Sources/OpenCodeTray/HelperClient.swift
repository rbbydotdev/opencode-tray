import Foundation
import HelperProtocol

final class HelperClient {
    static let shared = HelperClient()

    private var connection: NSXPCConnection?
    private let queue = DispatchQueue(label: "ai.opencode.tray.helperclient")

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperServiceConstants.installedPlistPath)
            && FileManager.default.fileExists(atPath: HelperServiceConstants.installedHelperPath)
    }

    func setSleepDisabledOnBattery(_ disabled: Bool, completion: @escaping (Bool) -> Void) {
        guard isInstalled else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let proxy = remoteProxy { DispatchQueue.main.async { completion(false) } }
        proxy.setSleepDisabledOnBattery(disabled) { exitCode in
            DispatchQueue.main.async { completion(exitCode == 0) }
        }
    }

    func setSleepDisabledOnBatterySync(_ disabled: Bool, timeout: TimeInterval) -> Bool {
        guard isInstalled else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        setSleepDisabledOnBattery(disabled) { ok in
            success = ok
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return success
    }

    func ping(completion: @escaping (Bool) -> Void) {
        guard isInstalled else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let proxy = remoteProxy { DispatchQueue.main.async { completion(false) } }
        proxy.ping { _ in
            DispatchQueue.main.async { completion(true) }
        }
    }

    func invalidate() {
        queue.sync {
            connection?.invalidate()
            connection = nil
        }
    }

    private func remoteProxy(onError: @escaping () -> Void) -> HelperProtocol {
        let conn = ensureConnection()
        return conn.remoteObjectProxyWithErrorHandler { error in
            NSLog("OpenCodeTray helper XPC error: \(error)")
            onError()
        } as! HelperProtocol
    }

    private func ensureConnection() -> NSXPCConnection {
        return queue.sync {
            if let existing = connection { return existing }
            let conn = NSXPCConnection(
                machServiceName: HelperServiceConstants.machServiceName,
                options: .privileged
            )
            conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            conn.invalidationHandler = { [weak self] in
                self?.queue.async { self?.connection = nil }
            }
            conn.interruptionHandler = { [weak self] in
                self?.queue.async {
                    self?.connection?.invalidate()
                    self?.connection = nil
                }
            }
            conn.resume()
            connection = conn
            return conn
        }
    }
}
