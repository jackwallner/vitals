---
paths:
  - "Shared/Utilities/CTAExperiment.swift"
  - "Shared/Utilities/VitalsConversionCopy.swift"
  - "Vitals/Views/PaywallView.swift"
  - "Shared/Services/StoreService.swift"
---

# Vitals: the CTA wording test (2026-10-15, control added 2026-10-20)

`CTAExperiment` ships three trial-button wordings: `standard` (the live 1.8.8
copy, "Start 7-day free trial" / "Start Free Trial"), `my` and `your`. The
current offering's `trial_cta` metadata picks one; missing or unknown is
`standard`, so the binary alone changes no button. A wording test is a
RevenueCat Experiment whose treatment offering sets `trial_cta`, the Mahj
pattern (Jack's 2026-10-16 ruling: no in-app 50/50 without a control).
Set the key the same on every offering outside the test, and mind that RC
Experiments enrol new customers only and compete with the offering-driven
`paywall_variant` (`upgrade_tab`) experiment for traffic.
The arm also goes to RevenueCat as `cta_wording` with the funnel attributes in
`StoreService.syncConversionAttributes`.
Method and readout: `~/ios/growth/cta-wording-test.md`.
`-cta.arm standard|my|your` (DEBUG) pins the arm for captures.
