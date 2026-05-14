import Foundation

@objc public protocol HelperProtocol {
    func setSleepDisabledOnBattery(_ disabled: Bool, withReply reply: @escaping (Int32) -> Void)
    func ping(withReply reply: @escaping (Int32) -> Void)
}

public enum HelperServiceConstants {
    public static let machServiceName = "ai.opencode.tray.helper"
    public static let label = "ai.opencode.tray.helper"
    public static let installedPlistPath = "/Library/LaunchDaemons/ai.opencode.tray.helper.plist"
    public static let installedHelperPath = "/usr/local/libexec/opencode-tray-helper"
}
