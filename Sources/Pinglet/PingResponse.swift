//
// Created by Kevin Ross on 4/23/23.
//

import Foundation

/// A struct encapsulating a ping response.
public struct PingResponse {
    /// The randomly generated identifier used in the ping header.
    public let identifier: UInt16
    /// The IP address of the host.
    public let ipAddress: String?
    /// Running sequence number, starting from 0.
    /// This number will wrap to zero when it exceeds `UInt16.max`,
    /// which is usually just 65535, and is the one used in the ping
    /// protocol. See `trueSequenceNumber` for the actual count.
    public let sequenceNumber: UInt16
    /// The true sequence number.
    public let trueSequenceNumber: UInt64
    /// Roundtrip time.
    public let duration: TimeInterval
    /// An error associated with the response.
    public let error: PingError?
    /// Response data packet size in bytes.
    public let byteCount: Int?
    /// Response IP header.
    public let ipHeader: IPHeader?
}
