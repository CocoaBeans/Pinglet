/*
  Pinglet
  This project is based on SwiftyPing: https://github.com/samiyr/SwiftyPing
  Copyright (c) 2023 Kevin Ross
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
 */

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

    public init(host: String, ipv4Address: Data) {
        self.host = host
        self.ipv4Address = ipv4Address
    }

    /// Resolves the `host`.
    public static func getIPv4AddressFromHost(host: String) throws -> Data {
        var streamError = CFStreamError()
        let cfhost: CFHost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        let status: Bool = CFHostStartInfoResolution(cfhost, .addresses, &streamError)

        var data: Data?
        if !status {
            if Int32(streamError.domain) == kCFStreamErrorDomainNetDB {
                throw SocketError.addressLookupError
            } else {
                throw SocketError.unknownHostError
            }
        } else {
            var success: DarwinBoolean = false
            guard let addresses = CFHostGetAddressing(cfhost, &success)?.takeUnretainedValue() as? [Data] else {
                throw SocketError.hostNotFound
            }

            for address in addresses {
                let addrin = address.socketAddress
                if address.count >= MemoryLayout<sockaddr>.size && addrin.sa_family == UInt8(AF_INET) {
                    data = address
                    break
                }
            }

            if data?.count == 0 || data == nil {
                throw SocketError.hostNotFound
            }
        }
        guard let returnData = data else { throw SocketError.unknownHostError }
        return returnData
    }
}
