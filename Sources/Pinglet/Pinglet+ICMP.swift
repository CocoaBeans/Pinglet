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

// MARK: - ICMP package

extension Pinglet {

    /// Creates an ICMP package.
    internal func createICMPPackage(identifier: UInt16, sequenceNumber: UInt16) throws -> Data {
        var header = ICMPHeader(type: ICMPType.EchoRequest.rawValue,
                                code: 0,
                                checksum: 0,
                                identifier: CFSwapInt16HostToBig(identifier),
                                sequenceNumber: CFSwapInt16HostToBig(sequenceNumber),
                                payload: fingerprint.uuid)

        let delta = configuration.payloadSize - MemoryLayout<uuid_t>.size
        var additional = [UInt8]()
        if delta > 0 {
            additional = (0..<delta).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        }

        let checksum = try header.computeChecksum(additionalPayload: additional)
        header.checksum = checksum

        let package = Data(bytes: &header, count: MemoryLayout<ICMPHeader>.size) + Data(additional)
        return package
    }

}
