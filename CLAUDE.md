# JustPlay

macOS SwiftUI app generated from an XcodeGen spec.

## Commands

| Command | Description |
| --- | --- |
| `make setup` | Bootstrap Carthage deps and generate the Xcode project (`bootstrap + generate`). |
| `make build` | Build the app for Apple Silicon macOS. |
| `make run` | Build with derived data and open `JustPlay.app`. |
| `make install` | Build, copy `JustPlay.app` to `/Applications`, and open it. |
| `make install APPLICATIONS_DIR=~/Applications` | Install to user-local Applications directory. |
| `make help` | Show all available Makefile targets. |
| `xcodegen dump --type summary` | Validate the resolved XcodeGen spec and target summary. |
| `xcodegen generate --use-cache` | Regenerate `JustPlay.xcodeproj` and plist outputs from `project.yml`. |
| `xcodebuild -project JustPlay.xcodeproj -scheme JustPlay -destination 'platform=macOS,arch=arm64' build` | Build the app from CLI for Apple Silicon macOS. |
| `xcodebuild -project JustPlay.xcodeproj -scheme JustPlay -destination 'platform=macOS,arch=arm64' -derivedDataPath ./.derivedData build && open "./.derivedData/Build/Products/Debug/JustPlay.app"` | Build and launch from CLI. |
| `xcrun simctl list devices` | Refresh CoreSimulator service state if Xcode/CoreSimulator mismatch errors appear. |

## Architecture

```text
project.yml                # Source-of-truth XcodeGen spec
JustPlay.xcodeproj/  # Generated project; regenerate instead of manual edits
Sources/
  JustPlayApp.swift        # @main app entry
  ContentView.swift        # Main window UI
  Info.plist               # Generated/synced from project.yml info properties
```

## Workflow

1. On a fresh clone, run `make setup` to bootstrap Carthage and regenerate the project.
2. Edit `project.yml` for target, build setting, bundle, or plist changes.
3. Build via `make build` (or raw `xcodebuild` using `-destination 'platform=macOS,arch=arm64'`).
4. Launch via `make run` from `.derivedData/Build/Products/Debug/JustPlay.app`, or use `make install` for install flow.

## Gotchas

- `xcodebuild` may print `[MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.` while still producing a successful build.
- On Apple Silicon, `xcodebuild -destination 'platform=macOS'` can warn about multiple matching destinations; use `platform=macOS,arch=arm64` for deterministic CLI builds.
- The target `PRODUCT_NAME` is `JustPlay`, so the built app bundle path ends in `JustPlay.app`.
- If you see CoreSimulator version mismatch errors during build startup, run `xcrun simctl list devices` once to let CoreSimulator refresh stale service state, then retry.
