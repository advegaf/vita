# Vita — App Store Connect listing (v1.0.0)

Everything to paste into App Store Connect, field by field. Screenshots live in
`marketing/appstore/` (6.9", 1320x2868) and `marketing/appstore-6.5/` (6.5", 1284x2778).

---

## App Information (sidebar → General → App Information)

| Field | Value |
|---|---|
| Name | `Vita: Peptide Tracker` |
| Subtitle | `Track doses, vials and labs` |
| Primary category | Health & Fitness |
| Secondary category | Education |
| Age rating | see questionnaire answers below |

### Age rating questionnaire

- Violence / profanity / mature themes / horror / gambling / sexual content / contests: **None**
- Unrestricted Web Access / real-money gambling: **No**
- **Medical or Treatment Information: Infrequent** ("Frequent" is for apps whose core
  content is treatment guidance; it drags the rating to 17+/18+ and contradicts the
  educational positioning)
- **Health or Wellness Topics: Yes** (the app presents health/wellness content throughout)
- **Alcohol, Tobacco, or Drug Use or References: None** (that category is about
  depicting recreational/illegal drug use; the medical question covers this app)
- AI chat, if asked: AI-generated content, not user-to-user; no shared user-generated content
- Expected computed rating: 12+/13+ — if it computes higher, an answer got over-declared

## Previews and Screenshots

- **6.5" Display slot:** upload the 8 PNGs from `marketing/appstore-6.5/` in name
  order (`01-today` → `08-stack`).
- **6.9" Display slot** (if shown): upload `marketing/appstore/` instead — same order.
- Only the first 3 appear on the install sheet (Today, Diary, Chat lead for that reason).
- App Previews (videos): skip for launch.

## Promotional Text (170 max)

```
Your protocol, handled. Every dose timed, every vial tracked, labs charted over time, and your ring's sleep and HRV on one calm page. Educational, private, local first.
```

## Description (4,000 max)

```
Vita is a calm, educational companion for tracking peptide protocols. It keeps your schedule, your vials, and your bloodwork in one quiet, beautiful place, and it never pretends to be your doctor.

YOUR PROTOCOL, HANDLED
See exactly what is due today, log a dose in one tap, and let morning, day, and night views keep the list short. Cycles, rest days, and week-by-week titration schedules are first-class: Vita always knows which week you are in and what the active dose is.

NEVER LOSE TRACK OF A VIAL
Each compound tracks its vial: doses remaining, reconstitution date, and when it runs out. A built-in reconstitution helper shows the math behind vial size, water, and draw volume for U-100, U-50, and U-40 syringes, so you can understand the numbers. Educational only.

YOUR RING'S DATA, ONE CALM PAGE
Connect Oura with a read-only sign-in and the Diary shows sleep, HRV, resting heart rate, respiratory rate, readiness, and sleep score as clean trend cards. Apple Health works too. Vita never writes back to your data.

ASK ANYTHING
The built-in assistant answers educational questions grounded in your actual stack, schedule, and recent sleep data. Every answer stays educational; nothing in Vita is medical advice.

YOUR BLOODWORK, IN FOCUS
Photograph a lab report and Vita reads the values, keeps every marker with its reference range, and charts each one over time so you can see the trend, not just the number.

PRIVATE BY DESIGN
Your data lives on your device in a local store. No account, no tracking, no ads. Health access is read-only and optional.

Vita is an educational tool. It does not diagnose, treat, or recommend. Always discuss your protocol and lab results with your clinician.
```

## Keywords (100 max — 94 used)

```
peptide,tracker,reconstitution,dose,vial,protocol,hrv,sleep,labs,bloodwork,health,log,schedule
```

Deliberately omitted: `oura` (third-party trademark in keywords risks metadata
rejection; fine in the description), `injection` and `bpc157` (signal
self-administration of unapproved substances — rejection surface, no search value).

## URLs

| Field | Value |
|---|---|
| Support URL | `https://advegaf.com` |
| Marketing URL | leave blank |
| Privacy Policy URL (in App Privacy) | `https://advegaf.com/privacy` |

## Version / Copyright

| Field | Value |
|---|---|
| Version | `1.0.0` (must match the build's CFBundleShortVersionString) |
| Copyright | `2026 Angel Vega Figueroa` |

## Build

Attach **1.0.0 (4)** — the clean upload (build 3 carried the widget-version warning).

## App Review Information

- **Sign-in required:** OFF (no accounts exist).
- **Contact:** Angel Vega Figueroa, phone, advegaf@tamu.edu.
- **Notes:**

```
Vita is an educational tracking app for peptide protocols. It does not diagnose, treat, or provide medical advice, and a persistent "Educational, not medical advice" disclaimer appears on every AI, dosing, and lab surface.

No account or sign-in is required. All user data is stored locally on device. The optional Oura connection is a read-only OAuth sign-in; the optional Apple Health access is read-only.

The reconstitution screen is an educational math helper that shows the arithmetic relating vial size, diluent volume, and syringe draw. It does not prescribe or recommend doses; ranges shown come from a static educational catalog with sources.

The chat assistant answers educational questions only and displays the disclaimer above the input at all times. The app is fully functional without network access.

To review: the app works immediately on first launch. Add a compound from the catalog to see scheduling, vial tracking, and the calculator.
```

- **Attachment:** none.

## App Store Version Release

**Manually release this version** — confirm the live listing before launch, control timing.

## App Privacy (sidebar → Trust & Safety → App Privacy)

Declare as **collected**: Health & Fitness, User Content (lab photos, chat text).
Purpose **App Functionality**; **not linked to identity**; **not used for tracking**.
Rationale: the only data leaving the device is what is sent to the AI API for chat and
lab reading; everything else is local. Requires the Privacy Policy URL.

## Pricing and Availability

Free, all territories (trim if preferred).

## What's New (version 1.0.0)

```
Welcome to Vita.

• Today view with one-tap dose logging and morning, day, and night slots
• Cycles, rest days, and titration schedules that always know your active dose
• Vial tracking with doses left and a reconstitution calculator for U-100, U-50, and U-40
• Oura sign-in and Apple Health for sleep, HRV, resting heart rate, and readiness
• Lab report scanning with per-marker trend charts
• An educational assistant grounded in your stack and recent sleep
• Home Screen widget, reminders, and a warm dark mode
```

---

## Known review risk (accepted)

Guideline 1.4.1 restricts drug dosage calculators to approved entities. The
reconstitution helper is the exposure; the mitigation is the educational framing,
visible disclaimers in every relevant screenshot, and the review notes above. The
listing copy no longer volunteers "exact syringe draw" language. If cited, respond by
pointing at the educational framing; worst case, gate the calculator behind a
settings toggle and resubmit.
