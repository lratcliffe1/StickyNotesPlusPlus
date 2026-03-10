# Contributing

Thanks for your interest in contributing.

## Setup

1. Open `StickyNote++.xcodeproj`.
2. Use the `StickyNote++` scheme.
3. Select an iOS Simulator (not a physical device for test runs).
4. Build and run.

## Tests

- Xcode: `Cmd+U`
- CLI:

```bash
xcodebuild -project "StickyNote++.xcodeproj" -scheme "StickyNote++" -destination "platform=iOS Simulator,name=iPhone 15" test
```

## Quality Checks

- SwiftFormat: `swiftformat . --lint`
- SwiftLint: `swiftlint`

## Pull Requests

- Keep PRs focused and small.
- Add or update tests for behavioral changes.
- Update `README.md` when architecture/setup/workflow changes.
