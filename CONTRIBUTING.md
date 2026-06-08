# Contributing / Building

## Prerequisites

- **macOS** with **Xcode 26** (iOS 26 SDK).
- **XcodeGen**: `brew install xcodegen`.
- Optional, for AI features: an **Anthropic API key** (https://console.anthropic.com).
- Optional, for a physical device: an **Apple Developer** account + Team ID.

## Local config

The repo contains no keys or signing identity. Create your local config from the template:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Then edit `Config/Secrets.xcconfig` (it's gitignored — never commit it):

```
ANTHROPIC_API_KEY = sk-ant-...        # optional; leave blank to use the offline fallback
DEVELOPMENT_TEAM   = ABCDE12345       # your Team ID; only needed for device builds
```

- The **key** is copied into the Keychain on first launch and used at runtime. With no key, onboarding builds a rule-based starter stack and AI features are unavailable (or use the stub — see below). You can also paste a key at runtime in **Settings → AI**.
- The **bundle id** defaults to `com.example.vita` (in `project.yml`). Change it there, or override `PRODUCT_BUNDLE_IDENTIFIER` if you prefer.

## The build loop

```bash
xcodegen generate          # after editing project.yml or adding/removing files

# Build + test on a simulator (no key or signing needed):
xcodebuild -project Vita.xcodeproj -scheme Vita \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Or just open it:
open Vita.xcodeproj
```

Run **`xcodegen generate` whenever you add/remove files or edit `project.yml`** — the `.xcodeproj` is generated and gitignored.

### Device builds (signing)

Set `DEVELOPMENT_TEAM` in `Secrets.xcconfig`, then:

```bash
xcodebuild -project Vita.xcodeproj -scheme Vita \
  -destination 'platform=iOS,id=<your-device-udid>' \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> \
  build/Build/Products/Debug-iphoneos/Vita.app
```

- **Paid Apple Developer account:** the bundled entitlements (HealthKit + Time-Sensitive notifications) provision automatically with `-allowProvisioningUpdates`.
- **Free account:** you **cannot** provision HealthKit or Time-Sensitive notifications. Either remove those two keys from `Support/Vita.entitlements` for a 7-day sideload (the app still runs — HealthKit no-ops, reminders fire at normal priority), or use a paid account.
- **Codesign "detritus" error** (`resource fork, Finder information, or similar detritus not allowed`) — iCloud/Desktop extended attributes. Fix: `xattr -cr .` before building.
- First device launch needs the developer cert trusted: **Settings → General → VPN & Device Management**.

## Running with the stub (no key, deterministic)

Set the launch env var `VITA_CLAUDE_STUB=1` to use canned AI responses (also used by tests and screenshots). There are several DEBUG-only demo/screenshot flags (e.g. `VITA_DEMO_STACK=1`, `VITA_CYCLE_DEMO=1`, `VITA_DIARY_DEMO=2`, `VITA_LABS_DEMO=1`, `VITA_OPEN_SETTINGS=1`); pass them to the simulator with the `SIMCTL_CHILD_` prefix, e.g. `SIMCTL_CHILD_VITA_DEMO_STACK=1 xcrun simctl launch <sim> <bundle-id>`.

## Conventions

- **Swift 6, strict concurrency.** Keep the `Data/` engines pure/testable; views stay thin.
- **Design system first.** Use `VT.*` tokens and the shared components (`PillToggle`, `ScreenHeader`, `vtCard()`, …). No raw system colors; Liquid Glass only on nav/controls/sheets, never content cards. Every component ships a `#Preview`.
- **Tests.** Add unit tests for any new pure logic. Honor the two SwiftData test traps (insert before wiring a relationship; retain the in-memory container).
- **Copy.** No em dashes in user-facing strings (there's a guard test). Keep the calm, educational voice; the disclaimer surfaces stay.
- **Commits.** Stage files explicitly by name (avoid `git add -A` — it sweeps up `.DS_Store` / `Icon?` junk). Don't commit `Config/Secrets.xcconfig`.
- **No CI yet** — run the test command above before pushing. (Wiring CI is a roadmap item; it's blocked on hosted runners shipping Xcode 26.)

## Where to start

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for the map and **[ROADMAP.md](ROADMAP.md)** for the backlog. Open issues are tagged for good entry points.
