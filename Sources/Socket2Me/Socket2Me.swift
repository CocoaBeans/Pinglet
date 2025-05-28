/*
  Socket2Me
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

/// Class representing socket info, which contains a `Socket2Me` instance and an identifier.
public class SocketInfo {
    public weak var socket2Me: Socket2Me?
    public let identifier: String

    public init(socket2Me: Socket2Me, identifier: String) {
        self.socket2Me = socket2Me
        self.identifier = identifier
    }
}

public class Socket2Me: NSObject, ObservableObject {
    public var destination: Destination
    public var timeout: TimeInterval = 30

    public var dataReceivedPublisher: AnyPublisher<Data, SocketError> { dataReceivedSubject.eraseToAnyPublisher() }
    public var dataSentPublisher: AnyPublisher<Data, SocketError> { dataSentSubject.eraseToAnyPublisher() }

    /// Sets the TTL flag on the socket. All requests sent from the socket will include the TTL field set to this value.
    public var timeToLive: Int?

    /// Flag to enable socket processing on a background thread
    public var runInBackground: Bool = true

    /// Detached run loop for handling socket communication off of the main thread
    public var runLoop: CFRunLoop?
    /// Socket for sending and receiving data.
    private var socket: CFSocket?
    /// Socket source
    private var socketSource: CFRunLoopSource?
    /// An unmanaged instance of `SocketInfo` used in the current socket's callback. This must be released manually, otherwise it will leak.
    private var unmanagedSocketInfo: Unmanaged<SocketInfo>?
    private var killSwitch: Bool = false

    private let queue = DispatchQueue(label: "Socket2Me internal utility", qos: .utility)

    private var detachedThread: Thread?

    @SerialAccess(defaultValue: PassthroughSubject<Data, SocketError>())
    private var dataReceivedSubject

    @SerialAccess(defaultValue: PassthroughSubject<Data, SocketError>())
    private var dataSentSubject

    public init(destination: Destination) {
        self.destination = destination
        super.init()
        try? createSocket()
    }

    @objc
    private func createSocketDetached() {
        detachedThread = Thread.current
        detachedThread?.qualityOfService = .utility

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let formatted: String = formatter.string(from: Date())

        detachedThread?.name = "Pinglet @ \(formatted)"
        try? _openNetworkSocket()
    }

    /// Initializes a CFSocket.
    /// - Throws: If setting a socket options flag fails, throws a `PingError.socketOptionsSetError(:)`.
    private func createSocket() throws {
        if runInBackground {
            Thread.detachNewThreadSelector(#selector(createSocketDetached), toTarget: self, with: nil)
        }
        else {
            try queue.sync {
                try _openNetworkSocket()
            }
        }
    }

    private func _openNetworkSocket() throws {
        // Create a socket context...
        let info = SocketInfo(socket2Me: self, identifier: UUID().uuidString)
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
                                { (socket: CFSocket?, type: CFSocketCallBackType, address: CFData?, data: UnsafeRawPointer?, info: UnsafeMutableRawPointer?) in
                                    guard let address = address as? Data else { return }

                                    // Socket callback closure
                                    guard let socket: CFSocket = socket,
                                          let info: UnsafeMutableRawPointer = info,
                                          let data: UnsafeRawPointer = data
                                    else { return }

                                    let socketInfo: SocketInfo = Unmanaged<SocketInfo>.fromOpaque(info).takeUnretainedValue()
                                    if (type as CFSocketCallBackType) == CFSocketCallBackType.dataCallBack,
                                       let socket2Me: Socket2Me = socketInfo.socket2Me,
                                       socket == socket2Me.socket,
                                       address == socket2Me.destination.ipv4Address {
                                        let cfdata: CFData = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue()
                                        socket2Me.socket(socket, didReadData: CFDataCreateCopy(.none, cfdata) as Data)
                                    }
                                },
                                &context)

        // Disable SIGPIPE, see issue #15 on GitHub.
        let handle: CFSocketNativeHandle = CFSocketGetNative(socket)
        var value: Int32 = 1
        let err = setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout.size(ofValue: value)))
        guard err == 0
        else {
            try emitSocketError(code: err)
            return
        }

        // Set TTL
        if var ttl = timeToLive {
            let err = setsockopt(handle, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout.size(ofValue: ttl)))
            guard err == 0
            else {
                try emitSocketError(code: err)
                return
            }
        }

        // ...and add it to the current run loop.
        socketSource = CFSocketCreateRunLoopSource(nil, socket, 0)
        if let runLoop: CFRunLoop = CFRunLoopGetCurrent(),
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

    private func emitSocketError(code: Int32) throws {
        let error = SocketError.socketOptionsSetError(errorCode: code)
        try emitSocketError(error: error)
    }

    private func emitSocketError(error: SocketError) throws {
        dataReceivedSubject.send(completion: .failure(error))
        throw error
    }

    // MARK: - Tear-down
    public func tearDown() {
        killSwitch = true

        if let socketSource = socketSource {
            CFRunLoopSourceInvalidate(socketSource)
            self.socketSource = nil
        }

        if let socket = socket {
            // If a run loop source was created for socket, the run loop source is invalidated.
            CFSocketInvalidate(socket)
            self.socket = nil
        }

        unmanagedSocketInfo?.release()
        unmanagedSocketInfo = nil

        if let runLoop = runLoop {
            CFRunLoopStop(runLoop)
            self.runLoop = nil
        }
        detachedThread?.cancel()
    }

    deinit {
        tearDown()
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: - Read Socket Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

extension Socket2Me {
    func socket(_ socket: CFSocket, didReadData data: Data?) {
        guard let data: Data = data,
              self.socket == socket
        else { return }
        dataReceivedSubject.send(data)
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: - Write Socket Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public extension Socket2Me {
    func send(data: Data) {
        queue.async {
            do {
                let address: Data = self.destination.ipv4Address

                // Make sure our socket is valid before trying to send data to it
                guard self.killSwitch == false,
                      let socket: CFSocket = self.socket,
                      CFSocketIsValid(socket),
                      let socketSource: CFRunLoopSource = self.socketSource,
                      CFRunLoopSourceIsValid(socketSource)
                else { return }

                let socketError: CFSocketError = CFSocketSendData(socket,
                                                                  address as CFData,
                                                                  data as CFData,
                                                                  self.timeout)
                if socketError != .success {
                    var error: SocketError?

                    switch socketError {
                    case .error: error = .requestError
                    case .timeout: error = .requestTimeout
                    default: break
                    }
                    if let error: SocketError = error {
                        throw error
                    }
                }
                else {
                    self.dataSentSubject.send(data)
                }
            }
            catch {
                if let err = error as? SocketError {
                    if err != SocketError.requestError && err != .requestTimeout {
                        self.dataSentSubject.send(completion: .failure(err))
                        self.dataReceivedSubject.send(completion: .failure(err))
                    }
                }
                else {
                    self.dataSentSubject.send(completion: .failure(.dataTransmissionFailed))
                    self.dataReceivedSubject.send(completion: .failure(.dataTransmissionFailed))
                }
            }
        }
    }
}
