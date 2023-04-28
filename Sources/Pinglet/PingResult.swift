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
