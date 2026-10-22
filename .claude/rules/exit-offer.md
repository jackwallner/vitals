---
paths:
  - "Shared/Utilities/ExitOffer.swift"
  - "Vitals/Views/ExitOfferView.swift"
  - "Vitals/Views/PaywallView.swift"
  - "Vitals/Views/TrialOfferPitch.swift"
  - "Shared/Services/StoreService.swift"
---

# Vitals: the paywall exit offer (2026-10-21, 1.9.1)

A deliberate paywall close (onboarding "Get Started", trial sheet "Not now",
paywall close button) shows Vitals+ Yearly at half price once, to half of
closers; the other half is a holdout. The plan is the `exit_annual` package in
the `exit_offer` offering, which is never current, so it stays out of every plan
list and every older binary. The split lives in that offering's metadata
(`offer_pct`, `salt`, `force`) and is a stable hash of the RevenueCat app user
id, so it runs beside RevenueCat Experiments without competing for traffic.
`exitOfferPackage` is kept out of `products` on purpose: its product id
contains the yearly one and would match `yearlyPackage`.
`-exitOffer.force` (DEBUG) shows it on the next close for captures.
Method, go-live steps and readout: `~/ios/growth/exit-offer-test.md`.
