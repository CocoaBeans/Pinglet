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

import Foundation

extension Pinglet {
    internal func completeRequest(for sequenceID: Int) {
        // Log.ping.debug("completeRequest(for: \(sequenceID))")
        invalidateTimer(sequenceID: sequenceID)
        serialProperty.async {
            self.pendingRequests.removeAll { (request: PingRequest) in request.sequenceIndex == sequenceID }
        }
    }

    internal func pendingRequest(for sequenceID: Int) -> PingRequest? {
        serialProperty.sync {
            pendingRequests.first { (request: PingRequest) in request.sequenceIndex == sequenceID }
        }
    }

    internal func invalidateTimer(sequenceID: Int) {
        serialProperty.async { [self] in
            guard let timer: Timer = timeoutTimers[sequenceID] else { return }
            // Log.ping.debug("invalidateTimer(sequenceID: \(sequenceID))")
            timer.invalidate()
            timeoutTimers.removeValue(forKey: sequenceID)
        }
    }

    internal func informObserversOfTimeout(for request: PingRequest) {
        // Log.ping.trace(#function)
        let response = PingResponse(identifier: request.identifier,
                                    ipAddress: request.ipAddress,
                                    sequenceIndex: request.sequenceIndex,
                                    trueSequenceIndex: request.trueSequenceIndex,
                                    duration: -1,
                                    error: PingError.responseTimeout,
                                    byteCount: nil,
                                    ipHeader: nil)
        erroredIndices.append(Int(request.sequenceIndex))
        informObservers(of: response)
    }

    internal func scheduleTimeout(for request: PingRequest) {
        serialProperty.async { [self] in
            // Log.ping.debug("scheduleTimeout(sequenceID: \(request.sequenceIndex))")
            let timer = Timer(timeInterval: configuration.timeoutInterval, repeats: false) { [weak self] (timer: Timer) in
                Log.ping.notice("Time-out for request: \(request.sequenceIndex)")
                self?.informObserversOfTimeout(for: request)
            }

            // If we have an internal socket run loop then we will add the timer to that run loop.
            if let cfRunLoop = socket?.runLoop {
                CFRunLoopAddTimer(cfRunLoop, timer, .commonModes)
            }
            else {
                RunLoop.main.add(timer, forMode: .common)
            }

            pendingRequests.append(request)
            timeoutTimers[request.sequenceIndex] = timer
        }
    }
}
