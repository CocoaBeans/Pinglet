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
    func createSocket() throws -> Socket2Me {
        let socket = Socket2Me(destination: try Destination(host: "1.1.1.1"))
        XCTAssertNotNil(socket)

        let openTimeout = Date().addingTimeInterval(5)
        while socket.isOpening, Date() < openTimeout {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(socket.isOpen)

        return socket
    }
    
    func testThreadExit() throws {
        var socket: Socket2Me? = .none
        for _ in 0...10 {
            socket = try createSocket()
            XCTAssertNotNil(socket)
            socket = nil
        }
    }
}
