# Foundation verification

Date: 2026-08-29 (Asia/Tokyo)

## Result

- Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`
- Swift: Apple Swift 6.3.3
- Result: PASS, 24 tests, 0 failures
- Duration reported by XCTest: 0.489 seconds after build
- Real container mutations: none

## Covered boundaries

- Fixed `127.0.0.1` binding and validated port configuration
- 64 KiB request and 16 MiB combined command-output limits
- Concurrent stdout/stderr draining, timeout, cancellation and invalid UTF-8 preservation
- Explicit/PATH CLI resolution and 1.3.x compatibility classification
- Stable Chinese problem envelopes and recursive secret redaction
- Idempotency replay/conflict, per-target lock, four-process cap, legal transitions and mandatory readback
- Same-origin JSON mutation checks, no CORS, CSP, frame and content-sniffing headers

## Local toolchain note

`xcode-select -p` currently points to `/Library/Developer/CommandLineTools`. That minimal toolchain does not
contain XCTest/Testing frameworks, so bare `swift test` cannot compile the test target. The installed full Xcode
contains the same Swift 6.3.3 compiler plus XCTest and is used explicitly above.
