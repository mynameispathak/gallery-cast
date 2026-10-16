import Foundation

/// Chooses the local IPv4 address to advertise to a Cast device.
///
/// The Mac's photo server listens on every interface, but the URL handed
/// to the receiver must name one address the device can actually reach —
/// normally the interface it shares a subnet with.
enum LocalAddress {

    struct Interface: Equatable, Sendable {
        var name: String
        var address: String
        var netmask: String
    }

    /// Live IPv4 interfaces from `getifaddrs`.
    static func interfaces() -> [Interface] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var interfaces: [Interface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }

            guard let sockaddrPtr = entry.pointee.ifa_addr,
                  sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }

            var address = sockaddr_in()
            memcpy(&address, sockaddrPtr, Int(sockaddrPtr.pointee.sa_len))

            var netmask = sockaddr_in()
            if let netmaskPtr = entry.pointee.ifa_netmask {
                memcpy(&netmask, netmaskPtr, Int(netmaskPtr.pointee.sa_len))
            }

            interfaces.append(
                Interface(
                    name: String(cString: entry.pointee.ifa_name),
                    address: Self.string(from: address.sin_addr),
                    netmask: Self.string(from: netmask.sin_addr)
                )
            )
        }
        return interfaces
    }

    /// The address to put in media URLs for a device at `deviceIPv4`.
    ///
    /// Prefers an interface sharing the device's subnet — Wi-Fi first,
    /// loopback included so loopback devices get loopback URLs. Anything
    /// unmatched falls back to the first non-loopback, non-link-local
    /// IPv4 address.
    static func bestAddress(interfaces: [Interface], deviceIPv4: String) -> String? {
        if let device = Self.ipv4Value(deviceIPv4) {
            let sharedSubnet = interfaces.filter { interface in
                guard let address = Self.ipv4Value(interface.address),
                      let mask = Self.ipv4Value(interface.netmask)
                else { return false }
                return (address & mask) == (device & mask)
            }
            if let match = sharedSubnet.first(where: { $0.name.hasPrefix("en") })
                ?? sharedSubnet.first {
                return match.address
            }
        }

        let usable = interfaces.filter {
            $0.name != "lo0" && !$0.address.hasPrefix("169.254.")
        }
        return usable.first(where: { $0.name.hasPrefix("en") })?.address
            ?? usable.first?.address
    }

    // MARK: Socket helpers

    private static func string(from address: in_addr) -> String {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return "0.0.0.0"
        }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Dotted-quad string to host-endian integer, or nil if malformed.
    private static func ipv4Value(_ string: String) -> UInt32? {
        var address = in_addr()
        guard string.withCString({ inet_pton(AF_INET, $0, &address) == 1 })
        else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }
}
