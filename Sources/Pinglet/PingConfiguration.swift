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

/// Controls pinging behaviour.
public struct PingConfiguration {
    /// The time between consecutive pings in seconds.
    public let pingInterval: TimeInterval
    /// Timeout interval in seconds.
    public let timeoutInterval: TimeInterval
    /// If `true`, then `Pinglet` will automatically halt and restart the pinging when the app state changes. Only applicable on iOS. If `false`, then the user is responsible for appropriately handling app state changes, see issue #15 on GitHub.
    public var handleBackgroundTransitions = true
    /// Sets the TTL flag on the socket. All requests sent from the socket will include the TTL field set to this value.
    public var timeToLive: Int?
    /// Payload size in bytes. The payload always includes a fingerprint, and a payload size smaller than the fingerprint is ignored. By default, only the fingerprint is included in the payload.
    public var payloadSize: Int = MemoryLayout<uuid_t>.size
    /// If set to `true`, when `targetCount` is reached (if set), the pinging will be halted instead of stopped. This means that the socket will be released and will be recreated if more pings are requested. Defaults to `true`.
    public var haltAfterTarget: Bool = true

    /// Initializes a `PingConfiguration` object with the given parameters.
    /// - Parameter interval: The time between consecutive pings in seconds. Defaults to 1.
    /// - Parameter timeout: Timeout interval in seconds. Defaults to 5.
    /// - Parameter timeToLive: TTL seconds. Defaults to none.
    public init(interval: TimeInterval = 1, timeout: TimeInterval = 5, timeToLive: Int? = .none) {
        pingInterval = interval
        timeoutInterval = timeout
        self.timeToLive = timeToLive
    }
}
