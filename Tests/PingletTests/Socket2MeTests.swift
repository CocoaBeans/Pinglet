//
//  File.swift
//  
//
//  Created by Kevin Ross on 7/1/25.
//

import Combine
@testable import Socket2Me
import XCTest

final class Socket2MeTests: XCTestCase {
    func createSocket() -> Socket2Me {
        let socket = Socket2Me(destination: try! Destination(host: "1.1.1.1"))
        XCTAssertNotNil(socket)

        while socket.isOpening {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(socket.isOpen)

        return socket
    }
    
    func testThreadExit() {
        var socket: Socket2Me? = .none
        for _ in 0...10 {
            socket = createSocket()
            XCTAssertNotNil(socket)
            socket = nil
        }
    }
}
