import Combine
import XCTest
@testable import Pinglet

extension AsyncSequence {
    func collect() async throws -> [Element] {
        try await reduce(into: [Element]()) { $0.append($1) }
    }
}

final class PingletTests: XCTestCase {

    var swiftyPing: Pinglet? = PingletTests.defaultPing

    private var subscriptions = Set<AnyCancellable>()

    static var defaultPing: Pinglet {
        let config = PingConfiguration(interval: 0.1)
        let ping: Pinglet = try! Pinglet(host: "1.1.1.1",
                                         configuration: config,
                                         queue: DispatchQueue.global(qos: .background))
        ping.runInBackground = true
        return ping
    }

    override func setUp() {
        super.setUp()
        swiftyPing = Self.defaultPing
    }

    override func tearDown() {
        super.tearDown()
        swiftyPing = nil
    }

    @available(macOS 12.0, iOS 15.0, *)
    func testSimplePing() async throws {
        guard let ping: Pinglet = swiftyPing else {
            XCTAssert(false)
            return
        }

        // ping.responses
        //     .publisher
        //     .collect()
        //     .sink { pings in
        //         print("Combine.pings: \(pings)")
        //     }
        //     .store(in: &subscriptions)

        let expectation = XCTestExpectation()
        var requestTime: Date = Date()
        ping.requestObserver = { identifier, sequenceIndex in
            let diff = Date().timeIntervalSince1970 -  requestTime.timeIntervalSince1970
            let formattedResponseTime = String(format: "%0.2f", diff * 1000)
            print("id: \(identifier) sequenceIndex: \(sequenceIndex) --> \(formattedResponseTime)ms")
            requestTime = Date()
        }
        ping.responseObserver = { (response: PingResponse) in
            let _ = Date().timeIntervalSince1970
            // print("response: \(response)")
            print("")
        }
        try ping.startPinging()


        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
            ping.stopPinging()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 11)

        let pings: [PingResponse] = try await ping.responses.publisher.values.collect()
        print("ping: \(pings.count)")
        XCTAssert(pings.isEmpty == false)
    }
}
