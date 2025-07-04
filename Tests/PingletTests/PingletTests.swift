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
@testable import Pinglet
import XCTest

extension AsyncSequence {
    func collect() async throws -> [Element] {
        try await reduce(into: [Element]()) { $0.append($1) }
    }
}

enum PingletTestError {
    case couldNotQueuePinglet
}

final class PingletTests: XCTestCase {
    var pinglet: Pinglet!

    private var observers = Set<AnyCancellable>()
    private var pingRuntime: TimeInterval = 5
    private var testTimeout: TimeInterval = 11

    static var defaultPinglet: Pinglet {
        let config = PingConfiguration(interval: 1, timeout: 3)
        let ping: Pinglet = try! Pinglet(host: "1.1.1.1",
                                         configuration: config,
                                         queue: DispatchQueue.global(qos: .background))
        ping.runInBackground = true
        #if os(iOS)
        ping.allowBackgroundPinging = true
        #endif
        return ping
    }

    override func setUp() {
        super.setUp()
        pingRuntime = 5
        testTimeout = 11
        pinglet = Self.defaultPinglet

        // Setup some debug observers for the request and response publishers of the default pinglet for tests.
        // Individual tests might invalidate these if `pinglet` gets overwritten as part of the test.
        pinglet.requestPublisher
                .sink(receiveCompletion: { _ in },
                        receiveValue: { request in
                            Log.ping.notice("----> \(String(describing: request), privacy: .public)")
                        })
                .store(in: &observers)

        pinglet.responsePublisher
                .sink(receiveCompletion: { _ in },
                        receiveValue: { response in
                            Log.ping.notice("<---- \(String(describing: response), privacy: .public)")
                        })
                .store(in: &observers)
    }

    override func tearDown() {
        super.tearDown()
        pinglet.requestObserver = nil
        pinglet.responseObserver = nil
        pinglet = nil
        observers.removeAll()
    }

    func testPassthroughResponsePublisher() throws {
        var collectedResponses = [PingResponse]()
        pinglet.responsePublisher
            .sink(receiveCompletion: { _ in },
                  receiveValue: { response in
                      print(response)
                      collectedResponses.append(response)
                  })
            .store(in: &observers)
        try waitForDefaultPinglet()
        print("total pings: \(collectedResponses.count)")
        XCTAssert(collectedResponses.isEmpty == false)
    }

    func _testMultipleStartStop() throws {
        var collectedResponses = [PingResponse]()
        pinglet.responsePublisher
            .sink(receiveCompletion: { _ in },
                  receiveValue: { response in
                      print("response.duration: \(response.duration)")
                      if response.duration < 0 {
                          print("BREAK")
                      }
                      XCTAssert(response.duration > 0)
                      collectedResponses.append(response)
                  })
            .store(in: &observers)
        for count in 0 ... 5 {
            try waitForDefaultPinglet()
            print("[\(count) loop count] total pings: \(collectedResponses.count)")
            XCTAssert(collectedResponses.isEmpty == false)
        }
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

    func testNoRegisteredObservers() throws {
        try waitForDefaultPinglet()
    }

    #if os(iOS)
    func testAutoStopInBackground() throws {
        pinglet.allowBackgroundPinging = false
        pinglet.runInBackground = false

        var responses = [PingResponse]()
        pinglet.$responses
            .sink { pings in
                print("Ping Count: \(pings.count)")
                responses = pings
            }
            .store(in: &subscriptions)

        // Ping for 4 seconds
        try pinglet.startPinging()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 4))
        XCTAssert(responses.count > 1)

        // Post the "background notification"
        print("UIApplication.didEnterBackgroundNotification")
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Verify that pings are not happening after `didEnterBackgroundNotification`
        // by checking that `responses.count` is the same after waiting 4 seconds.
        let preCount: Int = responses.count
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 4))
        let postCount: Int = responses.count
        XCTAssert(preCount == postCount)

        // Post the "foreground notification"
        print("UIApplication.didBecomeActiveNotification")
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 4))

        XCTAssert(responses.count > postCount)
    }
    #endif

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
            .store(in: &observers)

        let expectation = XCTestExpectation()

        print("Ping Start")
        try pinglet.startPinging()

        DispatchQueue.main.asyncAfter(deadline: .now() + pingRuntime) {
            print("Ping Stop")
            self.pinglet.stopPinging()
            expectation.fulfill()
        }

        for milliseconds in [100, 200, 300, 400, 500, 600, 700, 800, 900] {
            let pinglet = pinglet!
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                print("Ping Multiple-start")
                try? pinglet.startPinging()
            }
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
            .store(in: &observers)

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

        var requestTime = Date()
        pinglet.requestObserver = { identifier, sequenceIndex in
            let diff = Date().timeIntervalSince1970 - requestTime.timeIntervalSince1970
            let formattedResponseTime = String(format: "%0.2f", diff * 1000)
            print("request->id: \(identifier) sequenceIndex: \(sequenceIndex) --> \(formattedResponseTime)ms")
            requestTime = Date()
        }
        pinglet.responseObserver = { response in
            if response.duration < 0 {
                print("")
            }
            let formattedResponseTime = String(format: "%0.2f", response.duration * 1000)
            let count = self.pinglet.responses.count
            print("respnse<-id: \(response.identifier) sequenceIndex: \(response.sequenceIndex) <-- \(formattedResponseTime)ms Round-Trip \tTotalPings: \(count)")
        }

        try waitForDefaultPinglet()
        let pings: [PingResponse] = pinglet.responses
        print("total pings: \(pings.count)")
        XCTAssert(pings.isEmpty == false)
    }

    func testStopViaTimer() throws {
        let config = PingConfiguration(interval: 0.001, timeout: pinglet.configuration.timeoutInterval)
        pingRuntime = 1
        pinglet = try Pinglet(destination: pinglet.destination, configuration: config)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(888)) {
            print("stopped via timer on global queue")
            self.pinglet.stopPinging()
        }
        try testSimplePing()
    }

    func testLogErrorCodes() {
        PingError.logErrorCodes()
    }

    func testSaveronePinger() throws {
        let expectation = XCTestExpectation()
        let pinger = Pinger()
        pinger.start(5)
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(6)) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 7)
    }
}

class Pinger {
    static let shared = Pinger()
    internal init() {}

    private var pinglet: Pinglet?
    private weak var pingTimer: Timer?

    func start(_ duration: Double) {
        stop()
        if pinglet == nil {
            print("ping init !!")
            pinglet = try? Pinglet(host: "8.8.8.8",
                                   configuration: PingConfiguration(interval: 0.1),
                                   queue: DispatchQueue.global())
        }
        pinglet?.runInBackground = true
        try? pinglet?.startPinging()
        print("ping start")
        pingTimer = Timer.scheduledTimer(timeInterval: duration,
                                         target: self,
                                         selector: #selector(stop(_:)),
                                         userInfo: nil,
                                         repeats: false)
    }

    @objc
    func stop(_: Timer? = nil) {
        if pingTimer != nil {
            print("ping timer ended")
        }
        pingTimer?.invalidate()
        pingTimer = nil
        pinglet?.stopPinging()
        pinglet = nil
        print("ping stop")
    }
}
