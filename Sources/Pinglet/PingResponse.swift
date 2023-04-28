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

protocol PingID: Identifiable {
    var id: UInt64 { get }
    /// The randomly generated identifier used in the ping header.
    var identifier: UInt16 { get }
    /// The IP address of the host.
    var ipAddress: String? { get }
    /// Running sequence number, starting from 0.
    /// This number will wrap to zero when it exceeds `UInt16.max`,
    /// which is usually just 65535, and is the one used in the ping
    /// protocol. See `trueSequenceNumber` for the actual count.
    var sequenceIndex: UInt16 { get }
    /// The true sequence number.
    var trueSequenceIndex: UInt64 { get }
}

/// A struct encapsulating a ping request.
public struct PingRequest: PingID {
    public var id: UInt64 { trueSequenceIndex }
    public var identifier: UInt16
    public var ipAddress: String?
    public var sequenceIndex: UInt16
    public var trueSequenceIndex: UInt64

    var timestamp = Date()
    var timeIntervalSinceStart: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
}

/// A struct encapsulating a ping response.
public struct PingResponse: PingID {
    public var id: UInt64 { trueSequenceIndex }
    public let identifier: UInt16
    public let ipAddress: String?
    public let sequenceIndex: UInt16
    public let trueSequenceIndex: UInt64

    /// Roundtrip time.
    public let duration: TimeInterval
    /// An error associated with the response.
    public let error: PingError?
    /// Response data packet size in bytes.
    public let byteCount: Int?
    /// Response IP header.
    public let ipHeader: IPHeader?

    public static func empty() -> PingResponse {
        PingResponse(identifier: 0,
                     ipAddress: .none,
                     sequenceIndex: 0,
                     trueSequenceIndex: 0,
                     duration: 0,
                     error: .none,
                     byteCount: .none,
                     ipHeader: .none)
    }

    public init(identifier: UInt16,
                ipAddress: String?,
                sequenceIndex: UInt16,
                trueSequenceIndex: UInt64,
                duration: TimeInterval,
                error: PingError?,
                byteCount: Int?,
                ipHeader: IPHeader?) {
        self.identifier = identifier
        self.ipAddress = ipAddress
        self.sequenceIndex = sequenceIndex
        self.trueSequenceIndex = trueSequenceIndex
        self.duration = duration
        self.error = error
        self.byteCount = byteCount
        self.ipHeader = ipHeader
    }

    public init(request: PingRequest, error: PingError?, byteCount: Int?, ipHeader: IPHeader?) {
        duration = request.timeIntervalSinceStart
        self.error = error
        self.byteCount = byteCount
        self.ipHeader = ipHeader
        identifier = request.identifier
        ipAddress = request.ipAddress
        sequenceIndex = request.sequenceIndex
        trueSequenceIndex = request.trueSequenceIndex
    }

}
