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
import Darwin
import Foundation
import Socket2Me

#if os(iOS)
import UIKit
#endif

public typealias RequestObserver = (_ identifier: UInt16, _ sequenceIndex: Int) -> Void
public typealias ResponseObserver = (_ response: PingResponse) -> Void
public typealias FinishedCallback = (_ result: PingResult) -> Void

/// Represents a ping delegate.
public protocol PingDelegate {
    /// Called when a ping response is received.
    /// - Parameter response: A `PingResponse` object representing the echo reply.
    func didReceive(response: PingResponse)
    func didSend(identifier: UInt16, sequenceIndex: Int)
}

// MARK: Pinglet

/// Class representing socket info, which contains a `Pinglet` instance and the identifier.
public class SocketInfo {
    public weak var pinglet: Pinglet?
    public let identifier: UInt16

    public init(pinglet: Pinglet, identifier: UInt16) {
        self.pinglet = pinglet
        self.identifier = identifier
    }
}

/// Represents a single ping instance. A ping instance has a single destination.
public class Pinglet: NSObject, ObservableObject {
    /// Describes the ping host destination.

    // MARK: - Initialization

    /// Ping host
    public let destination: Destination
    /// Ping configuration
    public let configuration: PingConfiguration
    /// This closure gets called with each ping request.
    public var requestObserver: RequestObserver?
    /// This closure gets called with each ping response.
    public var responseObserver: ResponseObserver?
    public var responsePublisher: AnyPublisher<PingResponse, PingError> { responsePassthrough.eraseToAnyPublisher() }
    private var responsePassthrough = PassthroughSubject<PingResponse, PingError>()

    /// This closure gets called when pinging stops, either when `targetCount` is reached or pinging is stopped explicitly with `stop()` or `halt()`.
    public var finished: FinishedCallback?
    /// This delegate gets called with ping responses.
    public var delegate: PingDelegate?
    /// The number of pings to make. Default is `nil`, which means no limit.
    public var targetCount: Int?

    /// The current ping count, starting from 0.
    public var currentCount: UInt64 {
        trueSequenceIndex
    }

    /// Array of all ping responses sent to the `observer`.
    @Published
    public private(set) var responses: [PingResponse] = []

    internal var pendingRequests: [PingRequest] = []

    /// Flag to enable socket processing on a background thread
    public var runInBackground: Bool = false

    /// A random identifier which is a part of the ping request.
    internal let identifier = UInt16.random(in: 0 ..< UInt16.max)

    /// A random UUID fingerprint sent as the payload.
    internal let fingerprint = UUID()

    /// User-specified dispatch queue. The `observer` is always called from this queue.
    internal let currentQueue: DispatchQueue

    internal var socket: Socket2Me?

    /// The current sequence number.
    private var _sequenceIndex: UInt16 = 0
    internal var sequenceIndex: UInt16 {
        get { serialProperty.sync { _sequenceIndex } }
        set { serialProperty.sync { _sequenceIndex = newValue } }
    }

    /// The true sequence number.
    private var _trueSequenceIndex: UInt64 = 0
    private var trueSequenceIndex: UInt64 {
        get { serialProperty.sync { _trueSequenceIndex } }
        set { serialProperty.sync { _trueSequenceIndex = newValue } }
    }

    internal var erroredIndices = [Int]()

    internal var cancellables = Set<AnyCancellable>()
    internal var notificationCancellables = Set<AnyCancellable>()
    internal var timeoutTimers = [AnyHashable: Timer]()

    /// Initializes a pinglet.
    /// - Parameter destination: Specifies the host.
    /// - Parameter configuration: A configuration object which can be used to customize pinging behavior.
    /// - Parameter queue: All responses are delivered through this dispatch queue.
    public init(destination: Destination,
                configuration: PingConfiguration = PingConfiguration(),
                queue: DispatchQueue = DispatchQueue.main) throws {
        self.destination = destination
        self.configuration = configuration
        currentQueue = queue

        super.init()

        #if os(iOS)
        if configuration.handleBackgroundTransitions {
            addAppStateChangeObservers()
        }
        #endif
    }

    #if os(iOS)
    /// A public flag to control whether to halt the pinglet automatically on didEnterBackgroundNotification
    public var allowBackgroundPinging = false
    /// A flag to determine whether the pinglet was halted automatically by an app state change.
    private var autoHalted = false

    /// Adds notification observers for iOS app state changes.
    private func addAppStateChangeObservers() {
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [unowned self] (_: Notification) in
                if allowBackgroundPinging { return }
                autoHalted = true
                stopPinging(resetSequence: false)
            }
            .store(in: &notificationCancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [unowned self] (_: Notification) in
                if autoHalted {
                    autoHalted = false
                    try? startPinging()
                }
            }
            .store(in: &notificationCancellables)
    }
    #endif

    // MARK: - Convenience Initializers

    /// Initializes a pinglet from an IPv4 address string.
    /// - Parameter ipv4Address: The host's IP address.
    /// - Parameter configuration: A configuration object which can be used to customize pinging behavior.
    /// - Parameter queue: All responses are delivered through this dispatch queue.
    public convenience init(ipv4Address: String,
                            config configuration: PingConfiguration = PingConfiguration(),
                            queue: DispatchQueue = DispatchQueue.main) throws {
        var socketAddress = sockaddr_in()

        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = UInt8(AF_INET)
        socketAddress.sin_port = 0
        socketAddress.sin_addr.s_addr = inet_addr(ipv4Address.cString(using: .utf8))
        let data = Data(bytes: &socketAddress, count: MemoryLayout<sockaddr_in>.size)

        let destination = Destination(host: ipv4Address, ipv4Address: data)
        try self.init(destination: destination, configuration: configuration, queue: queue)
    }

    /// Initializes a pinglet from a given host string.
    /// - Parameter host: A string describing the host. This can be an IP address or host name.
    /// - Parameter configuration: A configuration object which can be used to customize pinging behavior.
    /// - Parameter queue: All responses are delivered through this dispatch queue.
    /// - Throws: A `PingError` if the given host could not be resolved.
    public convenience init(host: String,
                            configuration: PingConfiguration = PingConfiguration(),
                            queue: DispatchQueue = DispatchQueue.main) throws {
        let result = try Destination.getIPv4AddressFromHost(host: host)
        let destination = Destination(host: host, ipv4Address: result)
        try self.init(destination: destination, configuration: configuration, queue: queue)
    }

    /// Initializes a CFSocket.
    /// - Throws: If setting a socket options flag fails, throws a `PingError.socketOptionsSetError(:)`.
    private func createSocket() throws {
        socket = Socket2Me(destination: destination)
        socket?.runInBackground = runInBackground
        createDataSentPipeline()
        createDataReceivedPipeline()
    }

    private func createDataSentPipeline() {
        socket?.dataSentPublisher
            .tryMap { (data: Data) -> ICMPHeader in
                try ICMPHeader.from(data: data)
            }
            .mapError { error -> PingError in
                switch error {
                case let pingError as PingError:
                    return pingError
                default:
                    return .generic(error)
                }
            }
            .sink(receiveCompletion: { completion in
                      print("dataSentPublisher.receiveCompletion: \(completion)")
                  },
                  receiveValue: { (header: ICMPHeader) in
                      let identifier = header.identifierToHost
                      let sequenceIndex = header.sequenceNumberToHost
                      self.delegate?.didSend(identifier: identifier, sequenceIndex: Int(sequenceIndex))
                      self.requestObserver?(self.identifier, Int(sequenceIndex))
                  })
            .store(in: &cancellables)
    }

    private func createDataReceivedPipeline() {
        socket?.dataReceivedPublisher
            .removeDuplicates()
            .tryCompactMap { (data: Data) in
                var sequence: UInt16? = .none
                var id: UInt16? = .none
                var validationError: PingError?

                do {
                    let _: Bool = try self.validateResponse(from: data)
                    let icmp: ICMPHeader = try ICMPHeader.from(data: data)
                    sequence = icmp.sequenceNumberToHost
                    id = icmp.identifierToHost
                }
                catch {
                    switch error {
                    case let pingError as PingError:
                        validationError = pingError
                    default:
                        validationError = PingError.generic(error)
                    }
                }
                let ipHeader: IPHeader = data.withUnsafeBytes { $0.load(as: IPHeader.self) }

                // // Get the request from the sequence index of the echoed ICMP Packet
                guard id == self.identifier else { return nil }
                guard let sequenceIndex: UInt16 = sequence,
                      let request: PingRequest = self.pendingRequest(for: Int(sequenceIndex)) else {
                    print("Could not look up pending request for sequenceIndex: \(String(describing: sequence))")
                    return nil
                }

                return PingResponse(identifier: request.identifier,
                                    ipAddress: request.ipAddress,
                                    sequenceIndex: request.sequenceIndex,
                                    trueSequenceIndex: request.trueSequenceIndex,
                                    duration: request.timeIntervalSinceStart,
                                    error: validationError,
                                    byteCount: data.count,
                                    ipHeader: ipHeader)
            }
            .mapError { error -> PingError in
                switch error {
                case let pingError as PingError:
                    return pingError
                default:
                    return .generic(error)
                }
            }
            .sink(receiveCompletion: { [unowned self] (completion: Subscribers.Completion<Error>) in
                      switch completion {
                      case .finished:
                          print("Socket \(String(describing: socket)) was closed")
                      case let .failure(reason):
                          print("Socket \(String(describing: socket)) was closed because: \(reason)")
                      }
                      print("receiveCompletion: \(completion)")
                  },
                  receiveValue: { (response: PingResponse) in
                      self.informObservers(of: response)
                  })
            .store(in: &cancellables)
    }

    // MARK: - Tear-down

    private func tearDown() {
        print("Pinglet: tearDown")
        socket = nil

        pendingRequests.removeAll()
        timeoutTimers.forEach { _, timer in
            timer.invalidate()
        }
        timeoutTimers.removeAll()

        // Skip clearing notification listeners if we have been stopped because we're in the background.
        if autoHalted == false {
            notificationCancellables.removeAll()
        }
        cancellables.removeAll()
    }

    deinit {
        tearDown()
    }

    // MARK: - Single ping

    private var _isPinging = false
    private var isPinging: Bool {
        get { serialProperty.sync { _isPinging } }
        set { serialProperty.sync { _isPinging = newValue } }
    }

    private func sendPing(request: PingRequest) {
        guard let icmpPackage: Data = try? createICMPPackage(identifier: UInt16(request.identifier),
                                                             sequenceNumber: UInt16(request.sequenceIndex))
        else {
            print("Error creating icmp package!")
            return
        }
        scheduleTimeout(for: request)
        socket?.send(data: icmpPackage)
        scheduleNextPing()
    }

    private func sendPing() {
        if killSwitch { return }
        serial.async { [self] in
            sendPing(request: PingRequest(identifier: identifier,
                                          ipAddress: destination.ip,
                                          sequenceIndex: sequenceIndex,
                                          trueSequenceIndex: trueSequenceIndex))
        }
    }

    internal func informObservers(of response: PingResponse) {
        currentQueue.async {
            self.completeRequest(for: Int(response.sequenceIndex))
            self.responses.append(response)
            self.responsePassthrough.send(response)
            self.responseObserver?(response)
            self.delegate?.didReceive(response: response)
        }
    }

    // MARK: - Continuous ping

    private func isTargetCountReached() -> Bool {
        if let target = targetCount {
            if sequenceIndex >= target {
                return true
            }
        }
        return false
    }

    private func canSchedulePing() -> Bool {
        if killSwitch { return false }
        if isTargetCountReached() { return false }
        return true
    }

    private func scheduleNextPing() {
        if isTargetCountReached() {
            if configuration.haltAfterTarget {
                stopPinging()
            }
            else {
                informFinishedStatus(trueSequenceIndex)
            }
        }
        if canSchedulePing() {
            serial.asyncAfter(deadline: .now() + configuration.pingInterval) {
                self.incrementSequenceIndex()
                self.sendPing()
            }
        }
    }

    private func informFinishedStatus(_ sequenceIndex: UInt64) {
        if let callback = finished {
            var roundTrip: PingResult.Roundtrip?
            let roundTripTimes: [TimeInterval] = responses.filter { $0.error == nil }.map { $0.duration }
            if roundTripTimes.count != 0,
               let min = roundTripTimes.min(),
               let max = roundTripTimes.max() {
                let count = Double(roundTripTimes.count)
                let total = roundTripTimes.reduce(0, +)
                let avg = total / count
                let variance = roundTripTimes.reduce(0) { $0 + ($1 - avg) * ($1 - avg) }
                let stddev = sqrt(variance / count)

                roundTrip = PingResult.Roundtrip(minimum: min, maximum: max, average: avg, standardDeviation: stddev)
            }

            let result = PingResult(responses: responses, packetsTransmitted: sequenceIndex, packetsReceived: UInt64(roundTripTimes.count), roundtrip: roundTrip)
            callback(result)
        }
    }

    private let serial = DispatchQueue(label: "Pinglet internal", qos: .utility)
    internal let serialProperty = DispatchQueue(label: "Pinglet internal property", qos: .utility)

    private var _killSwitch = false
    internal var killSwitch: Bool {
        get { serialProperty.sync { _killSwitch } }
        set { serialProperty.sync { _killSwitch = newValue } }
    }

    /// Start pinging the host.
    public func startPinging() throws {
        guard isPinging == false else {
            return
        }
        if socket == nil {
            try createSocket()
        }
        killSwitch = false
        isPinging = true
        sendPing()
    }

    /// Stops pinging the host and destroys the CFSocket object.
    /// - Parameter resetSequence: Controls whether the sequence index should be set back to zero.
    public func stopPinging(resetSequence: Bool = true) {
        guard isPinging == true else { return }
        killSwitch = true
        isPinging = false
        let count = trueSequenceIndex
        if resetSequence {
            sequenceIndex = 0
            trueSequenceIndex = 0
            erroredIndices.removeAll()
        }
        informFinishedStatus(count)
        tearDown()
    }

    private func incrementSequenceIndex() {
        // Handle overflow gracefully
        if sequenceIndex >= UInt16.max { sequenceIndex = 0 }
        else { sequenceIndex += 1 }

        if trueSequenceIndex >= UInt64.max { trueSequenceIndex = 0 }
        else { trueSequenceIndex += 1 }
    }
}
