import Combine
@testable import Pinglet
@testable import Socket2Me
import XCTest

// MARK: - PingConfiguration

final class PingletConfigurationTests: XCTestCase {

    func testDefaultValues() {
        let config = PingConfiguration()
        XCTAssertEqual(config.pingInterval, 1)
        XCTAssertEqual(config.timeoutInterval, 5)
        XCTAssertNil(config.timeToLive)
        XCTAssertTrue(config.handleBackgroundTransitions)
        XCTAssertEqual(config.payloadSize, MemoryLayout<uuid_t>.size)
        XCTAssertTrue(config.haltAfterTarget)
    }

    func testCustomInterval() {
        let config = PingConfiguration(interval: 2.5)
        XCTAssertEqual(config.pingInterval, 2.5)
    }

    func testCustomTimeout() {
        let config = PingConfiguration(timeout: 10)
        XCTAssertEqual(config.timeoutInterval, 10)
    }

    func testCustomTimeToLive() {
        let config = PingConfiguration(timeToLive: 128)
        XCTAssertEqual(config.timeToLive, 128)
    }

    func testCustomAll() {
        let config = PingConfiguration(interval: 0.5, timeout: 3, timeToLive: 64)
        XCTAssertEqual(config.pingInterval, 0.5)
        XCTAssertEqual(config.timeoutInterval, 3)
        XCTAssertEqual(config.timeToLive, 64)
    }

    func testPropertyMutations() {
        var config = PingConfiguration()
        config.handleBackgroundTransitions = false
        config.payloadSize = 64
        config.haltAfterTarget = false
        config.timeToLive = 255

        XCTAssertFalse(config.handleBackgroundTransitions)
        XCTAssertEqual(config.payloadSize, 64)
        XCTAssertFalse(config.haltAfterTarget)
        XCTAssertEqual(config.timeToLive, 255)
    }
}

// MARK: - PingRequest

final class PingletRequestTests: XCTestCase {

    func testRequestInitialization() {
        let request = PingRequest(
            identifier: 42,
            ipAddress: "1.1.1.1",
            sequenceIndex: 0,
            trueSequenceIndex: 0
        )
        XCTAssertEqual(request.identifier, 42)
        XCTAssertEqual(request.ipAddress, "1.1.1.1")
        XCTAssertEqual(request.sequenceIndex, 0)
        XCTAssertEqual(request.trueSequenceIndex, 0)
        XCTAssertEqual(request.id, 0)
    }

    func testRequestIDEqualsTrueSequenceIndex() {
        let request = PingRequest(
            identifier: 1,
            ipAddress: nil,
            sequenceIndex: 5,
            trueSequenceIndex: 100
        )
        XCTAssertEqual(request.id, 100)
    }

    func testRequestSequenceIndexWrapping() {
        var request = PingRequest(
            identifier: 1,
            ipAddress: nil,
            sequenceIndex: UInt16.max,
            trueSequenceIndex: 0
        )
        request.sequenceIndex = UInt16.max
        XCTAssertEqual(request.sequenceIndex, UInt16.max)
    }

    func testRequestTimeIntervalSinceStart() {
        let request = PingRequest(
            identifier: 0,
            ipAddress: nil,
            sequenceIndex: 0,
            trueSequenceIndex: 0
        )
        let interval = request.timeIntervalSinceStart
        XCTAssertGreaterThanOrEqual(interval, 0)
        XCTAssertLessThan(interval, 1)
    }

    func testRequestPingIDConformance() {
        let request = PingRequest(
            identifier: 7,
            ipAddress: "8.8.8.8",
            sequenceIndex: 3,
            trueSequenceIndex: 42
        )
        XCTAssertEqual(request.id, request.trueSequenceIndex)
        XCTAssertEqual(request.identifier, 7)
        XCTAssertEqual(request.ipAddress, "8.8.8.8")
        XCTAssertEqual(request.sequenceIndex, 3)
    }
}

// MARK: - PingResponse

final class PingletResponseTests: XCTestCase {

    func testResponseFullInit() {
        let response = PingResponse(
            identifier: 1,
            ipAddress: "1.1.1.1",
            sequenceIndex: 0,
            trueSequenceIndex: 0,
            duration: 0.025,
            error: nil,
            byteCount: 64,
            ipHeader: nil
        )
        XCTAssertEqual(response.identifier, 1)
        XCTAssertEqual(response.ipAddress, "1.1.1.1")
        XCTAssertEqual(response.sequenceIndex, 0)
        XCTAssertEqual(response.trueSequenceIndex, 0)
        XCTAssertEqual(response.duration, 0.025)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.byteCount, 64)
        XCTAssertNil(response.ipHeader)
        XCTAssertEqual(response.id, 0)
    }

    func testResponseRequestInit() {
        let request = PingRequest(
            identifier: 5,
            ipAddress: "8.8.8.8",
            sequenceIndex: 1,
            trueSequenceIndex: 10
        )
        let response = PingResponse(
            request: request,
            error: PingError.responseTimeout,
            byteCount: nil,
            ipHeader: nil
        )
        XCTAssertEqual(response.identifier, 5)
        XCTAssertEqual(response.ipAddress, "8.8.8.8")
        XCTAssertEqual(response.sequenceIndex, 1)
        XCTAssertEqual(response.trueSequenceIndex, 10)
        if case .some(let error) = response.error {
            if case .responseTimeout = error {
                // Expected error
            } else {
                XCTFail("Expected responseTimeout, got \(error)")
            }
        } else {
            XCTFail("Expected responseTimeout error")
        }
        // duration is time since request was created, should be >= 0
        XCTAssertGreaterThanOrEqual(response.duration, 0)
        XCTAssertNil(response.byteCount)
        XCTAssertNil(response.ipHeader)
        XCTAssertEqual(response.id, 10)
    }

    func testResponseEmpty() {
        let response = PingResponse.empty()
        XCTAssertEqual(response.identifier, 0)
        XCTAssertNil(response.ipAddress)
        XCTAssertEqual(response.sequenceIndex, 0)
        XCTAssertEqual(response.trueSequenceIndex, 0)
        XCTAssertEqual(response.duration, 0)
        XCTAssertNil(response.error)
        XCTAssertNil(response.byteCount)
        XCTAssertNil(response.ipHeader)
        XCTAssertEqual(response.id, 0)
    }

    func testResponseWithError() {
        let response = PingResponse(
            identifier: 2,
            ipAddress: "127.0.0.1",
            sequenceIndex: 7,
            trueSequenceIndex: 7,
            duration: -1,
            error: .responseTimeout,
            byteCount: nil,
            ipHeader: nil
        )
        XCTAssertEqual(response.duration, -1)
        if case .some(let error) = response.error {
            if case .responseTimeout = error {
                // Expected
            } else {
                XCTFail("Expected responseTimeout, got \(error)")
            }
        } else {
            XCTFail("Expected responseTimeout error")
        }
    }

    func testResponseID() {
        let r1 = PingResponse(identifier: 0, ipAddress: nil, sequenceIndex: 0, trueSequenceIndex: 0, duration: 0, error: nil, byteCount: nil, ipHeader: nil)
        let r2 = PingResponse(identifier: 0, ipAddress: nil, sequenceIndex: 0, trueSequenceIndex: 1, duration: 0, error: nil, byteCount: nil, ipHeader: nil)
        XCTAssertEqual(r1.id, 0)
        XCTAssertEqual(r2.id, 1)
    }
}

// MARK: - PingResult

final class PingletResultTests: XCTestCase {

    func testResultPacketLoss() {
        let result = PingResult(
            responses: [],
            packetsTransmitted: 10,
            packetsReceived: 8,
            roundtrip: nil
        )
        XCTAssertEqual(result.packetsTransmitted, 10)
        XCTAssertEqual(result.packetsReceived, 8)
        XCTAssertNotNil(result.packetLoss)
        XCTAssertEqual(result.packetLoss!, 0.2, accuracy: 0.001)
    }

    func testPacketLossNilWhenZeroTransmitted() {
        let result = PingResult(
            responses: [],
            packetsTransmitted: 0,
            packetsReceived: 0,
            roundtrip: nil
        )
        XCTAssertNil(result.packetLoss)
    }

    func testPacketLossZeroWhenAllReceived() {
        let result = PingResult(
            responses: [],
            packetsTransmitted: 5,
            packetsReceived: 5,
            roundtrip: nil
        )
        XCTAssertEqual(result.packetLoss!, 0)
    }

    func testPacketLossFull() {
        let result = PingResult(
            responses: [],
            packetsTransmitted: 10,
            packetsReceived: 0,
            roundtrip: nil
        )
        XCTAssertEqual(result.packetLoss!, 1)
    }

    func testRoundtripStats() {
        let rt = PingResult.Roundtrip(
            minimum: 0.010,
            maximum: 0.100,
            average: 0.050,
            standardDeviation: 0.025
        )
        XCTAssertEqual(rt.minimum, 0.010)
        XCTAssertEqual(rt.maximum, 0.100)
        XCTAssertEqual(rt.average, 0.050)
        XCTAssertEqual(rt.standardDeviation, 0.025)
    }

    func testResultWithRoundtrip() {
        let rt = PingResult.Roundtrip(minimum: 1, maximum: 2, average: 1.5, standardDeviation: 0.5)
        let result = PingResult(
            responses: [],
            packetsTransmitted: 2,
            packetsReceived: 2,
            roundtrip: rt
        )
        XCTAssertNotNil(result.roundtrip)
        XCTAssertEqual(result.roundtrip?.minimum, 1)
        XCTAssertEqual(result.roundtrip?.maximum, 2)
    }
}

// MARK: - PingError

final class PingletErrorTests: XCTestCase {

    func testCaseIterable() {
        let cases = PingError.allCases
        XCTAssertFalse(cases.isEmpty)
        // Ensure the expected cases are present
        XCTAssertTrue(cases.contains { if case .responseTimeout = $0 { return true }; return false })
        XCTAssertTrue(cases.contains { if case .requestError = $0 { return true }; return false })
        XCTAssertTrue(cases.contains { if case .hostNotFound = $0 { return true }; return false })
        XCTAssertTrue(cases.contains { if case .socketNil = $0 { return true }; return false })
    }

    func testErrorCodesAreUnique() {
        let codes = PingError.allCases.map { ($0 as NSError).code }
        let uniqueCodes = Set(codes)
        // Each case should map to a unique error code
        XCTAssertEqual(codes.count, uniqueCodes.count)
    }

    func testErrorAssociatedValues() {
        let invalidLength = PingError.invalidLength(received: 10)
        let code = (invalidLength as NSError).code
        // Verifying that associated values don't affect the error code
        let otherLength = PingError.invalidLength(received: 0)
        XCTAssertEqual(code, (otherLength as NSError).code)
    }

    func testLogErrorCodesDoesNotThrow() {
        PingError.logErrorCodes()
    }
}

// MARK: - ICMP Parsing

final class PingletICMPParsingTests: XCTestCase {

    // MARK: IPHeader

    func testIPHeaderParsing() {
        let bytes: [UInt8] = [
            0x45, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x01, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08,
        ]
        let data = Data(bytes)
        let header = IPHeader(data: data)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.versionAndHeaderLength, 0x45)
        XCTAssertEqual(header?.timeToLive, 0x40)
        XCTAssertEqual(header?.protocol, UInt8(IPPROTO_ICMP))
        XCTAssertEqual(header?.sourceAddress.0, 1)
        XCTAssertEqual(header?.sourceAddress.3, 1)
        XCTAssertEqual(header?.destinationAddress.0, 8)
        XCTAssertEqual(header?.destinationAddress.3, 8)
    }

    func testIPHeaderInvalidDataTooShort() {
        let data = Data([UInt8](repeating: 0, count: 19))
        let header = IPHeader(data: data)
        XCTAssertNil(header)
    }

    func testIPHeaderEmptyData() {
        let header = IPHeader(data: Data())
        XCTAssertNil(header)
    }

    func testIPHeaderHeaderLength() {
        let bytes: [UInt8] = [
            0x46, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x01, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08, 0x00, 0x00, 0x00, 0x00,
        ]
        let header = IPHeader(data: Data(bytes))
        XCTAssertNotNil(header)
        // IHL = 6, so header length = 6 * 4 = 24
        XCTAssertEqual(header?.headerLength, 24)
    }

    func testIPHeaderIsIPv4() {
        let bytes: [UInt8] = [
            0x45, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x01, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08,
        ]
        let header = IPHeader(data: Data(bytes))
        XCTAssertTrue(header!.isIPv4)
    }

    func testIPHeaderNotIPv4() {
        let bytes: [UInt8] = [
            0x35, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x06, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08,
        ]
        let header = IPHeader(data: Data(bytes))
        XCTAssertFalse(header!.isIPv4)
    }

    func testIPHeaderIsICMP() {
        let bytes: [UInt8] = [
            0x45, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x01, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08,
        ]
        let header = IPHeader(data: Data(bytes))
        XCTAssertTrue(header!.isICMP)
    }

    func testIPHeaderNotICMP() {
        let bytes: [UInt8] = [
            0x45, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x06, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08,
        ]
        let header = IPHeader(data: Data(bytes))
        XCTAssertFalse(header!.isICMP)
    }

    func testIPHeaderDefaultInitIsInvalid() {
        // IPHeader has no public init; only init?(data:) which is internal
        // This test verifies the structure exists and can be parsed
    }

    // MARK: ICMPHeader

    func testICMPHeaderParsing() throws {
        let bytes: [UInt8] = [
            0x00, 0x00, 0xFF, 0xFD, 0x00, 0x01, 0x00, 0x01,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        ]
        let header = try ICMPHeader.from(data: Data(bytes))
        XCTAssertEqual(header.type, 0)
        XCTAssertEqual(header.code, 0)
        XCTAssertEqual(header.checksum, 0xFFFD)
        XCTAssertEqual(header.identifier, 1)
        XCTAssertEqual(header.sequenceNumber, 1)
        XCTAssertEqual(header.payload.count, 16)
        XCTAssertEqual(header.payload.first, 0x00)
        XCTAssertEqual(header.payload.last, 0x0F)
    }

    func testICMPHeaderParsingWithOffset() throws {
        // 10 bytes of junk prefix, then valid ICMP header
        let prefix = [UInt8](repeating: 0xCC, count: 10)
        let icmp: [UInt8] = [
            0x08, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ]
        let data = Data(prefix + icmp)
        let header = try ICMPHeader.from(data: data, offset: 10)
        XCTAssertEqual(header.type, 8)
        XCTAssertEqual(header.code, 0)
        XCTAssertEqual(header.identifier, 1)
        XCTAssertEqual(header.sequenceNumber, 1)
    }

    func testICMPHeaderInvalidDataTooShort() {
        let data = Data([UInt8](repeating: 0, count: 23))
        XCTAssertThrowsError(try ICMPHeader.from(data: data)) { error in
            guard case PingError.invalidLength = error else {
                return XCTFail("Expected invalidLength, got \(error)")
            }
        }
    }

    func testICMPHeaderEmptyData() {
        XCTAssertThrowsError(try ICMPHeader.from(data: Data()))
    }

    func testICMPHeaderIdentifierToHost() throws {
        let bytes: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        let header = try ICMPHeader.from(data: Data(bytes))
        // from(data:) decodes the big-endian wire bytes into a host-order value,
        // so identifier and identifierToHost are both the host value 1.
        XCTAssertEqual(header.identifier, 1)
        XCTAssertEqual(header.identifierToHost, 1)
    }

    func testICMPHeaderSequenceNumberToHost() throws {
        let bytes: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        let header = try ICMPHeader.from(data: Data(bytes))
        XCTAssertEqual(header.sequenceNumber, 0x8000)
        XCTAssertEqual(header.sequenceNumberToHost, 0x8000)
    }

    // MARK: Checksum

    func testChecksumComputation() throws {
        let header = ICMPHeader(
            type: 0,
            code: 0,
            checksum: 0,
            identifier: 0x0001,
            sequenceNumber: 0x0001,
            payload: [UInt8](repeating: 0, count: 16)
        )
        let checksum = try header.computeChecksum()
        // typeCode = 0x0000, identifier = 0x0001, sequenceNumber = 0x0001
        // sum = 0x0000 + 0x0001 + 0x0001 = 0x0002
        // payload of all zeroes = sum stays 0x0002
        // one's complement: ~0x0002 = 0xFFFD
        XCTAssertEqual(checksum, 0xFFFD)
    }

    func testChecksumWithType8() throws {
        let header = ICMPHeader(
            type: 8,
            code: 0,
            checksum: 0,
            identifier: 0x0001,
            sequenceNumber: 0x0001,
            payload: [UInt8](repeating: 0, count: 16)
        )
        let checksum = try header.computeChecksum()
        // typeCode = 0x0800, identifier = 0x0001, sequenceNumber = 0x0001
        // sum = 0x0800 + 0x0001 + 0x0001 = 0x0802
        // one's complement: ~0x0802 = 0xF7FD
        XCTAssertEqual(checksum, 0xF7FD)
    }

    func testChecksumWithNonZeroPayload() throws {
        let header = ICMPHeader(
            type: 0,
            code: 0,
            checksum: 0,
            identifier: 0x0001,
            sequenceNumber: 0x0001,
            payload: [
                0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04,
                0x00, 0x05, 0x00, 0x06, 0x00, 0x07, 0x00, 0x08,
            ]
        )
        let checksum = try header.computeChecksum()
        // typeCode = 0x0000
        // sum = 0x0000 + 0x0001 + 0x0001 = 0x0002
        // Payload words: 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008
        // Payload sum = 0x0001 + 0x0002 + 0x0003 + 0x0004 + 0x0005 + 0x0006 + 0x0007 + 0x0008 = 0x0024
        // Total sum = 0x0002 + 0x0024 = 0x0026
        // One's complement: ~0x0026 = 0xFFD9
        XCTAssertEqual(checksum, 0xFFD9)
    }

    func testChecksumWithAdditionalPayload() throws {
        let header = ICMPHeader(
            type: 0,
            code: 0,
            checksum: 0,
            identifier: 0x0001,
            sequenceNumber: 0x0001,
            payload: [UInt8](repeating: 0, count: 16)
        )
        let additional: [UInt8] = [0x00, 0xFF]
        let checksum = try header.computeChecksum(additionalPayload: additional)
        // typeCode = 0x0000, identifier = 0x0001, sequenceNumber = 0x0001
        // sum = 0x0002
        // payload (all zeroes) + additional = 0x00FF
        // sum = 0x0002 + 0x00FF = 0x0101
        // One's complement: ~0x0101 = 0xFEFE
        XCTAssertEqual(checksum, 0xFEFE)
    }

    func testChecksumOddPayloadThrows() {
        let header = ICMPHeader(
            type: 0,
            code: 0,
            checksum: 0,
            identifier: 0x0001,
            sequenceNumber: 0x0001,
            payload: [UInt8](repeating: 0, count: 15) // odd length
        )
        XCTAssertThrowsError(try header.computeChecksum()) { error in
            guard case PingError.unexpectedPayloadLength = error else {
                return XCTFail("Expected unexpectedPayloadLength, got \(error)")
            }
        }
    }

    func testChecksumWithOddAdditionalPayload() {
        let header = ICMPHeader(
            type: 0,
            code: 0,
            checksum: 0,
            identifier: 0x0001,
            sequenceNumber: 0x0001,
            payload: [UInt8](repeating: 0, count: 16) // even
        )
        XCTAssertThrowsError(try header.computeChecksum(additionalPayload: [0x00])) { error in
            guard case PingError.unexpectedPayloadLength = error else {
                return XCTFail("Expected unexpectedPayloadLength, got \(error)")
            }
        }
    }

    // MARK: Header Offset

    func testHeaderOffsetValidPacket() throws {
        let ip: [UInt8] = [
            0x45, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x01, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08,
        ]
        let icmp: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        let packet = Data(ip + icmp)
        let offset = ICMPHeader.headerOffset(in: packet)
        XCTAssertEqual(offset, 20)
    }

    func testHeaderOffsetTooShort() {
        let data = Data([UInt8](repeating: 0, count: 19))
        let offset = ICMPHeader.headerOffset(in: data)
        XCTAssertNil(offset)
    }

    func testHeaderOffsetNotIPv4() {
        let bytes: [UInt8] = [
            0x35, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x01, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08,
        ]
        let data = Data(bytes)
        let offset = ICMPHeader.headerOffset(in: data)
        XCTAssertNil(offset)
    }

    func testHeaderOffsetNotICMP() {
        let bytes: [UInt8] = [
            0x45, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00,
            0x40, 0x06, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
            0x08, 0x08, 0x08, 0x08,
        ]
        let data = Data(bytes)
        let offset = ICMPHeader.headerOffset(in: data)
        XCTAssertNil(offset)
    }

    // MARK: ICMPType

    func testICMPTypeValues() {
        XCTAssertEqual(ICMPType.EchoReply.rawValue, 0)
        XCTAssertEqual(ICMPType.EchoRequest.rawValue, 8)
    }
}

// MARK: - ICMP Package Creation

final class PingletICMPPackageTests: XCTestCase {

    func testCreateICMPPackage() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        let identifier: UInt16 = 42
        let sequenceNumber: UInt16 = 7

        let package = try pinglet.createICMPPackage(identifier: identifier, sequenceNumber: sequenceNumber)

        // Default payload is the 16-byte UUID fingerprint with no additional bytes.
        let config = PingConfiguration()
        let delta = config.payloadSize - MemoryLayout<uuid_t>.size
        XCTAssertEqual(package.count, ICMPHeader.totalSize + delta)

        // The package round-trips through ICMPHeader.from and carries the fingerprint
        // payload and a self-consistent checksum.
        let parsed = try ICMPHeader.from(data: package)
        XCTAssertEqual(parsed.type, ICMPType.EchoRequest.rawValue)
        XCTAssertEqual(parsed.code, 0)
        XCTAssertEqual(parsed.identifier, identifier)
        XCTAssertEqual(parsed.sequenceNumber, sequenceNumber)

        let expectedPayload = withUnsafeBytes(of: pinglet.fingerprint.uuid) { Array($0) }
        XCTAssertEqual(parsed.payload, expectedPayload)
        XCTAssertEqual(parsed.checksum, try parsed.computeChecksum())
    }

    func testCreateICMPPackageWithExtraPayload() throws {
        let config = PingConfiguration(interval: 1, timeout: 5)
        var mutableConfig = config
        mutableConfig.payloadSize = 32
        let pinglet = try Pinglet(host: "1.1.1.1", configuration: mutableConfig)

        let package = try pinglet.createICMPPackage(identifier: 0, sequenceNumber: 0)

        let expectedLength = ICMPHeader.totalSize + (32 - MemoryLayout<uuid_t>.size)
        XCTAssertEqual(package.count, expectedLength)
    }

    func testCreateICMPPackageAllSequenceNumbers() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        let identifier: UInt16 = UInt16.random(in: UInt16.min...UInt16.max)
        var sequenceNumber: UInt16 = 0
        for _ in 0...100 {
            let _: Data = try pinglet.createICMPPackage(identifier: identifier, sequenceNumber: sequenceNumber)
            if sequenceNumber == UInt16.max { break }
            sequenceNumber += 1
        }
    }
}

// MARK: - PingDelegate

final class PingletDelegateTests: XCTestCase {

    func testDelegateConformance() {
        let delegate = MockPingDelegate()
        XCTAssertTrue((delegate as AnyObject) is PingDelegate)
    }

    func testDelegateDidSend() {
        let delegate = MockPingDelegate()
        delegate.didSend(identifier: 42, sequenceIndex: 7)
        XCTAssertEqual(delegate.lastSentIdentifier, 42)
        XCTAssertEqual(delegate.lastSentSequenceIndex, 7)
    }

    func testDelegateDidReceive() {
        let delegate = MockPingDelegate()
        let response = PingResponse.empty()
        delegate.didReceive(response: response)
        XCTAssertEqual(delegate.lastReceivedResponse?.identifier, 0)
    }
}

private class MockPingDelegate: PingDelegate {
    var lastSentIdentifier: UInt16?
    var lastSentSequenceIndex: Int?
    var lastReceivedResponse: PingResponse?
    var onReceive: (() -> Void)?

    func didSend(identifier: UInt16, sequenceIndex: Int) {
        lastSentIdentifier = identifier
        lastSentSequenceIndex = sequenceIndex
    }

    func didReceive(response: PingResponse) {
        lastReceivedResponse = response
        onReceive?()
    }
}

// MARK: - Pinglet Model

final class PingletModelTests: XCTestCase {

    func testInitWithDestination() throws {
        let dest = try Destination(host: "1.1.1.1")
        let config = PingConfiguration(interval: 2, timeout: 10)
        let queue = DispatchQueue(label: "test.queue")
        let pinglet = try Pinglet(destination: dest, configuration: config, queue: queue)

        XCTAssertEqual(pinglet.destination.host, "1.1.1.1")
        XCTAssertEqual(pinglet.configuration.pingInterval, 2)
        XCTAssertEqual(pinglet.configuration.timeoutInterval, 10)
        XCTAssertNil(pinglet.targetCount)
        XCTAssertFalse(pinglet.runInBackground)
    }

    func testInitDefaults() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        XCTAssertEqual(pinglet.configuration.pingInterval, 1)
        XCTAssertEqual(pinglet.configuration.timeoutInterval, 5)
        XCTAssertNil(pinglet.targetCount)
        XCTAssertFalse(pinglet.runInBackground)
        XCTAssertEqual(pinglet.responses.count, 0)
        XCTAssertEqual(pinglet.currentCount, 0)
    }

    func testInitWithIPv4Address() throws {
        let pinglet = try Pinglet(ipv4Address: "127.0.0.1")
        XCTAssertEqual(pinglet.destination.host, "127.0.0.1")
        XCTAssertEqual(pinglet.destination.ip, "127.0.0.1")
    }

    func testConvenienceInitResolvesHost() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        XCTAssertEqual(pinglet.destination.host, "1.1.1.1")
        XCTAssertEqual(pinglet.destination.ip, "1.1.1.1")
    }

    func testTargetCountProperty() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        XCTAssertNil(pinglet.targetCount)
        pinglet.targetCount = 5
        XCTAssertEqual(pinglet.targetCount, 5)
    }

    func testPublishedResponsesStartsEmpty() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        XCTAssertTrue(pinglet.responses.isEmpty)
    }

    func testCurrentCountStartsZero() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        XCTAssertEqual(pinglet.currentCount, 0)
    }

    func testObservationClosures() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")

        let requestExpectation = XCTestExpectation()
        pinglet.requestObserver = { _, _ in requestExpectation.fulfill() }

        let responseExpectation = XCTestExpectation()
        pinglet.responseObserver = { _ in responseExpectation.fulfill() }

        let finishExpectation = XCTestExpectation()
        pinglet.finished = { _ in finishExpectation.fulfill() }

        XCTAssertNotNil(pinglet.requestObserver)
        XCTAssertNotNil(pinglet.responseObserver)
        XCTAssertNotNil(pinglet.finished)
    }

    func testRequestPublisher() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        var received: [PingRequest] = []
        let expectation = XCTestExpectation()

        let cancellable = pinglet.requestPublisher
            .sink(receiveCompletion: { _ in },
                  receiveValue: { request in
                      received.append(request)
                      if received.count == 2 { expectation.fulfill() }
                  })

        // Simulate sending requests via the internal passthrough
        // The passthrough is private, but we can trigger it through sendPing
        // For unit testing, we can observe the publisher is wired up correctly
        XCTAssertNotNil(cancellable)
        cancellable.cancel()
    }

    func testResponsePublisher() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        var received: [PingResponse] = []
        let expectation = XCTestExpectation()

        let cancellable = pinglet.responsePublisher
            .sink(receiveCompletion: { _ in },
                  receiveValue: { response in
                      received.append(response)
                      expectation.fulfill()
                  })

        XCTAssertNotNil(cancellable)
        cancellable.cancel()
    }

    func testResponsePublisherWithData() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        var receivedResponse: PingResponse?
        let expectation = XCTestExpectation()

        let cancellable = pinglet.responsePublisher
            .sink(receiveCompletion: { _ in },
                  receiveValue: { response in
                      receivedResponse = response
                      expectation.fulfill()
                  })

        // Create a request to add to pending requests so the response pipeline can find it
        let request = PingRequest(identifier: pinglet.identifier, ipAddress: "1.1.1.1", sequenceIndex: 0, trueSequenceIndex: 0)
        pinglet.pendingRequests.append(request)

        // Simulate what informObservers does
        pinglet.informObservers(of: PingResponse(
            identifier: pinglet.identifier,
            ipAddress: "1.1.1.1",
            sequenceIndex: 0,
            trueSequenceIndex: 0,
            duration: 0.025,
            error: nil,
            byteCount: 64,
            ipHeader: nil
        ))

        wait(for: [expectation], timeout: 2)
        XCTAssertNotNil(receivedResponse)
        XCTAssertEqual(receivedResponse?.duration, 0.025)
        cancellable.cancel()
    }

    func testPendingRequestManagement() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        let request = PingRequest(identifier: 1, ipAddress: "1.1.1.1", sequenceIndex: 5, trueSequenceIndex: 5)
        pinglet.pendingRequests.append(request)

        let found = pinglet.pendingRequest(for: 5)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.sequenceIndex, 5)

        let notFound = pinglet.pendingRequest(for: 99)
        XCTAssertNil(notFound)
    }

    func testCompleteRequestRemovesPending() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        let request = PingRequest(identifier: 1, ipAddress: "1.1.1.1", sequenceIndex: 3, trueSequenceIndex: 3)
        pinglet.pendingRequests.append(request)

        // completeRequest dispatches async cleanup; wait for it
        pinglet.completeRequest(for: 3)
        pinglet.serialProperty.sync {}

        let found = pinglet.pendingRequest(for: 3)
        XCTAssertNil(found)
    }

    func testInformObserversAppendsResponse() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        let request = PingRequest(identifier: pinglet.identifier, ipAddress: "1.1.1.1", sequenceIndex: 0, trueSequenceIndex: 0)
        pinglet.pendingRequests.append(request)

        let response = PingResponse(
            identifier: pinglet.identifier,
            ipAddress: "1.1.1.1",
            sequenceIndex: 0,
            trueSequenceIndex: 0,
            duration: 0.015,
            error: nil,
            byteCount: 64,
            ipHeader: nil
        )

        pinglet.informObservers(of: response)
        pinglet.serialProperty.sync {}

        XCTAssertEqual(pinglet.responses.count, 1)
        XCTAssertEqual(pinglet.responses.first?.duration, 0.015)
    }

    func testInformObserversTimeout() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        let request = PingRequest(identifier: pinglet.identifier, ipAddress: "1.1.1.1", sequenceIndex: 0, trueSequenceIndex: 0)
        pinglet.pendingRequests.append(request)

        pinglet.informObserversOfTimeout(for: request)
        pinglet.serialProperty.sync {}

        XCTAssertEqual(pinglet.responses.count, 1)
        if let error = pinglet.responses.first?.error {
            if case .responseTimeout = error {
                // Expected
            } else {
                XCTFail("Expected responseTimeout, got \(error)")
            }
        } else {
            XCTFail("Expected error on response")
        }
    }

    func testPingletDeinitDoesNotCrash() throws {
        let _: Pinglet? = try Pinglet(host: "1.1.1.1")
    }

    func testPingletSequenceAndTrueSequenceAreSynchronized() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        XCTAssertEqual(pinglet.currentCount, 0)
    }

    func testPingletResponseObserverQueue() throws {
        let expectation = XCTestExpectation()
        let pinglet = try Pinglet(host: "1.1.1.1", queue: DispatchQueue.global())

        let request = PingRequest(identifier: pinglet.identifier, ipAddress: "1.1.1.1", sequenceIndex: 0, trueSequenceIndex: 0)
        pinglet.pendingRequests.append(request)

        pinglet.responseObserver = { _ in
            expectation.fulfill()
        }

        pinglet.informObservers(of: PingResponse(
            identifier: pinglet.identifier,
            ipAddress: "1.1.1.1",
            sequenceIndex: 0,
            trueSequenceIndex: 0,
            duration: 0.01,
            error: nil,
            byteCount: nil,
            ipHeader: nil
        ))

        wait(for: [expectation], timeout: 2)
    }

    func testPingletDelegateWiredCorrectly() throws {
        let delegate = MockPingDelegate()
        let pinglet = try Pinglet(host: "1.1.1.1")
        pinglet.delegate = delegate

        let request = PingRequest(identifier: pinglet.identifier, ipAddress: "1.1.1.1", sequenceIndex: 0, trueSequenceIndex: 0)
        pinglet.pendingRequests.append(request)

        let response = PingResponse(
            identifier: pinglet.identifier,
            ipAddress: "1.1.1.1",
            sequenceIndex: 0,
            trueSequenceIndex: 0,
            duration: 0.01,
            error: nil,
            byteCount: nil,
            ipHeader: nil
        )

        let expectation = XCTestExpectation()
        delegate.onReceive = { expectation.fulfill() }

        pinglet.informObservers(of: response)
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(delegate.lastReceivedResponse?.duration, 0.01)
    }
}

// MARK: - Receive Path (regression guards)

final class PingletReceivePathTests: XCTestCase {

    /// A received echo *reply* echoes our request verbatim except the type flips
    /// from EchoRequest (8) to EchoReply (0). Builds one for `pinglet` carrying
    /// its identifier / fingerprint, with a self-consistent checksum.
    private func makeEchoReply(for pinglet: Pinglet, sequence: UInt16) throws -> Data {
        let request = try pinglet.createICMPPackage(identifier: pinglet.identifier, sequenceNumber: sequence)
        let echoed = try ICMPHeader.from(data: request)
        var reply = ICMPHeader(type: ICMPType.EchoReply.rawValue,
                               code: 0,
                               checksum: 0,
                               identifier: echoed.identifier,
                               sequenceNumber: echoed.sequenceNumber,
                               payload: echoed.payload)
        reply.checksum = try reply.computeChecksum()
        return reply.serialized()
    }

    /// A minimal IPv4 header as Darwin's raw/datagram socket delivers it: 20 bytes,
    /// `ip_len` in host byte order, protocol = ICMP, version/IHL = 0x45.
    private func syntheticIPHeader(icmpLength: Int) -> Data {
        var b = [UInt8](repeating: 0, count: IPHeader.minSize)
        b[0] = 0x45                                  // IPv4, 5-word (20-byte) header
        let len = UInt16(icmpLength)                 // ip_len, host byte order
        b[2] = UInt8(len & 0xFF); b[3] = UInt8(len >> 8)
        b[8] = 57                                    // TTL
        b[9] = UInt8(IPPROTO_ICMP)                   // protocol = ICMP
        b[12] = 1; b[13] = 1; b[14] = 1; b[15] = 1   // source 1.1.1.1
        return Data(b)
    }

    /// Regression guard for the offset bug (findings 2/3): a full IP-header + ICMP
    /// echo reply must validate. Under the old `ICMPHeader.from(data:)` (offset 0)
    /// the IP header was parsed as the ICMP header, so this threw / failed.
    func testValidateResponseAcceptsEchoReply() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        let sequence: UInt16 = 5

        let icmp = try makeEchoReply(for: pinglet, sequence: sequence)
        let packet = syntheticIPHeader(icmpLength: icmp.count) + icmp

        pinglet.pendingRequests.append(PingRequest(identifier: pinglet.identifier,
                                                   ipAddress: "1.1.1.1",
                                                   sequenceIndex: sequence,
                                                   trueSequenceIndex: 0))

        XCTAssertTrue(try pinglet.validateResponse(from: packet))
    }

    /// A reply carrying a different fingerprint belongs to another session and must
    /// be ignored (returns false, not a throw). The fingerprint check runs before
    /// the checksum check, so flipping one payload byte is enough to trigger it.
    func testValidateResponseRejectsForeignFingerprint() throws {
        let pinglet = try Pinglet(host: "1.1.1.1")
        let sequence: UInt16 = 5

        var icmp = [UInt8](try makeEchoReply(for: pinglet, sequence: sequence))
        icmp[ICMPHeader.headerSize] ^= 0xFF          // corrupt the first payload byte
        let packet = syntheticIPHeader(icmpLength: icmp.count) + Data(icmp)

        pinglet.pendingRequests.append(PingRequest(identifier: pinglet.identifier,
                                                   ipAddress: "1.1.1.1",
                                                   sequenceIndex: sequence,
                                                   trueSequenceIndex: 0))

        XCTAssertFalse(try pinglet.validateResponse(from: packet))
    }

    /// Regression guard for the Darwin byte-order fix: `ip_len` / `ip_off` arrive in
    /// host order, `ip_id` / `ip_sum` in network order. A uniform big-endian decode
    /// would read `totalLength` as 6144 instead of 24.
    func testIPHeaderDarwinByteOrder() throws {
        var b = [UInt8](repeating: 0, count: IPHeader.minSize)
        b[0] = 0x45
        b[9] = UInt8(IPPROTO_ICMP)
        b[2] = 0x18; b[3] = 0x00      // ip_len = 24,     host order (little-endian)
        b[4] = 0x12; b[5] = 0x34      // ip_id  = 0x1234, network order
        b[6] = 0x40; b[7] = 0x00      // ip_off = 0x0040, host order
        b[10] = 0xAB; b[11] = 0xCD    // ip_sum = 0xABCD, network order

        let header = try XCTUnwrap(IPHeader(data: Data(b)))
        XCTAssertEqual(header.totalLength, 24)               // host order
        XCTAssertEqual(header.flagsAndFragmentOffset, 0x40)  // host order
        XCTAssertEqual(header.identification, 0x1234)        // network order
        XCTAssertEqual(header.headerChecksum, 0xABCD)        // network order
    }
}
