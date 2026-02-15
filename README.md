# JustPlayNative

JustPlayNative is a macOS SwiftUI video player app generated from an XcodeGen spec.

## Requirements

- macOS 13+
- Xcode 15+
- Homebrew (recommended for installing CLI tools)
- `xcodegen`
- `carthage`

Install tooling:

```bash
brew install xcodegen carthage
```

## Quick Start

1. Fetch dependencies and generate the Xcode project:

   ```bash
   make setup
   ```

2. Build from CLI:

   ```bash
   make build
   ```

3. Build and launch:

   ```bash
   make run
   ```

You can run `make help` to see all available targets.

## Notes

- `Carthage/` is intentionally not committed; every fresh clone should run `make bootstrap` first.
- If Xcode/CoreSimulator version mismatch appears, run:

  ```bash
  xcrun simctl list devices
  ```

## License

- This repository is licensed under MIT (`LICENSE`).
- Third-party dependency notices are listed in `THIRD_PARTY_NOTICES.md`.
