# ALR Test Rig (Step 1 Scaffold)

- App: `TestRig` (macOS 13+, SwiftUI)
- Local Swift Package: `ALRPackages` with `CoreTypes` and `Analyzers`
- Offline-only, no 3rd-party runtime deps.

## Build & Run
- Open `TestRig.xcworkspace`
- Run the `TestRig` scheme (macOS)

## Tests
- `⌘U` in Xcode
- Or CLI: `xcodebuild -scheme TestRig -destination 'platform=macOS' test`

## Lint & Format
- `swiftformat .`
- `swiftlint`

## Coverage
- `Scripts/coverage_guard.sh`

## Logging & Timeouts
- The Coordinator logs run start/end and per-analyzer durations via `os.Logger` (subsystem `com.yourorg.testrig`, category `rig.run`).
- Per-analyzer timeout default is 3s; configurable via `runAll(timeoutPerAnalyzer:)`.
- Analyzer errors appear inline as `❌` rows; timeouts as `⏱️ Timed out`.
- A top-of-window banner (`lastError`) is available for rig-level issues (e.g., file I/O), currently not triggered by analyzers.