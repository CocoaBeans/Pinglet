/*
  Socket2Me
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

    /// Initializes a `Destination` from a literal IPv4 address string, building the
    /// socket address directly. Unlike `init(host:)`, this performs no DNS resolution
    /// and therefore never blocks or fails.
    /// - Parameter ipv4String: A dotted-decimal IPv4 address (e.g. `"1.1.1.1"`).
    public init(ipv4String: String) {
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = UInt8(AF_INET)
        socketAddress.sin_port = 0
        socketAddress.sin_addr.s_addr = inet_addr(ipv4String.cString(using: .utf8))
        self.host = ipv4String
        self.ipv4Address = Data(bytes: &socketAddress, count: MemoryLayout<sockaddr_in>.size)
    }

    @available(*, deprecated, message: "Blocking DNS resolution. Use 'init(host:) async throws' instead.")
    public init(host: String) throws {
        self.host = host
        self.ipv4Address = try Destination.performBlockingResolution(host: host)
    }

    /// Asynchronously resolves the given `host` and creates a `Destination`.
    ///
    /// DNS resolution runs off the calling task (see `resolve(host:)`), so awaiting this
    /// initializer never blocks the caller's thread.
    /// - Parameter host: A host name or IPv4 address string.
    /// - Throws: A `SocketError` if the host could not be resolved.
    public init(host: String) async throws {
        self.host = host
        self.ipv4Address = try await Destination.resolve(host: host)
    }

    /// A dedicated queue for the blocking `CFHost` resolution.
    ///
    /// Running resolution here — rather than on the Swift concurrency cooperative pool —
    /// guarantees a slow DNS lookup can never starve the shared executor. It is concurrent
    /// so independent lookups don't serialize behind one another.
    private static let resolutionQueue = DispatchQueue(label: "Pinglet.Destination.dnsResolution",
                                                       qos: .userInitiated,
                                                       attributes: .concurrent)

    /// Asynchronously resolves `host` to its IPv4 socket-address bytes.
    ///
    /// This bridges the blocking `getIPv4AddressFromHost(host:)` resolution onto a dedicated
    /// queue via a checked continuation, so neither the awaiting task nor a cooperative
    /// concurrency thread is blocked while the lookup is in flight.
    /// - Parameter host: A host name or IPv4 address string.
    /// - Returns: The `Data` wrapping the resolved `sockaddr_in`.
    /// - Throws: A `SocketError` if the host could not be resolved.
    public static func resolve(host: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            resolutionQueue.async {
                do {
                    continuation.resume(returning: try performBlockingResolution(host: host))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Resolves the `host`. This call blocks the current thread until resolution completes;
    /// prefer the asynchronous `resolve(host:)` from concurrency contexts.
    @available(*, deprecated, message: "Blocking DNS resolution. Use 'resolve(host:) async throws' instead.")
    public static func getIPv4AddressFromHost(host: String) throws -> Data {
        try performBlockingResolution(host: host)
    }

    /// The synchronous `CFHost` resolution core shared by the blocking entry point
    /// (`getIPv4AddressFromHost(host:)`) and the asynchronous `resolve(host:)`.
    private static func performBlockingResolution(host: String) throws -> Data {
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
