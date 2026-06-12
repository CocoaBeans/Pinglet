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

/// Closure called when a ping request is sent.
public typealias RequestObserver = (_ identifier: UInt16, _ sequenceIndex: Int) -> Void
/// Closure called with each ping response.
public typealias ResponseObserver = (_ response: PingResponse) -> Void
/// Closure called when pinging finishes (targetCount reached, stopPinged, or halt() called).
public typealias FinishedCallback = (_ result: PingResult) -> Void

/// Delegate protocol for receiving ping send and response events.
public protocol PingDelegate: AnyObject {
    /// Called when a ping response is received.
    /// - Parameter response: The `PingResponse` representing the echo reply.
    func didReceive(response: PingResponse)
    /// Called when a ping request is sent.
    /// - Parameters:
    ///   - identifier: The session identifier for this ping.
    ///   - sequenceIndex: The sequence number of the sent request.
    func didSend(identifier: UInt16, sequenceIndex: Int)
}

// MARK: Pinglet



/// Sends ICMP echo requests to a host and receives echo replies.
///
/// `Pinglet` supports both single pings (via `targetCount`) and continuous pinging
/// (when `targetCount` is `nil`). It delivers events via closure observers, Combine
/// publishers, and the `PingDelegate` protocol.
public class Pinglet: NSObject, ObservableObject {

    // MARK: - Initialization

    /// The ping destination (host and IP address).
    public let destination: Destination

    /// Configuration controlling ping interval, timeout, and other behaviors.
    public let configuration: PingConfiguration

    /// Closure called when a ping request is sent.
    public var requestObserver: RequestObserver?

    /// Combine publisher for ping requests.
    public var requestPublisher: AnyPublisher<PingRequest, PingError> { requestPassthrough.eraseToAnyPublisher() }
    private var requestPassthrough = PassthroughSubject<PingRequest, PingError>()

    /// Closure called when a ping response is received.
    public var responseObserver: ResponseObserver?

    /// Combine publisher for ping responses.
    public var responsePublisher: AnyPublisher<PingResponse, PingError> { responsePassthrough.eraseToAnyPublisher() }
    private var responsePassthrough = PassthroughSubject<PingResponse, PingError>()

    /// Closure called when pinging finishes (targetCount reached, stopPinged, or halt() called).
    public var finished: FinishedCallback?

    /// Delegate for receiving ping send and response events.
    public weak var delegate: PingDelegate?

    /// Number of pings to send. `nil` means continuous pinging until `stopPinging()` is called.
    public var targetCount: Int?

    /// Current count of successfully sent pings, starting from 0.
    public var currentCount: UInt64 {
        trueSequenceIndex
    }

    /// Published array of all ping responses received so far.
    @Published
    public private(set) var responses: [PingResponse] = []

    internal var pendingRequests: [PingRequest] = []

    /// When `true`, the underlying socket is opened on a detached background thread.
    /// Default is `false`. Set to `true` to avoid blocking the main thread during socket creation.
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

    private var pingTimer: Timer?
    internal var cancellables = Set<AnyCancellable>()
    internal var notificationCancellables = Set<AnyCancellable>()
    internal var timeoutTimers = [AnyHashable: Timer]()

    /// Initializes a `Pinglet` for the given destination.
    ///
    /// - Parameters:
    ///   - destination: The host to ping, created via `Destination`.
    ///   - configuration: A `PingConfiguration` object customizing interval, timeout, and other behaviors.
    ///   - queue: The dispatch queue on which observers and publishers deliver events. Defaults to the main queue.
    /// - Throws: A `PingError` if socket creation fails.
    public init(destination: Destination,
                configuration: PingConfiguration = PingConfiguration(),
                queue: DispatchQueue = DispatchQueue.main) throws {
        self.destination = destination
        self.configuration = configuration
        currentQueue = DispatchQueue(label: "Pinglet Internal", target: queue)
        super.init()

        #if os(iOS)
        if configuration.handleBackgroundTransitions {
            addAppStateChangeObservers()
        }
        #endif
    }

    #if os(iOS)
    /// When `true`, the ping continues even after the app enters the background.
    /// Default is `false`. Ignored on macOS.
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
        let destination = Destination(ipv4Address: ipv4Address)
        try self.init(destination: destination, configuration: configuration, queue: queue)
    }

    /// Initializes a pinglet from a given host string.
    /// - Parameter host: A string describing the host. This can be an IP address or host name.
    /// - Parameter configuration: A configuration object which can be used to customize pinging behavior.
    /// - Parameter queue: All responses are delivered through this dispatch queue.
    /// - Throws: A `PingError` if the given host could not be resolved.
    @available(*, deprecated, message: "Blocking DNS resolution. Use 'init(host:configuration:queue:) async throws' instead.")
    public convenience init(host: String,
                            configuration: PingConfiguration = PingConfiguration(),
                            queue: DispatchQueue = DispatchQueue.main) throws {
        let result = try Destination.getIPv4AddressFromHost(host: host)
        let destination = Destination(host: host, ipv4Address: result)
        try self.init(destination: destination, configuration: configuration, queue: queue)
    }

    /// Initializes a pinglet from a given host string, resolving the host asynchronously.
    ///
    /// Unlike the synchronous overload, DNS resolution does not block the calling thread —
    /// it is awaited via `Destination.resolve(host:)`. Prefer this initializer from any
    /// `async` context.
    /// - Parameter host: A string describing the host. This can be an IP address or host name.
    /// - Parameter configuration: A configuration object which can be used to customize pinging behavior.
    /// - Parameter queue: All responses are delivered through this dispatch queue.
    /// - Throws: A `PingError` if the given host could not be resolved.
    public convenience init(host: String,
                            configuration: PingConfiguration = PingConfiguration(),
                            queue: DispatchQueue = DispatchQueue.main) async throws {
        let destination = try await Destination(host: host)
        try self.init(destination: destination, configuration: configuration, queue: queue)
    }

    /// Initializes a CFSocket.
    /// - Throws: If setting a socket options flag fails, throws a `PingError.socketOptionsSetError(:)`.
    private func createSocket() throws {
        // Log.ping.trace(#function)
        socket = Socket2Me(destination: destination)
        socket?.runInBackground = runInBackground
        socket?.timeToLive = configuration.timeToLive

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
            .sink(receiveCompletion: { _ in },
                  receiveValue: { (header: ICMPHeader) in
                      let identifier = header.identifierToHost
                      let sequenceIndex = header.sequenceNumberToHost
                      self.delegate?.didSend(identifier: identifier, sequenceIndex: Int(sequenceIndex))
                      self.requestObserver?(self.identifier, Int(sequenceIndex))
                  })
            .store(in: &cancellables)
    }

    private func createDataReceivedPipeline() {
        // Log.ping.trace(#function)
        // Log.ping.debug("createDataReceivedPipeline for session id: \(self.identifier)")
        socket?.dataReceivedPublisher
            .removeDuplicates()
            .replaceError(with: Data())
            .filter { $0.isEmpty == false }
            .tryCompactMap { [weak self] (data: Data) in
                var sequence: UInt16? = .none
                var id: UInt16? = .none
                var validationError: PingError?

                do {
                    let _ = try self?.validateResponse(from: data)
                    guard let headerOffset = ICMPHeader.headerOffset(in: data) else {
                        throw PingError.invalidHeaderOffset
                    }
                    let icmp: ICMPHeader = try ICMPHeader.from(data: data, offset: headerOffset)
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

                // Get the request from the sequence index of the echoed ICMP Packet
                let selfID = self?.identifier ?? 0
                guard id == selfID else {
                    // DispatchQueue.global(qos: .background).async {
                    //     Log.ping.debug("Received PingResponse for identifier: \(id ?? 0), sequence: \(sequence ?? 0) but our current session id is: \(selfID)")
                    // }
                    return nil
                }
                guard let sequenceIndex: UInt16 = sequence,
                      let request: PingRequest = self?.pendingRequest(for: Int(sequenceIndex)) else {
                    Log.ping.warning("Could not look up pending request for sequenceIndex: \(String(describing: sequence))")
                    return nil
                }

                let ipHeader: IPHeader? = IPHeader(data: data)
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
            .sink(receiveCompletion: { (_: Subscribers.Completion<Error>) in
                      },
                  receiveValue: { [unowned self] (response: PingResponse) in
                      // Log.ping.trace("Socket sink receiveValue: \(response.sequenceIndex)")
                      informObservers(of: response)
                  })
            .store(in: &cancellables)
    }

    // MARK: - Tear-down

    private func tearDown() {
        // Log.ping.trace(#function)

        pingTimer?.invalidate()
        cancellables.removeAll()

        socket?.tearDown()
        socket = nil

        serialProperty.sync {
            pendingRequests.removeAll()
            timeoutTimers.forEach { _, timer in
                timer.invalidate()
            }
            timeoutTimers.removeAll()

            // Skip clearing notification listeners if we have been stopped because we're in the background.
            #if os(iOS)
            if autoHalted == false {
                notificationCancellables.removeAll()
            }
            #else
            notificationCancellables.removeAll()
            #endif
        }
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
        // Log.ping.trace(#function)
        guard let icmpPackage: Data = try? createICMPPackage(identifier: UInt16(request.identifier),
                                                             sequenceNumber: UInt16(request.sequenceIndex))
        else {
            Log.ping.error("Error creating icmp package!")
            return
        }
        scheduleTimeout(for: request)
        // Log.ping.debug("sendPing: \(String(describing: request))")
        socket?.send(data: icmpPackage)
        requestPassthrough.send(request)
        scheduleNextPing()
    }

    private func sendPing() {
        // Log.ping.trace(#function)
        if killSwitch { return }
        serial.sync { [self] in
            sendPing(request: PingRequest(identifier: identifier,
                                          ipAddress: destination.ip,
                                          sequenceIndex: sequenceIndex,
                                          trueSequenceIndex: trueSequenceIndex))
        }
    }

    internal func informObservers(of response: PingResponse) {
        // Log.ping.trace(#function)
        // Complete the request on the Pinglet serialProperty queue
        completeRequest(for: Int(response.sequenceIndex))
        serialProperty.sync {
            responses.append(response)
        }

        // Then call the completion handlers on the queue set by the API client
        responsePassthrough.send(response)
        currentQueue.async {
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
        // Log.ping.trace(#function)
        if isTargetCountReached() {
            if configuration.haltAfterTarget {
                stopPinging()
            }
            else {
                informFinishedStatus(trueSequenceIndex)
            }
        }
        else if canSchedulePing() {
            let timer = Timer(timeInterval: configuration.pingInterval, repeats: false) { _ in
                self.incrementSequenceIndex()
                self.sendPing()
            }
            pingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
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
        // Log.ping.trace(#function)
        guard isPinging == false else { return }
        isPinging = true

        if socket == nil {
            do { try createSocket() }
            catch {
                // Turn off the isPinging flag if we fail to create a socket
                isPinging = false
                throw error
            }
        }
        guard let socket = socket else {
            throw PingError.socketNil
        }

        let openTimeout = Date().addingTimeInterval(configuration.timeoutInterval)
        while !socket.isOpen, socket.isOpening, Date() < openTimeout {
            RunLoop.current.run(until: Date().advanced(by: 0.1))
        }
        guard socket.isOpen else {
            throw PingError.socketNil
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
        // Log.ping.trace(#function)
        // Handle overflow gracefully
        if sequenceIndex >= UInt16.max { sequenceIndex = 0 }
        else { sequenceIndex += 1 }

        if trueSequenceIndex >= UInt64.max { trueSequenceIndex = 0 }
        else { trueSequenceIndex += 1 }
    }
}
