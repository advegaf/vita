# Privacy Policy — Vita

_Last updated: June 11, 2026_

Vita is an educational peptide-tracking journal. It is built so that your data
stays yours.

## What Vita stores, and where

Everything you enter — your plan, dose logs, diary check-ins, body
measurements, lab panels, and chat history — is stored **locally on your
device**. There is no Vita server, no account, and no sign-up.

## What leaves your device

Two features call Anthropic's Claude API, and only with content you initiate:

- **Chat and plan generation**: your message plus the context that grounds the
  answer (your plan, recent logs, lab flags, and Apple Health summary values)
  is sent to Anthropic to generate the response.
- **Lab scanning**: the lab photo or PDF you choose is sent to Anthropic to
  read its values, after a one-time in-app consent. The original stays on your
  device with location metadata stripped.

This content is used solely to generate the response. Vita has no analytics,
no advertising, no trackers, and sells nothing. See Anthropic's privacy policy
for how API inputs are handled: https://www.anthropic.com/legal/privacy

## Apple Health

With your permission, Vita **reads** weight, height, sleep, heart rate, HRV,
and steps to ground its educational suggestions. Vita never writes to Apple
Health, and Health data is never used for advertising or shared with anyone
except as part of the AI context described above.

## Notifications

Dose reminders are scheduled locally on your device. Nothing about them leaves
your phone.

## Your controls

- Export everything (JSON + CSV) from Settings at any time.
- Delete chat history, dose logs, or every byte of data (Settings → Danger
  zone → Full reset).
- Revoke lab-scan consent in Settings → Privacy.

## Not medical advice

Vita is educational only. It does not diagnose, treat, or prescribe, and its
content is not a substitute for a clinician.

## Contact

Questions: open an issue at https://github.com/advegaf/vita or email
advegaf@tamu.edu.
