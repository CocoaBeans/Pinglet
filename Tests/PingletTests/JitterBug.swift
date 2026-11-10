//
// Created by Kevin Ross on 6/12/24.
//

import Foundation
import Pinglet

class JitterBug: NSObject, ObservableObject {

    // Observable Properties
    @Published var isStarted: Bool = false
    @Published var sessionID: UUID = .init()


    private var pinglet: Pinglet?

    // var didSendPublisher: AnyPublisher<IdentifierSequence, Never> {
    //     didSendSubject.receive(on: queue)
    //             .receive(on: DispatchQueue.main)
    //             .eraseToAnyPublisher()
    // }
    // var didReceivePublisher: AnyPublisher<IdentifierSequence, Never> {
    //     didReceiveSubject.receive(on: queue)
    //             .receive(on: DispatchQueue.main)
    //             .eraseToAnyPublisher()
    // }

    private let queue = DispatchQueue(label: "JitterBug Serial")

    // These should be private when we're done testing
    // private var didSendSubject: PassthroughSubject<IdentifierSequence, Never> = .init()
    // private var didReceiveSubject: PassthroughSubject<IdentifierSequence, Never> = .init()

    override init() {
        super.init()
    }

    func start() throws {
        let config = PingConfiguration(interval: 0.1, timeout: 1)
        pinglet = try Pinglet(ipv4Address: "1.1.1.1", config: config, queue: queue)
    }
}
