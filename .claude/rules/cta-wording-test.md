---
paths:
  - "Shared/Utilities/CTAExperiment.swift"
  - "Shared/Utilities/VitalsConversionCopy.swift"
  - "Vitals/Views/PaywallView.swift"
  - "Shared/Services/StoreService.swift"
---

# Vitals: the CTA wording test (2026-10-15)

`CTAExperiment` assigns each install "my" or "your" (50/50, sticky) and every
trial CTA in `VitalsConversionCopy` reads "Start my/your free trial" (title
case on the paywall and capsules). The arm goes to RevenueCat as
`cta_wording` with the funnel attributes in `StoreService.syncConversionAttributes`.
It is independent of the offering-driven `paywall_variant` experiment.
Method, readout script and decision rule: `~/ios/growth/cta-wording-test.md`.
After the day-14 readout, delete `CTAExperiment` and hardcode the winner.
`-cta.arm my|your` (DEBUG) pins the arm for captures.
