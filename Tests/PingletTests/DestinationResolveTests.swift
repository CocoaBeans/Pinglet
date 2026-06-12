/*
  Pinglet
  This project is based on SwiftyPing: https://github.com/samiyr/SwiftyPing
  Copyright (c) 2023 Kevin Ross

  Tests for the asynchronous host-resolution API (`Destination.resolve(host:)`
  and the `async` initializers) introduced to replace the blocking
  `CFHostStartInfoResolution` path.
 */

import Foundation
import Testing
@testable import Pinglet
@testable import Socket2Me

@Suite("Async host resolution")
struct DestinationResolveTests {
    /// A literal IPv4 address resolves without any DNS network round-trip, so these
    /// happy-path cases are deterministic and offline-safe.
    private static let loopbackAddress = "127.0.0.1"
    private static let publicResolver = "1.1.1.1"

    @Test("resolve(host:) returns the IPv4 sockaddr bytes for a literal address")
    func resolveLiteralIPv4() async throws {
        let data = try await Destination.resolve(host: Self.publicResolver)
        let destination = Destination(host: Self.publicResolver, ipv4Address: data)
        #expect(destination.ip == Self.publicResolver)
    }

    @Test("async init(host:) produces a usable destination without blocking the caller")
    func asyncDestinationInit() async throws {
        let destination = try await Destination(host: Self.loopbackAddress)
        #expect(destination.host == Self.loopbackAddress)
        #expect(destination.ip == Self.loopbackAddress)
    }

    @Test("async Pinglet(host:) builds its destination via async resolution")
    func asyncPingletInit() async throws {
        let pinglet = try await Pinglet(host: Self.publicResolver)
        #expect(pinglet.destination.ip == Self.publicResolver)
    }

    @Test("resolve(host:) throws for an unresolvable host")
    func resolveInvalidHostThrows() async {
        await #expect(throws: (any Error).self) {
            _ = try await Destination.resolve(host: "thishostdoesnotexistzzz.example.com")
        }
    }
}
