import Combine
import XCTest
@testable import Pinglet

extension AsyncSequence {
    func collect() async throws -> [Element] {
        try await reduce(into: [Element]()) { $0.append($1) }
    }
}

enum PingletTestError {
    case couldNotQueuePinglet
}

final class PingletTests: XCTestCase {

    var pinglet: Pinglet! = PingletTests.defaultPinglet

    private var subscriptions = Set<AnyCancellable>()
    private let pingRuntime: TimeInterval = 3
    private let testTimeout: TimeInterval = 11

    static var defaultPinglet: Pinglet {
        let config = PingConfiguration(interval: 0.25, timeout: 1)
        let ping: Pinglet = try! Pinglet(host: "1.1.1.1",
                                         configuration: config,
                                         queue: DispatchQueue.global(qos: .background))
        ping.runInBackground = true
        return ping
    }

    override func setUp() {
        super.setUp()
        pinglet = Self.defaultPinglet
    }

    override func tearDown() {
        super.tearDown()
        pinglet = nil
        subscriptions.removeAll()
    }

    func testPassthroughResponsePublisher() throws {
        var collectedResponses = [PingResponse]()
        pinglet.responsePublisher
               .sink(receiveCompletion: { completion in  },
                     receiveValue: { response in
                         print(response)
                         collectedResponses.append(response)
                     })
               .store(in: &subscriptions)
        try waitForDefaultPinglet()
        print("total pings: \(collectedResponses.count)")
        XCTAssert(collectedResponses.isEmpty == false)
    }

    func queueTestPinglet() throws -> XCTestExpectation {
        let expectation = XCTestExpectation()

        try pinglet.startPinging()

        DispatchQueue.main.asyncAfter(deadline: .now() + pingRuntime) {
            self.pinglet.stopPinging()
            expectation.fulfill()
        }

        return expectation
    }

    private func waitForDefaultPinglet() throws {
        let expectation: XCTestExpectation = try queueTestPinglet()
        wait(for: [expectation], timeout: testTimeout)
    }

    func testResponsePublisher() throws {
        var responses = [PingResponse]()
        pinglet.$responses
               .sink { pings in
                   print("Combine.pings: \(pings.count)")
                   responses = pings
               }
               .store(in: &subscriptions)

        try waitForDefaultPinglet()
        print("total pings: \(pinglet.responses.count)")
        XCTAssert(responses.isEmpty == false)
    }

    func testSimplePing() async throws {
        var requestTime: Date = Date()
        pinglet.requestObserver = { identifier, sequenceIndex in
            let diff = Date().timeIntervalSince1970 -  requestTime.timeIntervalSince1970
            let formattedResponseTime = String(format: "%0.2f", diff * 1000)
            print("request->id: \(identifier) sequenceIndex: \(sequenceIndex) --> \(formattedResponseTime)ms")
            requestTime = Date()
        }
        pinglet.responseObserver = { response in
            if response.duration < 0 {
                print("")
            }
            let formattedResponseTime = String(format: "%0.2f", response.duration * 1000)

            print("respnse<-id: \(response.identifier) sequenceIndex: \(response.sequenceIndex) <-- \(formattedResponseTime)ms Round-Trip \tTotalPings: \(self.pinglet.responses.count)")
        }

        try waitForDefaultPinglet()
        let pings: [PingResponse] = pinglet.responses
        print("total pings: \(pings.count)")
        XCTAssert(pings.isEmpty == false)
    }

}
