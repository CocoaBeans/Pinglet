# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Pinglet** is a Swift Package that sends ICMP echo requests (ping) to network hosts. It is based on [SwiftyPing](https://github.com/samiyr/SwiftyPing). The package targets iOS 14+ and macOS 11+.

## Build, Test, and Lint Commands

```bash
# Build
swift build

# Run all tests
swift test

# Run a single test
swift test --filter PingletTests

# Run with logging enabled (requires macOS)
swift test --filter PingletTests/PingletTests.testSimplePing
```

No linter or formatter is configured at the SPM level. The project uses [swiftformat](https://github.com/nicklockwood/SwiftFormat) with the rules in `.swiftformat` (Yodaswap, self-removal, organized types, etc.). Run `swiftformat .` to apply.

## Architecture

The package has three targets:

### `Socket2Me` (low-level networking)
- **`Socket2Me.swift`** — Core `CFSocket` wrapper class. Creates ICMP datagram sockets (optionally in a detached background thread), handles read/write via Combine publishers (`dataReceivedPublisher`, `dataSentPublisher`), and manages the run loop. All low-level socket callbacks flow through here.
- **`Destination.swift`** — Hostname-to-IP resolution via `CFHost`. Wraps `sockaddr_in` addresses.
- **`SocketError.swift`** — Error types for socket-level failures (DNS, connectivity, SIGPIPE).
- **`Data+Networking.swift`** — Extensions to convert `Data` to `sockaddr` / `sockaddr_in`.
- **`SerialPropertyWrapper.swift`** — `@SerialAccess` property wrapper for thread-safe access to Combine subjects.

### `Pinglet` (public API)
- **`Pinglet.swift`** — Main entry point. `public class Pinglet: NSObject, ObservableObject` manages the ping lifecycle (`startPinging`/`stopPinging`), sequence numbering, Timer-based scheduling, and Combine publisher wiring. Supports both closure observers and Combine publishers (`$responses`, `responsePublisher`, `requestPublisher`). iOS-specific: auto-halts on background, `allowBackgroundPinging` toggle.
- **`PingConfiguration.swift`** — Configurable params: interval, timeout, TTL, payload size, halt behavior.
- **`PingResponse.swift`** / `PingRequest.swift` — Request/response data structs implementing `PingID` protocol.
- **`PingResult.swift`** — Aggregate stats (packet loss, roundtrip min/max/avg/stddev) delivered on finish.
- **`PingError.swift`** — Comprehensive error enum covering validation, DNS, checksum, socket, and timeout errors.
- **`ICMP.swift`** — `IPHeader` and `ICMPHeader` structs with raw byte parsing, network↔host byte-swapping, and ICMP checksum computation.
- **`Pinglet+ICMP.swift`** — ICMP echo request package builder (header + payload + checksum).
- **`Pinglet+Networking.swift`** — Response validation (UUID fingerprint, checksum, identifier/sequence matching).
- **`Pinglet+Timeout.swift`** — Per-request timeout scheduling via `Timer` and `invalidateTimer`/`completeRequest` lifecycle.
- **`Pinglet+Log.swift`** — `os.Logger` instance for the "ping" category.

### Key patterns
- **Threading**: `Pinglet` uses `DispatchQueue` serial queues (`serial`, `serialProperty`) for internal state. `@SerialAccess` property wrapper wraps Combine subjects. Network I/O can run on a detached thread (`runInBackground`).
- **Combine pipeline**: `Socket2Me` emits raw `Data` → `Pinglet` pipes it through `tryCompactMap` → parses `ICMPHeader` → validates → emits `PingResponse`.
- **Sequence tracking**: Dual counters — `sequenceIndex` (UInt16, wraps at 65535) and `trueSequenceIndex` (UInt64). Requests stored in `pendingRequests`, timed via `timeoutTimers`.
- **UUID fingerprint**: Each `Pinglet` instance gets a random `UUID` sent as ICMP payload. Incoming responses are filtered by matching fingerprint to avoid cross-session contamination.
- **Multithreaded design**: Ping send and receive are independent. Multiple `startPinging()` calls are guarded by `isPinging` + `killSwitch`.

### Code review notes
- The code uses C-level raw byte manipulation (`withUnsafeBytes`, `load(as:)`) for ICMP/IP headers. Be cautious with struct layout assumptions and endianness (`CFSwapInt16BigToHost` / `CFSwapInt16HostToBig`).
- `PingError` and `SocketError` are parallel error enums. `PingError` is the public-facing one.
- Both `Pinglet` and `Socket2Me` have `deinit → tearDown()` for cleanup, but `tearDown()` also fires from `stopPinging()`/`Socket2Me.tearDown()` for early teardown.
- The `SerialAccess` wrapper uses `barrier` + `assignCurrentContext` for Combine subject writes.

## Testing
- `PingletTests.swift` — Integration-style tests hitting real hosts (1.1.1.1, 8.8.8.8). Uses `RunLoop` spinning and `XCTestExpectation` for async.
- `Socket2MeTests.swift` — Socket lifecycle test (create/destroy in a loop).
- `JitterBug.swift` — Debug/prototyping class, not a test.
