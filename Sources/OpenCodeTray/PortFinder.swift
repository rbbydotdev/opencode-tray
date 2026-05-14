import Foundation
import Darwin

enum PortFinder {
    /// Returns the first available TCP port >= preferredPort, scanning up to `maxAttempts` ports.
    /// Falls back to nil if none in range are available.
    static func findAvailable(startingFrom preferredPort: Int, maxAttempts: Int = 50) -> Int? {
        for candidate in preferredPort..<min(preferredPort + maxAttempts, 65_536) {
            if isAvailable(candidate) {
                return candidate
            }
        }
        return nil
    }

    static func isAvailable(_ port: Int) -> Bool {
        guard (1...65_535).contains(port) else { return false }
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = in_addr_t(INADDR_ANY).bigEndian

        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
