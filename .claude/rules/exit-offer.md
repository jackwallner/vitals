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
The close goes through as normal in both arms. In the offer arm it marks the
offer due (`StoreService.exitOfferDue`, persisted as `ExitOffer.isPending` so
an app killed first still gets it next launch), and `MainTabView`
(`presentExitOfferWhenClear`) raises it as its own sheet once Today has been
clear for 3 seconds (`isTodayClear`, plan loaded). Jack's 2026-10-24 call,
replacing the in-place version of 10-23: on video the switch to the half price
inside the page being closed was too easy to miss. The sheet is the trial
pitch (`TrialPitchRequest.exitOffer()`) with `ExitOfferPriceTiles` (usual price
struck through beside the half price), a headline named from the real
discount ("Vitals+ at half price"), the button buying `exit_annual`, and
"No thanks" as the way out. A due offer holds off the passive launch and
History pitches. The tiles appearing is the impression; "No thanks" calls
`StoreService.declineExitOffer()`, and a purchase records its outcome in
`StoreService.purchase`. At accessibility text sizes the tiles scroll
themselves into view (`revealingInScroll`, `enclosingScrollReader`).
The tile reads "Your price", never "One-time price": the plan renews at that
price every year. While `force: "offer"` is set for App Review, every 1.9.1
build in the wild and every non-capture UI test gets the offer after its first
close, so UI test dismiss helpers also look for "No thanks".
`-exitOffer.force` (DEBUG) owes it on every close; `-PaywallSnapshot
exit-sheet` captures the sheet.
UI tests: `ExitOfferUITests` (onboarding at default and AX text),
`SeededHealthFlowUITests.testTrialSheetNotNowLeadsToTheExitOffer` (the real
trial sheet), and the `testOnboardingExitOffer` release journey.
Method, go-live steps and readout: `~/ios/growth/exit-offer-test.md`.
