//
//  Pinglet.swift
//  Pinglet
//
//  Created by Kevin Ross on 04/23/23.
//  Copyright © 2023 Kevin Ross. All rights reserved.
//

import Combine
import Darwin
import Foundation

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

// MARK: SwiftyPing

/// Class representing socket info, which contains a `SwiftyPing` instance and the identifier.
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
    public var responsePublisher: AnyPublisher<PingResponse, Never> { responsePassthrough.eraseToAnyPublisher() }
    private var responsePassthrough = PassthroughSubject<PingResponse, Never>()

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
    private let currentQueue: DispatchQueue

    /// Detached run loop for handling socket communication off of the main thread
    private var runLoop: CFRunLoop?

    /// Socket for sending and receiving data.
    private var socket: CFSocket?
    /// Socket source
    private var socketSource: CFRunLoopSource?
    /// An unmanaged instance of `SocketInfo` used in the current socket's callback. This must be released manually, otherwise it will leak.
    private var unmanagedSocketInfo: Unmanaged<SocketInfo>?

    /// When the current request was sent.
    // private var sequenceStart = Date()
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

    internal var subscriptions = Set<AnyCancellable>()
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
            .sink { (_: Notification) in
                if allowBackgroundPinging { return }
                autoHalted = true
                haltPinging(resetSequence: false)
            }
            .store(in: &subscriptions)
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { (_: Notification) in
                if autoHalted {
                    autoHalted = false
                    try? startPinging()
                }
            }
            .store(in: &subscriptions)
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

    private func _createSocket() throws {
        // Create a socket context...
        let info = SocketInfo(pinglet: self, identifier: identifier)
        unmanagedSocketInfo = Unmanaged.passRetained(info)
        var context = CFSocketContext(version: 0,
                                      info: unmanagedSocketInfo!.toOpaque(),
                                      retain: nil,
                                      release: nil,
                                      copyDescription: nil)

        // ...and a socket...
        socket = CFSocketCreate(kCFAllocatorDefault,
                                AF_INET,
                                SOCK_DGRAM,
                                IPPROTO_ICMP,
                                CFSocketCallBackType.dataCallBack.rawValue,
                                { socket, type, _, data, info in
                                    // Socket callback closure
                                    guard let socket: CFSocket = socket, let info: UnsafeMutableRawPointer = info, let data: UnsafeRawPointer = data
                                    else { return }
                                    let socketInfo = Unmanaged<SocketInfo>.fromOpaque(info).takeUnretainedValue()

                                    if (type as CFSocketCallBackType) == CFSocketCallBackType.dataCallBack,
                                       let pinglet: Pinglet = socketInfo.pinglet {
                                        let cfdata: CFData = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue()
                                        pinglet.socket(socket, didReadData: cfdata as Data)
                                    }
                                },
                                &context)

        // Disable SIGPIPE, see issue #15 on GitHub.
        let handle: CFSocketNativeHandle = CFSocketGetNative(socket)
        var value: Int32 = 1
        let err = setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout.size(ofValue: value)))
        guard err == 0
        else {
            throw PingError.socketOptionsSetError(err: err)
        }

        // Set TTL
        if var ttl = configuration.timeToLive {
            let err = setsockopt(handle, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout.size(ofValue: ttl)))
            guard err == 0
            else {
                throw PingError.socketOptionsSetError(err: err)
            }
        }

        // ...and add it to the current run loop.
        socketSource = CFSocketCreateRunLoopSource(nil, socket, 0)
        if let runLoop = CFRunLoopGetCurrent(),
           runLoop != CFRunLoopGetMain() {
            self.runLoop = runLoop
            CFRunLoopAddSource(runLoop, socketSource, .commonModes)
            // If we are not on the main run loop we have to run the loop to schedule timers and network sockets
            CFRunLoopRun()
        }
        else {
            CFRunLoopAddSource(CFRunLoopGetMain(), socketSource, .commonModes)
        }
    }

    @objc
    private func createSocketDetached() {
        try? _createSocket()
    }

    /// Initializes a CFSocket.
    /// - Throws: If setting a socket options flag fails, throws a `PingError.socketOptionsSetError(:)`.
    private func createSocket() throws {
        if runInBackground {
            Thread.detachNewThreadSelector(#selector(createSocketDetached), toTarget: self, with: nil)
        }
        else {
            try serial.sync {
                try _createSocket()
            }
        }
    }

    // MARK: - Tear-down

    private func tearDown() {
        if socketSource != nil {
            CFRunLoopSourceInvalidate(socketSource)
            socketSource = nil
        }
        if socket != nil {
            CFSocketInvalidate(socket)
            socket = nil
        }
        if runLoop != nil {
            CFRunLoopStop(runLoop)
            runLoop = nil
        }
        unmanagedSocketInfo?.release()
        unmanagedSocketInfo = nil
        pendingRequests.removeAll()
        timeoutTimers.forEach { key, timer in
            timer.invalidate()
        }
        timeoutTimers.removeAll()
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
        serial.async {
            self.scheduleTimeout(for: request)

            do {
                let address = self.destination.ipv4Address
                let icmpPackage: Data = try self.createICMPPackage(identifier: UInt16(request.identifier),
                                                                   sequenceNumber: UInt16(request.sequenceIndex))

                guard let socket: CFSocket = self.socket else { return }
                let socketError: CFSocketError = CFSocketSendData(socket,
                                                                  address as CFData,
                                                                  icmpPackage as CFData,
                                                                  self.configuration.timeoutInterval)

                self.delegate?.didSend(identifier: request.identifier, sequenceIndex: Int(request.trueSequenceIndex))
                self.requestObserver?(request.identifier, Int(request.trueSequenceIndex))

                if socketError != .success {
                    var error: PingError?

                    switch socketError {
                    case .error: error = .requestError
                    case .timeout: error = .requestTimeout
                    default: break
                    }
                    let response = PingResponse(request: request,
                                                error: error,
                                                byteCount: nil,
                                                ipHeader: nil)

                    self.erroredIndices.append(Int(request.sequenceIndex))
                    self.informObserver(of: response)
                }
            }
            catch {
                let pingError: PingError
                if let err = error as? PingError {
                    pingError = err
                }
                else {
                    pingError = .packageCreationFailed
                }
                let response = PingResponse(request: request,
                                            error: pingError,
                                            byteCount: nil,
                                            ipHeader: nil)
                self.erroredIndices.append(Int(request.sequenceIndex))
                // self.isPinging = false
                self.informObserver(of: response)
            }
        }

        scheduleNextPing()
    }

    private func sendPing() {
        if killSwitch { return }
        sendPing(request: PingRequest(identifier: identifier,
                                      ipAddress: destination.ip,
                                      sequenceIndex: sequenceIndex,
                                      trueSequenceIndex: trueSequenceIndex))
    }

    internal func informObserver(of response: PingResponse) {
        responses.append(response)
        responsePassthrough.send(response)

        currentQueue.sync {
            responseObserver?(response)
            delegate?.didReceive(response: response)
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
                haltPinging()
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

    private let serial = DispatchQueue(label: "SwiftyPing internal", qos: .utility)
    private let serialProperty = DispatchQueue(label: "SwiftyPing internal property", qos: .utility)

    private var _killSwitch = false
    internal var killSwitch: Bool {
        get {
            serialProperty.sync { _killSwitch }
        }
        set {
            serialProperty.sync { _killSwitch = newValue }
        }
    }

    /// Start pinging the host.
    public func startPinging() throws {
        if socket == nil {
            try createSocket()
        }
        killSwitch = false
        isPinging = true
        sendPing()
    }

    /// Stop pinging the host.
    /// - Parameter resetSequence: Controls whether the sequence index should be set back to zero.
    public func stopPinging(resetSequence: Bool = true) {
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

    /// Stops pinging the host and destroys the CFSocket object.
    /// - Parameter resetSequence: Controls whether the sequence index should be set back to zero.
    public func haltPinging(resetSequence: Bool = true) {
        stopPinging(resetSequence: resetSequence)
        tearDown()
    }

    private func incrementSequenceIndex() {
        // Handle overflow gracefully
        if sequenceIndex >= UInt16.max {
            sequenceIndex = 0
        }
        else {
            sequenceIndex += 1
        }

        if trueSequenceIndex >= UInt64.max {
            trueSequenceIndex = 0
        }
        else {
            trueSequenceIndex += 1
        }
    }
}
