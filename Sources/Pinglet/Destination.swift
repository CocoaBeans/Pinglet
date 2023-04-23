//
// Created by Kevin Ross on 4/23/23.
//

import Foundation

public struct Destination {
    /// The host name, can be a IP address or a URL.
    public let host: String
    /// IPv4 address of the host.
    public let ipv4Address: Data
    /// Socket address of `ipv4Address`.
    public var socketAddress: sockaddr_in? { ipv4Address.socketAddressInternet }
    /// IP address of the host.
    public var ip: String? {
        guard let address = socketAddress else { return nil }
        return String(cString: inet_ntoa(address.sin_addr), encoding: .ascii)
    }

    /// Resolves the `host`.
    public static func getIPv4AddressFromHost(host: String) throws -> Data {
        var streamError = CFStreamError()
        let cfhost: CFHost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        let status: Bool = CFHostStartInfoResolution(cfhost, .addresses, &streamError)

        var data: Data?
        if !status {
            if Int32(streamError.domain) == kCFStreamErrorDomainNetDB {
                throw PingError.addressLookupError
            } else {
                throw PingError.unknownHostError
            }
        } else {
            var success: DarwinBoolean = false
            guard let addresses = CFHostGetAddressing(cfhost, &success)?.takeUnretainedValue() as? [Data] else {
                throw PingError.hostNotFound
            }

            for address in addresses {
                let addrin = address.socketAddress
                if address.count >= MemoryLayout<sockaddr>.size && addrin.sa_family == UInt8(AF_INET) {
                    data = address
                    break
                }
            }

            if data?.count == 0 || data == nil {
                throw PingError.hostNotFound
            }
        }
        guard let returnData = data else { throw PingError.unknownHostError }
        return returnData
    }

}
