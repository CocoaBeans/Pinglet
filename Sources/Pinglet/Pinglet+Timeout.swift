//
// Created by Kevin Ross on 4/24/23.
//

import Foundation

extension Pinglet {
    internal func completeRequest(for sequenceID: Int) {
        invalidateTimer(sequenceID: sequenceID)
        pendingRequests.removeAll { request in request.sequenceIndex == sequenceID }
    }

    internal func pendingRequest(for sequenceID: Int) -> PingRequest? {
        pendingRequests.first { (request: PingRequest) in request.sequenceIndex == sequenceID }
    }

    internal func invalidateTimer(sequenceID: Int) {
        guard let timer: Timer = timeoutTimers[sequenceID] else { return }
        timer.invalidate()
        timeoutTimers.removeValue(forKey: sequenceID)
    }

    internal func scheduleTimeout(for request: PingRequest) {
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
        timeoutTimers[request.id] = timer
        pendingRequests.append(request)
    }
}
