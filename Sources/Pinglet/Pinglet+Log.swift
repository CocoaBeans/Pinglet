//
// Created by Kevin Ross on 9/6/23.
//

import Foundation
import os

struct Log {
    private static var subsystem: String = Bundle.main.bundleIdentifier!
    static let ping: Logger = .init(subsystem: subsystem, category: "ping")
}
