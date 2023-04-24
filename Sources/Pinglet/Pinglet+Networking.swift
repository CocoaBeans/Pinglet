//
// Created by Kevin Ross on 4/24/23.
//

import Foundation

extension Pinglet {
    // MARK: - Socket callback

    internal func socket(_ socket: CFSocket, didReadData data: Data?) {
        if killSwitch { return }

        guard let data = data else { return }
        var validationError: PingError?
        var sequence: UInt16? = .none

        do {
            let validation = try validateResponse(from: data)
            if !validation { return }
            let icmp: ICMPHeader = try ICMPHeader.from(data: data)
            sequence = icmp.sequenceNumberToHost

        }
        catch let error as PingError {
            validationError = error
        }
        catch {
            print("Unhandled error thrown: \(error)")
        }

        // timeoutTimer?.invalidate()
        var ipHeader: IPHeader?
        if validationError == nil {
            ipHeader = data.withUnsafeBytes { $0.load(as: IPHeader.self) }
        }

        guard let sequenceIndex: UInt16 = sequence,
              let request: PingRequest = pendingRequest(for: Int(sequenceIndex)) else {
            fatalError("Could not look up pending request for sequenceIndex: \(sequence ?? UInt16.min)")
        }

        // Get the request from the sequence index of the echoed ICMP Packet
        informObserver(of: PingResponse(identifier: request.identifier,
                                        ipAddress: request.ipAddress,
                                        sequenceIndex: request.sequenceIndex,
                                        trueSequenceIndex: request.trueSequenceIndex,
                                        duration: request.timeIntervalSinceStart,
                                        error: validationError,
                                        byteCount: data.count,
                                        ipHeader: ipHeader))
    }

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
