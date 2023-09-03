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
        let ping: Pinglet = try! Pinglet(host: "24mountains.com",
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

    func testMultipleStartInOneSession() throws {
        var responses = [PingResponse]()
        pinglet.$responses
                .sink { pings in
                    print("Combine.pings: \(pings.count)")
                    responses = pings
                }
                .store(in: &subscriptions)

        let expectation = XCTestExpectation()

        print("Ping Start")
        try pinglet.startPinging()

        DispatchQueue.main.asyncAfter(deadline: .now() + pingRuntime) {
            print("Ping Stop")
            self.pinglet.stopPinging()
            expectation.fulfill()
        }


        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            print("Ping Multiple-start")
            try? self.pinglet.startPinging()
            try? self.pinglet.startPinging()
            try? self.pinglet.startPinging()
            try? self.pinglet.startPinging()
            try? self.pinglet.startPinging()
            try? self.pinglet.startPinging()
            try? self.pinglet.startPinging()
        }
        wait(for: [expectation], timeout: testTimeout)

        print("total pings: \(pinglet.responses.count)")
        XCTAssert(responses.isEmpty == false)
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

    func testFloodPing() throws {
        let config = PingConfiguration(interval: 0.001, timeout: pinglet.configuration.timeoutInterval)
        pinglet = try Pinglet(destination: pinglet.destination, configuration: config)
        try testSimplePing()
    }

    func testSimplePing() throws {
        let formattedInterval = String(format: "%0.2f", pinglet.configuration.pingInterval * 1000)
        print("Starting ping with \(formattedInterval)ms interval...")

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
