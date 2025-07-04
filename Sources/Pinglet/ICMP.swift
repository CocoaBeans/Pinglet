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

/// Format of IPv4 header
public struct IPHeader: Sendable {
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

    init(data: Data) {
        self = data.withUnsafeBytes { $0.load(as: IPHeader.self) }
    }
}

/// ICMP header structure
public struct ICMPHeader: Sendable {
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

    var identifierToHost: UInt16 {
        CFSwapInt16BigToHost(identifier)
    }
    var sequenceNumberToHost: UInt16 {
        CFSwapInt16BigToHost(sequenceNumber)
    }

    static func from(data: Data) throws -> ICMPHeader {
        let icmpHeaderSize = MemoryLayout<ICMPHeader>.size
        let ipHeaderSize = MemoryLayout<IPHeader>.size
        guard data.count >= icmpHeaderSize
        else { throw PingError.invalidLength(received: data.count) }

        if data.count >= ipHeaderSize + icmpHeaderSize {
            guard let headerOffset: Int = ICMPHeader.headerOffset(in: data)
            else { throw PingError.invalidHeaderOffset }

            return data.withUnsafeBytes { $0.load(fromByteOffset: headerOffset, as: ICMPHeader.self) }
        }
        else if data.count == icmpHeaderSize {
            return data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: ICMPHeader.self) }
        }
        throw PingError.invalidLength(received: data.count)
    }
}


extension ICMPHeader {
    func computeChecksum(additionalPayload: [UInt8] = []) throws -> UInt16 {
        let typeCode = Data([type, code]).withUnsafeBytes { $0.load(as: UInt16.self) }
        var sum: UInt64 = UInt64(typeCode) + UInt64(identifier) + UInt64(sequenceNumber)
        let payload: [UInt8] = ICMPHeader.convert(payload: payload) + additionalPayload

        guard payload.count % 2 == 0 else { throw PingError.unexpectedPayloadLength }

        var i = 0
        while i < payload.count {
            guard payload.indices.contains(i + 1) else { throw PingError.unexpectedPayloadLength }
            // Convert two 8 byte ints to one 16 byte int
            sum += Data([payload[i], payload[i + 1]]).withUnsafeBytes { UInt64($0.load(as: UInt16.self)) }
            i += 2
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xffff) + (sum >> 16)
        }

        guard sum < UInt16.max else { throw PingError.checksumOutOfBounds }

        return ~UInt16(sum)
    }

    internal static func convert(payload: uuid_t) -> [UInt8] {
        let p = payload
        return [p.0, p.1, p.2, p.3, p.4, p.5, p.6, p.7, p.8, p.9, p.10, p.11, p.12, p.13, p.14, p.15].map { UInt8($0) }
    }

    internal static func headerOffset(in ipPacket: Data) -> Int? {
        guard ipPacket.count >= MemoryLayout<IPHeader>.size + MemoryLayout<ICMPHeader>.size else { return nil }

        let ipHeader: IPHeader = ipPacket.withUnsafeBytes({ $0.load(as: IPHeader.self) })
        if ipHeader.versionAndHeaderLength & 0xF0 == 0x40 && ipHeader.protocol == IPPROTO_ICMP {
            let headerLength = Int(ipHeader.versionAndHeaderLength) & 0x0F * MemoryLayout<UInt32>.size
            if ipPacket.count >= headerLength + MemoryLayout<ICMPHeader>.size {
                return headerLength
            }
        }
        return nil
    }
}

/// ICMP echo types
public enum ICMPType: UInt8 {
    case EchoReply = 0
    case EchoRequest = 8
}
