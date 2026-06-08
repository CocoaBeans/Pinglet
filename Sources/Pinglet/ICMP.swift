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

// MARK: ICMP

/// Format of IPv4 header (20 bytes minimum)
public struct IPHeader: Sendable {
    public let versionAndHeaderLength: UInt8
    public let differentiatedServices: UInt8
    public let totalLength: UInt16
    public let identification: UInt16
    public let flagsAndFragmentOffset: UInt16
    public let timeToLive: UInt8
    public let `protocol`: UInt8
    public let headerChecksum: UInt16
    public let sourceAddress: (UInt8, UInt8, UInt8, UInt8)
    public let destinationAddress: (UInt8, UInt8, UInt8, UInt8)

    public static let minSize = 20

    /// Safe manual parsing instead of `load(as:)` which has undefined behavior if:
    /// - Struct layout doesn't match exactly (padding, alignment differences across platforms)
    /// - Data is shorter than struct size (reads out of bounds)
    /// - Endianness differs (network byte order vs host byte order)
    /// This approach explicitly reads each byte and constructs values with known endianness.
    init?(data: Data) {
        guard data.count >= Self.minSize else { return nil }
        let bytes = [UInt8](data.prefix(Self.minSize))

        versionAndHeaderLength = bytes[0]
        differentiatedServices = bytes[1]
        totalLength = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        identification = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        flagsAndFragmentOffset = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        timeToLive = bytes[8]
        `protocol` = bytes[9]
        headerChecksum = UInt16(bytes[10]) << 8 | UInt16(bytes[11])
        sourceAddress = (bytes[12], bytes[13], bytes[14], bytes[15])
        destinationAddress = (bytes[16], bytes[17], bytes[18], bytes[19])
    }

    var headerLength: Int {
        Int(versionAndHeaderLength & 0x0F) * 4
    }

    var isIPv4: Bool {
        versionAndHeaderLength & 0xF0 == 0x40
    }

    var isICMP: Bool {
        `protocol` == IPPROTO_ICMP
    }
}

/// ICMP header structure (8 bytes + 16 bytes UUID payload = 24 bytes)
public struct ICMPHeader: Sendable {
    public let type: UInt8
    public let code: UInt8
    public var checksum: UInt16
    public let identifier: UInt16
    public let sequenceNumber: UInt16
    public let payload: [UInt8]

    public static let headerSize = 8
    public static let payloadSize = 16
    public static let totalSize = headerSize + payloadSize

    /// `identifier` and `sequenceNumber` are stored in host byte order:
    /// `from(data:offset:)` decodes the big-endian wire bytes, and
    /// `createICMPPackage` constructs them from host-order values. These
    /// accessors therefore return the fields directly.
    public var identifierToHost: UInt16 { identifier }
    public var sequenceNumberToHost: UInt16 { sequenceNumber }

    /// Safe manual parsing with explicit bounds checking.
    /// Unlike `load(as:)` / `load(fromByteOffset:as:)` this:
    /// - Validates data length before reading
    /// - Doesn't depend on struct memory layout / padding
    /// - Handles endianness explicitly (network = big-endian)
    /// - Returns typed errors instead of crashing on malformed packets
    static func from(data: Data, offset: Int = 0) throws -> ICMPHeader {
        guard data.count >= offset + Self.totalSize else {
            throw PingError.invalidLength(received: data.count)
        }

        // Anchor to startIndex so a sliced Data (non-zero startIndex) can't trap.
        let start = data.startIndex + offset
        let bytes = [UInt8](data[start ..< start + Self.totalSize])

        let type = bytes[0]
        let code = bytes[1]
        let checksum = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        let identifier = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        let sequenceNumber = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let payload = Array(bytes[8..<24])

        return ICMPHeader(
            type: type,
            code: code,
            checksum: checksum,
            identifier: identifier,
            sequenceNumber: sequenceNumber,
            payload: payload
        )
    }

    /// Serializes the header to wire format in network (big-endian) byte order —
    /// the inverse of `from(data:offset:)`. Emits the 8-byte header followed by
    /// `payload`, but not any trailing additional payload.
    ///
    /// The struct cannot be serialized with `Data(bytes:count:)` because `payload`
    /// is a heap-backed `Array`; a raw memory copy would emit the array's pointer
    /// instead of the payload bytes.
    func serialized() -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Self.headerSize + payload.count)
        bytes.append(type)
        bytes.append(code)
        bytes.append(UInt8(checksum >> 8))
        bytes.append(UInt8(checksum & 0xFF))
        bytes.append(UInt8(identifier >> 8))
        bytes.append(UInt8(identifier & 0xFF))
        bytes.append(UInt8(sequenceNumber >> 8))
        bytes.append(UInt8(sequenceNumber & 0xFF))
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }
}


extension ICMPHeader {
    func computeChecksum(additionalPayload: [UInt8] = []) throws -> UInt16 {
        // Manual byte-wise construction avoids `load(as:)` which assumes
        // host endianness and exact struct layout. Network byte order is big-endian.
        let typeCode = UInt16(type) << 8 | UInt16(code)
        var sum: UInt64 = UInt64(typeCode) + UInt64(identifier) + UInt64(sequenceNumber)
        let payload = self.payload + additionalPayload

        guard payload.count % 2 == 0 else { throw PingError.unexpectedPayloadLength }

        var i = 0
        while i < payload.count {
            // Explicit big-endian word assembly - no unsafe pointer loads
            let word = UInt16(payload[i]) << 8 | UInt16(payload[i + 1])
            sum += UInt64(word)
            i += 2
        }
        // Fold carry bits (one's complement addition)
        while sum >> 16 != 0 {
            sum = (sum & 0xffff) + (sum >> 16)
        }

        guard sum <= UInt16.max else { throw PingError.checksumOutOfBounds }

        return ~UInt16(sum)
    }

    /// Safe header offset calculation with validation at each step.
    /// Previous version had a precedence bug: `& 0x0F * 4` parsed as `& (0x0F * 4)`
    /// instead of `(& 0x0F) * 4`. This version uses explicit parentheses
    /// and validates IPv4 + ICMP protocol before trusting header length.
    internal static func headerOffset(in ipPacket: Data) -> Int? {
        guard ipPacket.count >= IPHeader.minSize else { return nil }

        guard let ipHeader = IPHeader(data: ipPacket) else { return nil }
        guard ipHeader.isIPv4 && ipHeader.isICMP else { return nil }

        let headerLength = ipHeader.headerLength
        guard ipPacket.count >= headerLength + ICMPHeader.totalSize else { return nil }

        return headerLength
    }
}

/// ICMP echo types
public enum ICMPType: UInt8 {
    case EchoReply = 0
    case EchoRequest = 8
}
