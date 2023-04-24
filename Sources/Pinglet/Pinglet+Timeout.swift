//
// Created by Kevin Ross on 4/24/23.
//

import Foundation

extension Pinglet {
    internal func completeRequest(for sequenceID: Int) {
        // print("completeRequest(for: \(sequenceID))")
        invalidateTimer(sequenceID: sequenceID)
        pendingRequests.removeAll { request in request.sequenceIndex == sequenceID }
    }

    internal func pendingRequest(for sequenceID: Int) -> PingRequest? {
        serialProperty.sync {
            return pendingRequests.first { (request: PingRequest) in request.sequenceIndex == sequenceID }
        }
    }

    internal func invalidateTimer(sequenceID: Int) {
        // print("invalidateTimer(sequenceID: \(sequenceID))")
        serialProperty.sync {
            guard let timer: Timer = timeoutTimers[sequenceID] else { return }
            timer.invalidate()
            timeoutTimers.removeValue(forKey: sequenceID)
        }
    }

    internal func scheduleTimeout(for request: PingRequest) {
        // print("scheduleTimeout(for: \(request.sequenceIndex))")
        pendingRequests.append(request)
        let timer = Timer(timeInterval: configuration.timeoutInterval, repeats: false) { [unowned self] (timer: Timer) in
            let response = PingResponse(identifier: request.identifier,
                                        ipAddress: request.ipAddress,
                                        sequenceIndex: request.sequenceIndex,
                                        trueSequenceIndex: request.trueSequenceIndex,
                                        duration: -1,
                                        error: PingError.responseTimeout,
                                        byteCount: nil,
                                        ipHeader: nil)
            erroredIndices.append(Int(request.sequenceIndex))
            informObserver(of: response)
        }
        RunLoop.current.add(timer, forMode: .common)
        serialProperty.sync {
            timeoutTimers[request.id] = timer
        }
    }
}
