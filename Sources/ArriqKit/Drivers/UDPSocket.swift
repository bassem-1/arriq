import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// minimal ipv4 udp socket for the govee lan api.
final class UDPSocket {
    private let fd: Int32

    /// bindPort nil leaves the socket on an ephemeral port
    init?(bindPort: UInt16?) {
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))
        if let port = bindPort {
            let addr = Self.addr("0.0.0.0", port)
            let bound = withUnsafePointer(to: addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0 else {
                close(fd)
                return nil
            }
        }
    }

    deinit { close(fd) }

    static func addr(_ ip: String, _ port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = inet_addr(ip)
        return a
    }

    @discardableResult
    func send(_ data: Data, to ip: String, port: UInt16) -> Bool {
        let a = Self.addr(ip, port)
        let n = data.withUnsafeBytes { buf -> Int in
            withUnsafePointer(to: a) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return n == data.count
    }

    /// first datagram before the timeout, as (payload, sender ip)
    func receive(timeout: TimeInterval) -> (Data, String)? {
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let deadline = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let cap = buf.count
            let n = buf.withUnsafeMutableBytes { raw -> Int in
                withUnsafeMutablePointer(to: &from) { fp in
                    fp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, raw.baseAddress, cap, 0, sa, &len)
                    }
                }
            }
            if n > 0 {
                let ip = String(cString: inet_ntoa(from.sin_addr))
                return (Data(buf[0..<n]), ip)
            }
        }
        return nil
    }
}
