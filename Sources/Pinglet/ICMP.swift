//
// Created by Kevin Ross on 4/23/23.
//

import Foundation

// MARK: ICMP

/// Format of IPv4 header
public struct IPHeader {
    public var versionAndHeaderLength: UInt8
    public var differentiatedServices: UInt8
    public var totalLength: UInt16
    public var identification: UInt16
    public var flagsAndFragmentOffset: UInt16
    public var timeToLive: UInt8
    public var `protocol`: UInt8
    public var headerChecksum: UInt16
    public var sourceAddress: (UInt8, UInt8, UInt8, UInt8)
    public var destinationAddress: (UInt8, UInt8, UInt8, UInt8)
}

/// ICMP header structure
public struct ICMPHeader {
    /// Type of message
    var type: UInt8
    /// Type sub code
    var code: UInt8
    /// One's complement checksum of struct
    var checksum: UInt16
    /// Identifier
    var identifier: UInt16
    /// Sequence number
    var sequenceNumber: UInt16
    /// UUID payload
    var payload: uuid_t
}

/// ICMP echo types
public enum ICMPType: UInt8 {
    case EchoReply = 0
    case EchoRequest = 8
}
