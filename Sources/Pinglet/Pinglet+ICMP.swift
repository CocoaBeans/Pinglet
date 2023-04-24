//
// Created by Kevin Ross on 4/23/23.
//

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
