//
// Created by Kevin Ross on 4/23/23.
//

import Foundation

// MARK: - Data Extensions
public extension Data {
    /// Expresses a chunk of data as a socket address.
    var socketAddress: sockaddr {
        withUnsafeBytes { $0.load(as: sockaddr.self) }
    }
    /// Expresses a chunk of data as an internet-style socket address.
    var socketAddressInternet: sockaddr_in {
        withUnsafeBytes { $0.load(as: sockaddr_in.self) }
    }
}
