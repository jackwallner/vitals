---
paths:
  - "Shared/Utilities/ExitOffer.swift"
  - "Vitals/Views/ExitOfferPriceTiles.swift"
  - "Vitals/Views/DashboardView.swift"
  - "Vitals/App.swift"
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
The offer appears in place, never as a new screen (Jack's 2026-10-23 call,
after a standalone screen read as an ad): the page that was closed stays,
`ExitOfferPriceTiles` (usual price struck through beside the half price)
slides in where the plans or under the benefit rows were, the primary button
buys `exit_annual`, and the way out reads "No thanks" (the paywall keeps its
close button). The tiles appearing is the impression; "No thanks" calls
`StoreService.declineExitOffer()`, and a purchase records its outcome in
`StoreService.purchase`.
The tile reads "Your price", never "One-time price": the plan renews at that
price every year. While `force: "offer"` is set for App Review, every 1.9.1
build in the wild and every non-capture UI test gets the offer on its first
close, so UI test dismiss helpers also look for "No thanks".
`-exitOffer.force` (DEBUG) shows it on the next close; `-PaywallSnapshot
exit-sheet` captures the trial sheet version and `exit` the paywall (tap close).
UI tests: `ExitOfferUITests` (onboarding, paywall),
`SeededHealthFlowUITests.testTrialSheetNotNowTurnsIntoTheExitOffer` (the real
trial sheet), and the `testOnboardingExitOffer` release journey.
Method, go-live steps and readout: `~/ios/growth/exit-offer-test.md`.
