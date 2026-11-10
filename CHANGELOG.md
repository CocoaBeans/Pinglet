# Changelog

All notable changes to **Pinglet** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — Unreleased

This release modernizes host resolution with Swift Concurrency, hardens the
ICMP/IP receive path, and tidies the public API. It contains **breaking
changes** — see below before upgrading.

### ⚠️ Breaking Changes

- **`Pinglet.delegate` is now a `weak` reference.** Pinglet no longer retains
  its delegate, so you must hold a strong reference to the delegate yourself.
  Code like `pinglet.delegate = SomeDelegate()` (with no other strong reference)
  will now deallocate the delegate immediately. This is the only break that
  fails **silently** rather than at compile time — audit your delegate
  ownership when upgrading.
- **`PingDelegate` now requires `AnyObject`** (class-bound). Value-type
  conformers are no longer allowed. Required to support the weak `delegate`
  reference above.
- **`SocketInfo` moved and changed.** It now lives in the `Socket2Me` module and
  its initializer changed from `init(pinglet: Pinglet, identifier: UInt16)` to
  `init(socket2Me: Socket2Me, identifier: String)`. This is an internal
  callback-context helper; direct use was never expected.
- **`IPHeader` stored properties are now `let` instead of `var`.** All parsed
  header fields (`totalLength`, `timeToLive`, `protocol`, `sourceAddress`, …)
  are read-only. Breaks code that mutated a parsed header.
- **Removed the retroactive `extension String: LocalizedError`.** If you relied
  on `String` conforming to `LocalizedError` (a global conformance Pinglet
  previously added), that is gone.

### Added

- **Asynchronous DNS resolution** using modern Swift Concurrency:
  - `Destination.resolve(host:) async throws -> Data`
  - `Destination.init(host:) async throws`
  - `Pinglet.init(host:configuration:queue:) async throws`

  Resolution runs on a dedicated `DispatchQueue` via a checked continuation, so
  it never blocks the caller or a cooperative concurrency thread.
- **`Destination.init(ipv4String:) throws`** — builds a destination from a
  literal IPv4 address with no DNS. Validates input via `inet_pton` and throws
  `SocketError.addressLookupError` on malformed input (instead of silently
  yielding a garbage address).
- Expanded public `ICMPHeader` / `IPHeader` API: `type`, `code`, `identifier`,
  `sequenceNumber`, `payload`, `checksum`, the `identifierToHost` /
  `sequenceNumberToHost` accessors, and the `headerSize` / `payloadSize` /
  `totalSize` / `minSize` size constants.
- Comprehensive `Pinglet` and `Socket2Me` unit test suites, plus Swift Testing
  coverage for the async resolution and `ipv4String` validation paths.
- Swift 6 language-mode compatibility fixes.

### Changed

- ICMP and IP headers are now parsed with **safe manual byte parsing** instead
  of unsafe pointer loads (`withUnsafeBytes` / `load(as:)`), removing struct
  memory-layout and padding assumptions.
- `Pinglet.init(ipv4Address:)` now delegates to `Destination.init(ipv4String:)`,
  removing duplicated `sockaddr_in` construction. Its public signature is
  unchanged.

### Deprecated

The synchronous, **blocking** host-resolution APIs are deprecated in favor of
the async equivalents above. They still work but emit deprecation warnings:

- `Destination.getIPv4AddressFromHost(host:)` → use `Destination.resolve(host:)`
- `Destination.init(host:) throws` → use `Destination.init(host:) async throws`
- `Pinglet.init(host:configuration:queue:) throws` → use the `async` overload

### Fixed

- ICMP receive-path bugs: out-of-bounds IP header reads, incorrect header
  offset when parsing the ICMP header, and unsafe slice indexing. Regression
  guards added.
- ICMP/IP header **byte-order** handling on Darwin raw sockets: `ip_len` /
  `ip_off` are decoded in host order while `ip_id` / `ip_sum` remain network
  order, matching the raw-socket convention.
- Flaky `testStopViaTimer` caused by a dual-timer race condition.

[2.0.0]: https://github.com/CocoaBeans/Pinglet/compare/v1.0.8...v2.0.0
