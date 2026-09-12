# 5.1.1(ix) appeal kit (build 8, submission fd2bd256-b778-472f-8171-8a87f2b8e4fa)

Everything needed to fight the "organization account required" rejection without
spending on an LLC. Three free levers, fired together. Facts below are the
canonical phrasing; reuse them verbatim so the record stays consistent.

## The facts (the whole argument)

- Vita is a personal logbook plus cited educational reference. It offers no
  service: no telemedicine, no consultations, no pharmacy, no sale or
  fulfillment of any substance, no lab-testing service, no insurance.
- No user accounts and no backend operated by the developer. All user data
  lives in a local on-device database. Nothing is collected server-side.
- The only network calls send user-initiated text or a lab photo to an AI API
  to generate an educational response; nothing is stored or linked to an
  identity.
- Every compound page cites its sources (PubMed, ClinicalTrials.gov, FDA
  DailyMed for prescription drugs). Every AI, dosing, and lab surface carries
  a persistent "Educational, not medical advice" disclaimer.
- Health integrations (Apple Health, Oura) are optional and read-only.
- The guideline's own text targets apps "operating in highly regulated
  fields" that provide services: telehealth, pharmacies, gambling, money
  lending, cryptocurrency exchanges. Vita provides no service in any of these
  categories. It records what users already do under their own direction and
  educates with citations, the same shape as a medication-reminder or
  supplement-tracking app, categories long published by individual developers.

## Lever 1: Meet with Apple appointment (book first, strongest)

Where: developer.apple.com/meet-with-apple, App Review consultation slot
(Tuesdays/Thursdays, offered directly in the rejection message).
Bring: submission ID fd2bd256-b778-472f-8171-8a87f2b8e4fa, the facts above.

Talking points, in order:

1. Every other guideline issue is resolved as of build 8; 5.1.1(ix) is the
   only open item.
2. Walk the facts list. Emphasize: no service, no accounts, no backend,
   local-only data.
3. The precise question to ask, word for word: "Which specific highly
   regulated service category does Vita fall under, and what concrete change
   would take it out of that category?" Any answer helps: either the
   classification falls apart in conversation, or we finally learn the exact
   trigger and can decide whether a descope is worth it.
4. If they hold: ask whether an individual account with the app scoped to
   educational reference only (no reconstitution calculator, for example)
   would clear, so the descope option is fully priced before any LLC spend.

## Lever 2: App Review Board appeal (file the same day)

Where: developer.apple.com/contact/app-store/?topic=appeal

Paste:

> We are appealing the 5.1.1(ix) rejection of Vita 1.0.0 (submission
> fd2bd256-b778-472f-8171-8a87f2b8e4fa) on the classification itself.
>
> Guideline 5.1.1(ix) applies to apps that offer highly regulated services or
> require sensitive user information. Vita does neither. It is a personal
> logbook with cited educational reference content: no telemedicine, no
> consultations, no pharmacy, no sale or fulfillment of any substance, no
> lab-testing service, and no financial services. It has no user accounts and
> no developer-operated backend; all user data is stored locally on the
> device and no sensitive information is collected by us. Health integrations
> are optional and read-only. Every compound page cites PubMed,
> ClinicalTrials.gov, and, for prescription medications, FDA DailyMed, and
> every relevant screen carries a persistent "Educational, not medical
> advice" disclaimer.
>
> Apps of the same shape, medication reminders and supplement trackers, are
> published by individual developers today. We ask the Board to review
> whether the highly-regulated classification is correct for an app that
> operates no service and holds no user data. All other issues raised in
> review have been resolved in build 8, which reviewers confirmed by
> narrowing the rejection to this single item.
>
> If the Board upholds the classification, we would appreciate the specific
> service category Vita is considered to fall under so we can either bring
> the app out of that category or complete organization enrollment.

## Lever 3: Resolution Center reply (keeps the thread coherent)

Paste:

> Thank you. Build 8 resolved the HealthKit and age-rating items, and we
> understand 5.1.1(ix) is the only remaining issue. We have requested a Meet
> with Apple review appointment and filed an appeal with the App Review Board
> regarding the highly-regulated classification, and we would welcome the
> chance to discuss it. We are not abandoning this submission.

## Standing decisions

- Do not cancel the submission; the reviewer thread has the fix history.
- TestFlight distribution continues meanwhile. Build 8 expires ~November 20,
  2026; ship build 9 before then regardless of review status.
- LLC routes stay deferred until affordable. Cheapest on record: New Mexico
  LLC ~$50 filing + ~$35-50/yr registered agent; Texas LLC $300; friend's-LLC
  new-org enrollment is $0 to us but makes their LLC the seller of record and
  the legally responsible publisher. D-U-N-S is free; conversion takes 2-3
  weeks once an entity exists.
