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

extension Pinglet {
    internal func validateResponse(from data: Data) throws -> Bool {
        guard data.count >= MemoryLayout<ICMPHeader>.size + MemoryLayout<IPHeader>.size else {
            throw PingError.invalidLength(received: data.count)
        }

        guard let headerOffset = ICMPHeader.headerOffset(in: data) else { throw PingError.invalidHeaderOffset }
        let payloadSize = data.count - headerOffset - MemoryLayout<ICMPHeader>.size

        let icmpHeader: ICMPHeader = try ICMPHeader.from(data: data)
        let payload: Data = data.subdata(in: (data.count - payloadSize) ..< data.count)

        let uuid = UUID(uuid: icmpHeader.payload)
        guard uuid == fingerprint else {
            // Wrong handler, ignore this response
            return false
        }

        let checksum = try icmpHeader.computeChecksum(additionalPayload: [UInt8](payload))

        guard icmpHeader.checksum == checksum else {
            throw PingError.checksumMismatch(received: icmpHeader.checksum, calculated: checksum)
        }
        guard icmpHeader.type == ICMPType.EchoReply.rawValue else {
            throw PingError.invalidType(received: icmpHeader.type)
        }
        guard icmpHeader.code == 0 else {
            throw PingError.invalidCode(received: icmpHeader.code)
        }
        guard CFSwapInt16BigToHost(icmpHeader.identifier) == identifier else {
            throw PingError.identifierMismatch(received: icmpHeader.identifier, expected: identifier)
        }
        let sequenceNumberUInt16 = CFSwapInt16BigToHost(icmpHeader.sequenceNumber)
        let receivedSequenceIndex = Int(sequenceNumberUInt16)
        guard pendingRequest(for: receivedSequenceIndex) != nil else {
            if erroredIndices.contains(receivedSequenceIndex) {
                // This response either errorred or timed out, ignore it
                return false
            }

            // TODO: This error doesn't make sense anymore because we are checking against an array of pending sequences
            // throw PingError.invalidSequenceIndex(received: sequenceNumberUInt16, expected: sequenceIndex)
            return false
        }
        return true
    }
}
