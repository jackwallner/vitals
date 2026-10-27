---
paths:
  - "Shared/Utilities/TrialNote.swift"
  - "Vitals/Views/DashboardView.swift"
  - "Vitals/Views/ReviewPromptSheet.swift"
---

# Vitals: the trial pitch indie note test (2026-10-27)

`TrialNote` adds "We're a small indie studio. Your trial helps us keep
building. Not for you? Cancel anytime and tell us what to fix." under the
onboarding pitch's four rows when the current offering's `trial_note`
metadata is `indie`. Missing or unknown is `none`, the live pitch. A test is a
RevenueCat Experiment whose treatment offering sets the key (the
`CTAExperiment` pattern); set it the same on every offering outside the test.

The note's promise is kept: a customer who saw it (`trialNote.seen`) and then
switches the trial's renewal off is asked "Your trial won't renew. What should
we fix?" once, through `ReviewPromptSheet(asksWhatToFix:)`, on Today when it
is clear (`StoreService.whatToFixDue`, `presentWhatToFixWhenClear`). The arm
rides to RevenueCat as `trial_note` with the funnel attributes.

The CTA bar must not move between arms (`OnboardingFlowUITests.testTrialNoteArms`).
`-trialNote.arm none|indie` (DEBUG) pins the arm. Plan, go-live and the
pre-registered rule: `~/ios/growth/indie-note-test.md`.
