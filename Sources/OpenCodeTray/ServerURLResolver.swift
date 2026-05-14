import Foundation
import Darwin

struct ServerAccessTarget {
    var urlString: String
    var displayURLString: String
    var baseURLString: String
    var subtitle: String
    var note: String?
}

enum ServerURLResolver {
    static func accessTarget(for settings: ServerSettings, runtimePort: Int? = nil) -> ServerAccessTarget {
        var settings = settings
        if let runtimePort { settings.port = runtimePort }
        let hostname = settings.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = NetworkAddressResolver.bestCandidate()

        if isWildcard(hostname) {
            if let candidate {
                return makeTarget(
                    host: candidate.host,
                    port: settings.port,
                    settings: settings,
                    subtitle: "Using \(candidate.label)",
                    note: candidate.note
                )
            }

            return makeTarget(
                host: settings.localURLHost,
                port: settings.port,
                settings: settings,
                subtitle: "No VPN or LAN address found",
                note: "The server is listening on all interfaces, but no shareable IPv4 address was detected."
            )
        }

        if isLoopback(hostname) {
            let reachableHint = candidate.map { " Detected \($0.label): \($0.host)." } ?? ""
            return makeTarget(
                host: settings.localURLHost,
                port: settings.port,
                settings: settings,
                subtitle: "Local Mac only",
                note: "For phone access, set Hostname to 0.0.0.0 or a VPN IP in Settings, then restart the server.\(reachableHint)"
            )
        }

        return makeTarget(
            host: settings.localURLHost,
            port: settings.port,
            settings: settings,
            subtitle: "Using configured host",
            note: nil
        )
    }

    static func detectedNetworkTarget(for settings: ServerSettings) -> ServerAccessTarget? {
        guard let candidate = NetworkAddressResolver.bestCandidate() else { return nil }
        return makeTarget(
            host: candidate.host,
            port: settings.port,
            settings: settings,
            subtitle: candidate.label,
            note: candidate.note
        )
    }

    static func localTarget(for settings: ServerSettings, runtimePort: Int? = nil) -> ServerAccessTarget {
        var settings = settings
        if let runtimePort { settings.port = runtimePort }
        return makeTarget(
            host: settings.localURLHost,
            port: settings.port,
            settings: settings,
            subtitle: "Local Mac URL",
            note: nil
        )
    }

    static func docTarget(for settings: ServerSettings, runtimePort: Int? = nil) -> ServerAccessTarget {
        let target = accessTarget(for: settings, runtimePort: runtimePort)
        guard var components = URLComponents(string: target.urlString) else { return target }
        components.path = "/doc"

        let displayComponents = URLComponents(string: target.displayURLString)
        var display = target.displayURLString
        if var displayComponents {
            displayComponents.path = "/doc"
            display = displayComponents.string ?? display
        }

        return ServerAccessTarget(
            urlString: components.string ?? target.urlString,
            displayURLString: display,
            baseURLString: "\(target.baseURLString)/doc",
            subtitle: target.subtitle,
            note: target.note
        )
    }

    static func isLocalOnly(_ settings: ServerSettings) -> Bool {
        isLoopback(settings.hostname.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func isWildcard(_ host: String) -> Bool {
        host == "0.0.0.0" || host == "::" || host == "[::]"
    }

    private static func isLoopback(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        return lowercased == "localhost" || lowercased == "::1" || lowercased == "[::1]" || lowercased.hasPrefix("127.")
    }

    private static func makeTarget(host: String, port: Int, settings: ServerSettings, subtitle: String, note: String?) -> ServerAccessTarget {
        let baseURLString = "http://\(host):\(port)"
        let authNote = settings.basicAuthEnabled ? "OpenCode Basic Auth is enabled; enter the username and password manually if the browser prompts." : nil

        return ServerAccessTarget(
            urlString: baseURLString,
            displayURLString: baseURLString,
            baseURLString: baseURLString,
            subtitle: subtitle,
            note: [note, authNote].compactMap { $0 }.joined(separator: " ").nilIfEmpty
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct NetworkAddressCandidate {
    var host: String
    var interfaceName: String
    var label: String
    var note: String?
    var priority: Int
}

private enum NetworkAddressResolver {
    static func bestCandidate() -> NetworkAddressCandidate? {
        candidates().sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.interfaceName < rhs.interfaceName
            }
            return lhs.priority < rhs.priority
        }.first
    }

    private static func candidates() -> [NetworkAddressCandidate] {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0 else { return [] }
        defer { freeifaddrs(interfaceAddresses) }

        var result: [NetworkAddressCandidate] = []
        var cursor = interfaceAddresses

        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard let host = numericHost(from: address), !isLinkLocal(host) else { continue }

            let interfaceName = String(cString: interface.ifa_name)
            if let candidate = classify(host: host, interfaceName: interfaceName) {
                result.append(candidate)
            }
        }

        return result
    }

    private static func numericHost(from address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else { return nil }
        return String(cString: host)
    }

    private static func classify(host: String, interfaceName: String) -> NetworkAddressCandidate? {
        let lowercasedName = interfaceName.lowercased()

        if isTailscale(host) || lowercasedName.contains("tailscale") {
            return NetworkAddressCandidate(
                host: host,
                interfaceName: interfaceName,
                label: "Tailscale IP",
                note: "Your phone must also be connected to the same Tailscale tailnet.",
                priority: 0
            )
        }

        if isWireGuardLike(interfaceName: lowercasedName, host: host) {
            return NetworkAddressCandidate(
                host: host,
                interfaceName: interfaceName,
                label: "WireGuard/VPN IP",
                note: "Your phone must also be connected to the same VPN.",
                priority: 1
            )
        }

        if isPrivateIPv4(host) {
            return NetworkAddressCandidate(
                host: host,
                interfaceName: interfaceName,
                label: "LAN IP",
                note: "Your phone must be on the same local network.",
                priority: 2
            )
        }

        return nil
    }

    private static func isWireGuardLike(interfaceName: String, host: String) -> Bool {
        guard isPrivateIPv4(host) else { return false }
        return interfaceName.hasPrefix("utun") || interfaceName.hasPrefix("wg") || interfaceName.contains("wireguard")
    }

    private static func isTailscale(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host), octets.count == 4 else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host), octets.count == 4 else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        return false
    }

    private static func isLinkLocal(_ host: String) -> Bool {
        guard let octets = ipv4Octets(host), octets.count == 4 else { return false }
        return octets[0] == 169 && octets[1] == 254
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return octets
    }
}
