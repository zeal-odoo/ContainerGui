import Darwin
import Foundation

protocol SSHReadinessChecking: Sendable {
    func receivesSSHBanner(port: Int) async -> Bool
}

struct LoopbackSSHReadinessChecker: SSHReadinessChecking, Sendable {
    private let timeoutMilliseconds: Int32

    init(timeoutMilliseconds: Int32 = 750) {
        self.timeoutMilliseconds = max(1, timeoutMilliseconds)
    }

    func receivesSSHBanner(port: Int) async -> Bool {
        guard (1_024...65_535).contains(port) else { return false }
        let timeoutMilliseconds = self.timeoutMilliseconds
        return await Task.detached(priority: .utility) {
            Self.check(port: port, timeoutMilliseconds: timeoutMilliseconds)
        }.value
    }

    private static func check(port: Int, timeoutMilliseconds: Int32) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }

        let currentFlags = fcntl(descriptor, F_GETFL, 0)
        guard currentFlags >= 0,
              fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
            return false
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, SSHCreateConfiguration.fixedHost, &address.sin_addr) == 1 else {
            return false
        }

        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(timeoutMilliseconds) * 1_000_000
        let connectionResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                Darwin.connect(
                    descriptor,
                    addressPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        if connectionResult != 0 {
            guard errno == EINPROGRESS,
                  wait(descriptor: descriptor, event: POLLOUT, deadline: deadline) else {
                return false
            }
            var socketError: Int32 = 0
            var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(
                descriptor,
                SOL_SOCKET,
                SO_ERROR,
                &socketError,
                &socketErrorLength
            ) == 0, socketError == 0 else {
                return false
            }
        }

        guard wait(descriptor: descriptor, event: POLLIN, deadline: deadline) else {
            return false
        }
        var buffer = [UInt8](repeating: 0, count: 255)
        let received = buffer.withUnsafeMutableBytes { bytes in
            recv(descriptor, bytes.baseAddress, bytes.count, 0)
        }
        guard received > 0 else { return false }
        return String(decoding: buffer.prefix(received), as: UTF8.self).hasPrefix("SSH-")
    }

    private static func wait(
        descriptor: Int32,
        event: Int32,
        deadline: UInt64
    ) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { return false }
        let remainingMilliseconds = max(1, (deadline - now) / 1_000_000)
        var descriptorState = pollfd(
            fd: descriptor,
            events: Int16(event),
            revents: 0
        )
        return poll(
            &descriptorState,
            1,
            Int32(min(remainingMilliseconds, UInt64(Int32.max)))
        ) > 0 && descriptorState.revents & Int16(event) != 0
    }
}
