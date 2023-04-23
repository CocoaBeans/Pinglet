//
// Created by Kevin Ross on 4/23/23.
//

import Foundation

/// Controls pinging behaviour.
public struct PingConfiguration {
    /// The time between consecutive pings in seconds.
    public let pingInterval: TimeInterval
    /// Timeout interval in seconds.
    public let timeoutInterval: TimeInterval
    /// If `true`, then `SwiftyPing` will automatically halt and restart the pinging when the app state changes. Only applicable on iOS. If `false`, then the user is responsible for appropriately handling app state changes, see issue #15 on GitHub.
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
    public init(interval: TimeInterval = 1, with timeout: TimeInterval = 5) {
        pingInterval = interval
        timeoutInterval = timeout
    }
    /// Initializes a `PingConfiguration` object with the given interval.
    /// - Parameter interval: The time between consecutive pings in seconds.
    /// - Note: Timeout interval will be set to 5 seconds.
    public init(interval: TimeInterval) {
        self.init(interval: interval, with: 5)
    }
}
