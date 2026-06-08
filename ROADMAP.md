# Roadmap

Where Vita is, how it got here, and what's worth doing next. This is a living document — update it as the project moves.

---

## Status at a glance

- **Working, full vertical slice.** All four tabs + onboarding + labs + calculator + settings are built and run on device and simulator.
- **159 unit tests**, green. Pure-logic engines (scheduling, reconstitution, streaks, diary series, lab flagging) and services are well-covered; there are **no UI/snapshot tests and no CI** yet.
- **~12k lines of Swift**, single app target, iOS 26 / Swift 6.
- **Distribution:** personal / TestFlight-style only. The Anthropic key is embedded per-device (Keychain), which is fine for personal use but **cannot** ship to the App Store as-is (see [Distribution & security](#1-distribution--security-highest-leverage)).

---

## What's shipped (milestones)

The app was built in numbered milestones. Each was independently demoable.

| # | Milestone | Highlights |
|---|---|---|
| **M0** | Scaffold + design system | Tokens, typography (Inter Tight), motion, haptics; signature components — `CandySegmentedControl` (width-spring), the north-star `PinRow` tap; 4-tab Liquid Glass shell. |
| **M1** | Data + catalog | CloudKit-legal SwiftData models (`VitaSchemaV1`), local container, ~58-compound `catalog.json` seed + 6 goals, `CatalogStore`; searchable grouped catalog + Stack with add/edit/remove/dedupe. |
| **M2a/b** | Add-setup sheet + Today | `DoseSetupSheet` (dose/frequency/times), `ScheduleService` (occurrences/due-day/blocks), the loved time-adaptive Today (focus card, expanding block control, filtered pins); category-colored vial tiles. |
| **M2.5** | Reconstitution + vials | `ReconstitutionCalculator` (U-100/50/40), `Vial` model, "draw to X units" surfaced everywhere. |
| **M2** | Onboarding wizard | Welcome/consent → goals → peptides → labs → generating → review → notifications; rule-based `StarterSuggester`. |
| **M2.6** | Working reminders | `NotificationManager` (materialized window, deterministic IDs, 64-cap), Time-Sensitive entitlement; symmetric dose stepper + keyboard fixes. |
| **M3a** | Real Claude protocol gen | `AnthropicClient` (actor, raw URLSession, Opus-4.8 constraints, retry, forced tool-use), Keychain + seed-on-launch, `ClaudeService`/stub/factory, `emit_protocol` strict schema, validation + repair-retry + offline fallback; `HealthKitService`; profile fields; Health onboarding step. |
| **M3b** | Streaming Chat | SSE `streamChat`, `suggest_stack_action` tool, grounded chat (catalog + stack + goals + profile + Health), `ChatMessage` persistence, `Connectivity`. |
| **M3.6/3.7** | Polish | Always-colored tab icons, keyboard handling (tap-to-dismiss app-wide), onboarding units. |
| **M4** | Persistent logging | `DoseLog` (append-only), `DoseLogger` (upsert/undo/PRN), derived state, `StreakService`, day-complete + rest-day moments, PRN "as needed" card. |
| **M4.6** | Chat refinement | Multi-suggestion Add chips, "knowledgeable friend" voice, em-dash sanitizer, calmer keyboard. |
| **M5** | Notification actions | Lock-screen Log / Skip / Snooze (shared `DoseLogger`), suppress-if-logged, tap → detail sheet. |
| **M6** | Detail spine | (Built then **reverted** — the segment-spine on the detail screen; the plain stacked cards were preferred.) |
| **M7** | Reconstitution calculator UI | `ReconCalculatorView` sheet (draw units, mg↔IU, warnings), save-as-vial, write-back to the dose sheet. |
| **M8a/8a.1/8.2** | Diary | Dashboard (check-in / weight / trend), the signature 1–10 `VitaSlider`, `DiaryEntry`/`BodyMetric`, Apple-Health weight backfill, first Swift Charts trend with drag-scrub; app-wide UI polish (shared `PillToggle`/`ScreenHeader`/`CircleIconButton`). |
| **M8.3** | Rename → "Vita" | Wordmark, bundle id, display name (from the "ACME" placeholder). |
| **M8b** | Lab scan + analysis | Claude **vision** (`interpret_labs`), `LabPanel`/`LabValue`, deterministic flagging, EXIF-strip, panels + "vs last" delta, QuickLook original; removed the ✺ glyph + done-pulse. |
| **M9** | Cycles + titration | Cycle as an envelope over `isDueDay` (off-block → rest, never overdue), titration as a per-date dose resolver; `CycleRibbon` + `TitrationLadder`; advanced setup; review-only change notices. |
| **M10** | Settings | Profile, units, permission-aware notifications, Apple Health re-sync, API-key status/replace/test, ℞ overrides sub-screen, privacy/consent, about, danger zone (clear/reset/full-wipe). |
| **M10.1** | Lab-PDF + HealthKit device fixes | Hybrid PDF handling (native for small, PDFKit rasterize for large/scanned, fallback), bigger max_tokens, specific lab error messages + Retry; restored HealthKit + Time-Sensitive entitlements for the paid signing team. |

---

## Next up

### M11 — Lab marker-over-time trend charts
Tap a marker (e.g. glucose) → see its value across **all** saved panels over time, with a reference band, reusing the Diary `TrendCard`/`DiarySeries` Charts machinery (build a `LabSeries` mirroring `DiarySeries`). Each `LabValue` already carries its own `refLow`/`refHigh`, so a reference band is straightforward. Designed but not built.

---

## What could be improved (prioritized backlog)

Roughly ordered by leverage. Effort/risk are rough.

### 1. Distribution & security (highest leverage)
The Anthropic key is embedded per-device (seeded from a gitignored xcconfig into the Keychain). **This is fine for personal/TestFlight use but cannot ship publicly** — a distributed binary's key is extractable. For any real release:
- Stand up a thin **proxy backend** (e.g. a serverless function) that holds the key and forwards Messages API calls; the app calls the proxy. Add auth/rate-limiting.
- Until then, each user supplies their own key (already supported in Settings).
- *Effort: medium. Risk: low (additive).* 

### 2. Testing & CI
- **No CI.** Add a GitHub Actions macOS workflow running `xcodebuild … test`. Blocked today because GitHub-hosted runners may not yet have Xcode 26 / iOS 26 — revisit when they do, or use a self-hosted runner. The exact command is in [CONTRIBUTING.md](CONTRIBUTING.md).
- **No UI / snapshot tests.** The pure logic is well-tested; the views are not. Add snapshot tests for the design-system components and key screens (default + largest Dynamic Type).
- *Effort: low–medium.*

### 3. SPM module split
The original architecture envisioned local Swift packages enforcing `App → Features → Services → Core → DesignSystem`. It's currently one app target with clean *internal* layering (pure engines already isolated in `Vita/Data`). Splitting into packages would harden the boundaries and speed incremental builds/tests. *Effort: medium. Risk: medium (mechanical but broad).*

### 4. CloudKit sync
Models are already **CloudKit-legal** (all optional/defaulted, explicit inverses, no `.unique`, cascade/nullify). Enabling sync = add the iCloud entitlement, switch the container to `cloudKitDatabase: .automatic`, and move local-only models (`CatalogCompound`, scan blobs) into their own configuration. Must deploy the schema to the CloudKit Production environment before any TestFlight build. *Effort: medium. Risk: medium (schema lock-in — review the model graph first).* 

### 5. Accessibility pass
Dynamic Type, VoiceOver, and Reduce-Motion are partially handled (tokens + many labels exist). Do a full audit: every interactive control labeled, ≥44pt targets, the condensed Inter Tight font verified at XXL sizes, charts/sliders VoiceOver-adjustable. *Effort: medium.*

### 6. Labs hardening
- Device-validate the new PDF **hybrid** (native small / rasterize large) against real multi-page / scanned / portal-"protected" exports; read the `vita-labs:` console log if a scan fails.
- Add a **marker-key alias map** (e.g. `hdl` ↔ `hdl_cholesterol`) so the same marker doesn't split across panels.
- Then M11 (charts).
- *Effort: low–medium.*

### 7. HealthKit depth
Read-only today (weight/sleep/HRV/steps/characteristics). Consider: clearer authorization signaling (read auth can't be queried directly — surface "no data found" calmly), optional write-back of logged context, and persisting samples for trends. *Effort: medium.*

### 8. Notifications depth
Deferred: quiet-hours awareness, vial-expiry + inventory/reorder nudges, the daily diary nudge, and the titration/cycle `DOSE_DECISION` review category polish. *Effort: low–medium each.*

### 9. Data quality (catalog)
`catalog.json` (~58 compounds) is an educational convenience reference and is **not clinically reviewed**. Dose ranges, routes, ℞ flags, and blurbs should be verified by someone qualified before anyone leans on them. Consider sourcing/citation per compound. *Effort: medium, ongoing.*

### 10. Localization
English only. No `Localizable.strings` yet; strings are inline. Externalize before any non-English audience. *Effort: medium.*

### 11. Smaller cleanups
- **Font config:** `project.yml` `UIAppFonts` lists three filenames but only `InterTight.ttf` (a variable font) ships — reconcile the list (works today, but it's confusing).
- Audit the DEBUG-only demo/screenshot env flags (`VITA_DEMO_STACK`, `VITA_CYCLE_DEMO`, `VITA_DIARY_DEMO`, `VITA_LABS_DEMO`, `VITA_OPEN_*`, …) — handy, but document or gate them.
- Reconstitution **inventory/expiry** tracking (vial doses-remaining, reconstituted-at expiry alerts) is designed but not built.
- Onboarding lab-scan + chat live paths are user-verified but not automated.

---

## Tracked issues

The backlog above is filed as GitHub issues:

- [#1 M11 — Lab marker-over-time trend charts](https://github.com/advegaf/vita/issues/1)
- [#2 Set up CI (build + 159 tests)](https://github.com/advegaf/vita/issues/2)
- [#3 Distribution: proxy backend for the Anthropic key](https://github.com/advegaf/vita/issues/3)
- [#4 Split into SPM modules](https://github.com/advegaf/vita/issues/4)
- [#5 Enable CloudKit sync](https://github.com/advegaf/vita/issues/5)
- [#6 Accessibility audit](https://github.com/advegaf/vita/issues/6)
- [#7 Labs hardening: PDF hybrid + marker-key alias map](https://github.com/advegaf/vita/issues/7)
- [#8 UI / snapshot tests](https://github.com/advegaf/vita/issues/8)
- [#9 Catalog data: clinical review](https://github.com/advegaf/vita/issues/9)

## Non-goals (for now)

Dark mode (tokens are ready), a watchOS companion, cost/price tracking, multi-user/caregiver sharing, and full App Store hardening (which requires the proxy backend in #1 and a stricter content/compliance review).
