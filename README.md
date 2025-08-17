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