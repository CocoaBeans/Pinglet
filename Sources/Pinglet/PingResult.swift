//
// Created by Kevin Ross on 4/23/23.
//

import Foundation

/// A struct encapsulating the results of a ping instance.
public struct PingResult {

    /// Collection of all responses, including errored or timed out.
    public let responses: [PingResponse]
    /// Number of packets sent.
    public let packetsTransmitted: UInt64
    /// Number of packets received.
    public let packetsReceived: UInt64
    /// The packet loss. If the number of packets transmitted (`packetsTransmitted`) is zero, returns `nil`.
    public var packetLoss: Double? {
        if packetsTransmitted == 0 { return nil }
        return 1 - Double(packetsReceived) / Double(packetsTransmitted)
    }
    /// Roundtrip statistics, including min, max, average and stddev.
    public let roundtrip: Roundtrip?

    /// A struct encapsulating the roundtrip statistics.
    public struct Roundtrip {
        /// The smallest roundtrip time.
        public let minimum: Double
        /// The largest roundtrip time.
        public let maximum: Double
        /// The average (mean) roundtrip time.
        public let average: Double
        /// The standard deviation of the roundtrip times.
        /// - Note: Standard deviation is calculated without Bessel's correction and thus gives zero if only one packet is received.
        public let standardDeviation: Double
    }
}
