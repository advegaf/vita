# Architecture

A map of how Vita is built and where things live. Single app target, iOS 26 / Swift 6 (strict concurrency), no third-party runtime dependencies (only XcodeGen at build time + a bundled font).

## Layers

```
Vita/
├── App/            App entry, root tab view, onboarding-vs-tabs routing
├── Features/       One folder per surface — the SwiftUI views
│   ├── Today/      time-adaptive home, pins, logging
│   ├── Stack/      catalog detail, dose-setup sheet, the stack list
│   ├── Catalog/    searchable compound browser
│   ├── Diary/      check-in, weight, trend chart
│   ├── Chat/       streaming grounded assistant
│   ├── Labs/       scan flow, review, panel list/detail
│   ├── Reconstitution/  the calculator sheet
│   ├── Settings/   settings + ℞ overrides sub-screen
│   └── Onboarding/ the wizard + steps
├── Data/           models, services, engines, the Claude client (no SwiftUI)
│   └── Claude/     AnthropicClient, ClaudeService, schemas, DTOs, Keychain
├── DesignSystem/   tokens, typography, motion, haptics, components, gallery
└── Resources/      Fonts/ (Inter Tight), catalog.json, Assets.xcassets
```

Dependencies point one way: **App → Features → Data / DesignSystem**. The `Data/` engines are platform-light and pure where it matters, so they unit-test in milliseconds. (A future hardening step is to split these into SPM packages — see ROADMAP.)

## Data model (SwiftData)

All `@Model` types are registered in `VitaSchemaV1` (`Data/ModelContainer.swift`) and follow **CloudKit-legal** rules so sync can be enabled later with no model rework: every stored property optional or defaulted, every relationship optional with an explicit inverse, no `.unique`, delete rules `.cascade`/`.nullify` only. Uniqueness (slugs, singletons) is enforced in code via fetch-before-insert.

- **Singletons:** `UserProfile`, `AppSettings` (fixed well-known UUIDs, fetch-or-create in `CatalogStore`).
- **Catalog:** `CatalogCompound` (local-only, re-seeded from `catalog.json`).
- **Stack:** `ProtocolPlan` → `ProtocolItem` → `ScheduleRule` (+ `Vial`). `ScheduleRule` holds frequency, time slots, weekdays, the protocol-start anchor, and the cycle/titration fields.
- **Logs/history:** `DoseLog` (append-only, denormalized — survives item edits), `DiaryEntry` + `BodyMetric`, `LabPanel` → `LabValue`, `ChatMessage`.

Two recurring SwiftData gotchas (encoded in the tests): set a relationship **only after** `context.insert`, and **retain** an in-memory `ModelContainer` in tests (a dropped one traps on use).

## Scheduling engine (derive live, never materialize)

`Data/ScheduleService.swift` computes everything on the fly from a `ScheduleRule` + a date — there is no `DoseEvent` table.

- `occurrences(for:on:)` / `isDueDay(_:on:)` — daily / eod / weekly / prn.
- **Cycles** are a one-line gate at the top of `isDueDay`: an off-block returns `false`, so it produces zero occurrences → automatically a rest day that holds the streak and fires no reminders. `cycleStatus(...)` drives the `CycleRibbon`.
- **Titration** is a per-date resolver: `activeDose(for:on:)` returns the latest step ≤ the date, surfaced everywhere via `ProtocolItem.effectiveDose(on:)`. `titrationLadder(...)` drives the `TitrationLadder`.

`DoseLogger` (`log`/`undo`/`logPRN`, upsert by item+day+slot) is the single write path for logging, shared by the in-app tap and the notification actions. `StreakService` and the per-occurrence state (`.due/.overdue/.taken/.skipped`) are pure functions over the logs.

Other pure engines: `ReconstitutionCalculator` (units/concentration/warnings, mg↔IU), `DiarySeries`/`DiaryStreak` (chart series + streak), `LabService.computeFlag` (deterministic high/low from value vs range).

## Claude integration (`Data/Claude/`)

The only network surface. Raw HTTPS over `URLSession` (no SDK), all against the Anthropic Messages API with `anthropic-version: 2023-06-01`.

- **`AnthropicClient`** (actor) — builds requests with Opus-4.8 constraints (no `temperature/top_p/top_k`, no `thinking` on forced tool-use), retries 429/500/529 + transient transport (never 400), and parses the forced `tool_use` block. Methods: `send` (non-stream, forced tool), `sendVision` (image/PDF + forced tool, multi-attachment), `streamChat` (SSE), `ping` (key liveness).
- **`ClaudeService`** + `StubClaudeService` + `ClaudeServiceFactory` — the boundary the UI calls. Live hits Claude; the stub returns canned fixtures so the app builds/runs/tests with no key (`VITA_CLAUDE_STUB=1`). Jobs: `generateProtocol` (forced `emit_protocol`), `streamChat` (grounded, `suggest_stack_action` tool), `interpretLabs` (vision `interpret_labs`, hybrid native-PDF / rasterized).
- **`ClaudeSchemas`** — the system prompts + strict tool schemas. A cached catalog/safety prefix (prompt-cache breakpoint) + an uncached per-user grounding block (goals/profile/Health/stack/diary/labs).
- **Validation** — model output is never trusted: unknown slugs dropped, doses clamped to the catalog's educational range, identity/units from the catalog; one repair-retry, then a rule-based fallback.
- **Keychain** — the key is seeded once from `Config/Secrets.xcconfig` → Info.plist → Keychain on first launch; the Keychain is the only runtime source thereafter.

## Other services

- **`NotificationManager`** — materializes a rolling 14-day window of concrete, deterministic-ID reminders from the schedule, skipping any occurrence that already has a `DoseLog`; caps under the 64-pending limit. `NotificationRouter` handles lock-screen Log/Skip/Snooze (routing to the shared `DoseLogger`) and body-tap → detail sheet. Plus review-only titration/cycle change notices.
- **`HealthKitService`** (actor) — read-only weight/sleep/HRV/steps + DOB/sex, and a ~90-day weight backfill merged idempotently into the Diary.
- **`LabImageEncoder`** — EXIF-strips + downscales photos; rasterizes PDFs to images via PDFKit for the hybrid lab path.
- **`Connectivity`** — `NWPathMonitor` for the chat offline state.

## Design system (`DesignSystem/`)

A closed token set (`VT.*`): cream canvas, white cards, candy accents (cyan dose / yellow timing / brown why / clay overdue-only), Inter Tight headlines with mandatory trailing periods, tabular figures on every changing number. Signature pieces: the **`CandySegmentedControl`** (expand-on-select width spring) and the **north-star pin-tap** (`PinRow`: press → ring fill → checkmark stroke → spring bump → haptics). Liquid Glass only on nav/controls/sheets — never content cards. Shared building blocks: `PillToggle`, `ScreenHeader`, `CircleIconButton`, `CharcoalPillButton`, `FieldShell`, `vtCard()`, `VMotion`, `Haptics`. Every component ships a `#Preview` on cream with real sample data.

## Build

`project.yml` (XcodeGen) is the source of truth; `Vita.xcodeproj` is generated and gitignored. Signing team + bundle id + API key come from `Config/Secrets.xcconfig` (gitignored) so nothing personal lives in the repo. Info.plist lives at `Support/Info.plist`; entitlements (HealthKit + Time-Sensitive) at `Support/Vita.entitlements`. See [CONTRIBUTING.md](CONTRIBUTING.md).
