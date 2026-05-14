import Foundation
import HelperProtocol

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()
        return true
    }
}

final class HelperService: NSObject, HelperProtocol {
    func setSleepDisabledOnBattery(_ disabled: Bool, withReply reply: @escaping (Int32) -> Void) {
        let value = disabled ? "1" : "0"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-b", "disablesleep", value]
        do {
            try task.run()
            task.waitUntilExit()
            reply(task.terminationStatus)
        } catch {
            reply(-1)
        }
    }

    func ping(withReply reply: @escaping (Int32) -> Void) {
        reply(0)
    }
}
