# Pinglet — AGENTS.md

Compact companion to `CLAUDE.md`. Only facts that are not obvious from the codebase or `CLAUDE.md`.

## Commands

| What | How |
|---|---|
| Build | `swift build` |
| All tests | `swift test` |
| Single test | `swift test --filter PingletTests` |
| With os_log output | `swift test --filter PingletTests/PingletTests.testSimplePing` |
| Format | `swiftformat .` |

No CI, no pre-commit hooks, no codegen.

## Dependencies

**Zero external dependencies.** No package resolution overhead, no SPM plugin issues. The two library targets (`Socket2Me` → `Pinglet`) are both internal to this package.

## Architecture key points (beyond CLAUDE.md)

- `Socket2Me` is a private implementation detail. All public API lives in the `Pinglet` target.
- The Combine pipeline: `Socket2Me` emits raw `Data` → `Pinglet` parses `ICMPHeader` → validates → emits `PingResponse`.
- `JitterBug.swift` in Tests/ is a **debug/prototyping class**, not a test. Do not treat it as a test suite.

## Raw byte manipulation

The code uses `withUnsafeBytes` / `load(as:)` to cast raw bytes into `IPHeader` and `ICMPHeader` structs. Always use `CFSwapInt16BigToHost` / `CFSwapInt16HostToBig` for network↔host byte order. Struct layout assumptions can crash at runtime.

## Conventions that differ from defaults

- `swiftformat` rules require **no `self.`** (except where required by the language), **Yodaswap** style, and **organized types** (actor/class/enum/struct grouped). Write code that passes `swiftformat .` without changes.
- `Pinglet` is `public class Pinglet: NSObject, ObservableObject`. It uses `DispatchQueue` serial queues for internal state and `@SerialAccess` property wrapper for thread-safe Combine subjects.
- `PingError` (public) and `SocketError` (internal) are parallel error enums covering overlapping domains.

## Tests

- Integration tests hit **real hosts** (1.1.1.1, 8.8.8.8). No mocking, no fixtures. Requires network connectivity.
- Async pattern: `RunLoop` spinning + `XCTestExpectation`. Not Swift Concurrency.
- `Socket2MeTests.swift` is just a create/destroy lifecycle loop.
