import Foundation

/// Cheap synchronous TCP connect probe for localhost ports (used by eco mode).
enum TCPLocalPortProbe {
    static func isPortOpen(host: String = "127.0.0.1", port: UInt16, timeout: TimeInterval = 0.25) -> Bool {
        guard let address = IPv4Address(host) else {
            return false
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        memcpy(&addr.sin_addr, address.rawBytes, 4)

        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        // Non-blocking connect with select() so a dead port fails fast.
        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

        let connectResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult == 0 {
            return true
        }
        guard errno == EINPROGRESS else {
            return false
        }

        var writeSet = fd_set()
        __darwin_fd_set(descriptor, &writeSet)

        var timeoutInterval = timeval(tv_sec: 0, tv_usec: __darwin_suseconds_t(timeout * 1_000_000))
        let ready = select(descriptor + 1, nil, &writeSet, nil, &timeoutInterval)
        guard ready > 0 else {
            return false
        }

        var connectError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &connectError, &length)
        return connectError == 0
    }
}

/// Minimal IPv4 address parser (avoids importing Network for a sync probe).
private struct IPv4Address {
    let rawBytes: [UInt8]

    init?(_ string: String) {
        let parts = string.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else {
            return nil
        }
        rawBytes = parts
    }
}
