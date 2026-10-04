# Otto

A to-do list, notes and meeting companion that lives in the MacBook notch.

## Requirements

- macOS 13.0 or later
- For development: Xcode 26+

## Installation

Download the latest `Otto.dmg` from [Releases](../../releases), open it and drag
`Otto.app` into **Applications**. Builds are signed with a Developer ID and
notarized, and Otto updates itself through Sparkle.

## Build from source

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig   # optional settings
open Otto.xcodeproj
# or
xcodebuild -project Otto.xcodeproj -scheme Otto -configuration Debug build
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — how the code is organised
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — product principles, platform traps, decision log
- [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) — signing, notarization, releases, Sparkle
- [`docs/TELEMETRY.md`](docs/TELEMETRY.md) — opt-in usage data and the feedback relay

## License

MIT
