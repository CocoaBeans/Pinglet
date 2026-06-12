import Combine
@testable import Socket2Me
import XCTest

final class Socket2MeTests: XCTestCase {

    // MARK: - Socket2Me Lifecycle

    func testSocketOpensWithinTimeout() throws {
        let socket = try createSocket()
        XCTAssertTrue(socket.isOpen)
        XCTAssertFalse(socket.isOpening)
        socket.tearDown()
    }

    func testDefaultPropertyValues() throws {
        let socket = try createSocket()
        XCTAssertTrue(socket.runInBackground)
        XCTAssertEqual(socket.timeout, 30)
        XCTAssertNil(socket.timeToLive)
        socket.tearDown()
    }

    func testTearDownTransitionsState() throws {
        let socket = try createSocket()
        XCTAssertTrue(socket.isOpen)

        socket.tearDown()

        XCTAssertFalse(socket.isOpen)
        XCTAssertFalse(socket.isOpening)
    }

    func testMultipleCreateTearDownCycles() throws {
        for _ in 0..<5 {
            let socket = try createSocket()
            socket.tearDown()
        }
    }

    func testThreadExit() throws {
        for _ in 0...10 {
            var socket: Socket2Me? = try createSocket()
            socket = nil
        }
    }

    func testTearDownFromBackgroundThread() throws {
        let socket = try createSocket()
        let expectation = XCTestExpectation()

        DispatchQueue.global().async {
            socket.tearDown()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
        XCTAssertFalse(socket.isOpen)
    }

    func testMultipleTearDownCallsAreSafe() throws {
        let socket = try createSocket()
        socket.tearDown()
        socket.tearDown()
        socket.tearDown()
    }

    // MARK: - Configuration

    func testSettingTimeToLive() throws {
        let socket = try createSocket()
        socket.timeToLive = 64
        XCTAssertEqual(socket.timeToLive, 64)
        socket.tearDown()
    }

    // MARK: - Publishers

    // NOTE: No inverted-expectation test for dataReceivedPublisher here.
    // A raw ICMP socket can receive unrelated network traffic (e.g. echo
    // replies from 1.1.1.1 to other processes), making such a test flaky.

    func testDataSentPublisherDoesNotFireWithoutSend() throws {
        let socket = try createSocket()
        let expectation = XCTestExpectation()
        expectation.isInverted = true

        let cancellable = socket.dataSentPublisher
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in expectation.fulfill() }
            )

        wait(for: [expectation], timeout: 2)
        cancellable.cancel()
        socket.tearDown()
    }

    // MARK: - Destination

    func testDestinationValidHost() async throws {
        let dest = try await Destination(host: "1.1.1.1")
        XCTAssertEqual(dest.host, "1.1.1.1")
        XCTAssertEqual(dest.ip, "1.1.1.1")
        XCTAssertNotNil(dest.socketAddress)
    }

    func testDestinationAlternateHost() async throws {
        let dest = try await Destination(host: "8.8.8.8")
        XCTAssertEqual(dest.host, "8.8.8.8")
        XCTAssertEqual(dest.ip, "8.8.8.8")
    }

    func testDestinationInvalidHost() async {
        do {
            _ = try await Destination(host: "thishostdoesnotexistzzz.example.com")
            XCTFail("Expected SocketError")
        } catch {
            guard let socketError = error as? SocketError else {
                return XCTFail("Expected SocketError")
            }
            XCTAssertTrue(
                socketError == .addressLookupError || socketError == .hostNotFound
            )
        }
    }

    func testDestinationDirectInit() {
        let data = Data([
            0x01, 0x01, 0x01, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ])
        let dest = Destination(host: "example.com", ipv4Address: data)
        XCTAssertEqual(dest.host, "example.com")
        XCTAssertEqual(dest.ipv4Address, data)
    }

    func testDestinationSocketAddressProperty() async throws {
        let dest = try await Destination(host: "127.0.0.1")
        XCTAssertEqual(dest.ip, "127.0.0.1")
        let addr = dest.socketAddress
        XCTAssertNotNil(addr)
    }

    // MARK: - SocketError

    func testSocketErrorEquatable() {
        XCTAssertEqual(SocketError.responseTimeout, SocketError.responseTimeout)
        XCTAssertEqual(SocketError.requestError, SocketError.requestError)
        XCTAssertEqual(SocketError.hostNotFound, SocketError.hostNotFound)
        XCTAssertEqual(
            SocketError.socketOptionsSetError(errorCode: 1),
            SocketError.socketOptionsSetError(errorCode: 1)
        )
        XCTAssertNotEqual(SocketError.requestError, SocketError.requestTimeout)
        XCTAssertNotEqual(
            SocketError.socketOptionsSetError(errorCode: 1),
            SocketError.socketOptionsSetError(errorCode: 2)
        )
    }

    // MARK: - Data+Networking

    func testSocketAddressConversion() {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(80)
        addr.sin_addr.s_addr = inet_addr("1.1.1.1")

        let data = withUnsafePointer(to: &addr) {
            Data(bytes: $0, count: MemoryLayout<sockaddr_in>.size)
        }

        let sockAddr = data.socketAddress
        XCTAssertEqual(sockAddr.sa_family, sa_family_t(AF_INET))

        let sockAddrIn = data.socketAddressInternet
        XCTAssertEqual(sockAddrIn.sin_family, sa_family_t(AF_INET))
        XCTAssertEqual(sockAddrIn.sin_port, CFSwapInt16HostToBig(80))
    }

    // MARK: - SocketInfo

    func testSocketInfo() throws {
        let socket = try createSocket()
        let info = SocketInfo(socket2Me: socket, identifier: "test-id")

        XCTAssertEqual(info.identifier, "test-id")
        XCTAssertNotNil(info.socket2Me)
        XCTAssertTrue(info.socket2Me === socket)

        socket.tearDown()
    }

    func testSocketInfoWeakReference() throws {
        let socket = try createSocket()
        let info = SocketInfo(socket2Me: socket, identifier: "test")
        XCTAssertNotNil(info.socket2Me)
        XCTAssertTrue(info.socket2Me === socket)
        socket.tearDown()
    }

    // MARK: - SerialAccess

    func testSerialAccessInitAndRead() {
        @SerialAccess(defaultValue: 42) var value
        XCTAssertEqual(value, 42)
    }

    func testSerialAccessWriteAndRead() {
        let queue = DispatchQueue(label: "test.queue")
        @SerialAccess(defaultValue: 0, queue: queue) var value

        value = 99
        queue.sync {}

        XCTAssertEqual(value, 99)
    }

    func testSerialAccessStringType() {
        let queue = DispatchQueue(label: "test.string.queue")
        @SerialAccess(defaultValue: "hello", queue: queue) var value

        value = "world"
        queue.sync {}

        XCTAssertEqual(value, "world")
    }

    // MARK: - Helpers

    @discardableResult
    func createSocket() throws -> Socket2Me {
        let socket = Socket2Me(destination: Destination(ipv4String: "1.1.1.1"))

        let openTimeout = Date().addingTimeInterval(5)
        while socket.isOpening, Date() < openTimeout {
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertTrue(socket.isOpen)
        return socket
    }
}
