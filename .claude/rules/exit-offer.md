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
(`presentExitOfferWhenClear`) raises it as its own sheet on the first return
to the app (a launch or a return from the background) at least an hour after
the first close (`ExitOffer.isReady`, `returnDelay`), once Today has been clear
for 3 seconds (`isTodayClear`, plan loaded). Jack's 2026-10-24 call, replacing
the in-place version of 10-23: on video the switch to the half price inside the
page being closed was too easy to miss. 2026-10-26: the wait for a return
replaced "3 seconds after the close", so the visit where they said no stays
theirs. A pinned arm (`force`, or `-exitOffer.force`) skips the wait
(`StoreService.exitOfferSkipsWait`) so App Review sees it after the close;
`-exitOffer.returnDelay <seconds>` (DEBUG) keeps a short wait for UI tests. The sheet is the trial
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
Welcome price (2026-10-27, Jack's call after the trust question: an
unexplained cut that reverts looked arbitrary). From the moment the tiles
first appear (`ExitOffer.shownAt`) the half price stands for 48 hours
(`welcomeWindow`): `StoreService.refreshWelcomePrice` swaps `exit_annual` into
`products` in yearly's place, so every paywall, pitch and disclosure sells it;
the sheet's subheadline and the Upgrade tab header read "Welcome price, ends
in N hours." (`ExitOffer.welcomeLine`, hours down to 90 minutes, then
minutes); the paywall's yearly card shows HALF OFF and the regular price
struck through (`regularYearlyPackage`, never `yearlyPackage`, which is the
swapped plan). It then ends for good: a Task at the deadline and every return
call `refreshWelcomePrice`, and nothing restarts it. Release builds also keep
`shownAt` in the Keychain (`ShownAtKeychain`) so a reinstall neither brings
the offer back nor reopens the window; debug builds skip the Keychain and
count only this run's showing (`shownThisRun`), so one UI test never leaves
the next at the welcome price. Once seen ended it stays ended
(`welcomeEnded`), and a clock earlier than the showing reads as ended, so
setting the clock back never reopens it. The swap needs the offer arm, live or
recorded at the first close on this install (`ExitOffer.recordedArm`), so
clearing `force` never cuts a window short and a reinstall that hashes into
the holdout never inherits a Keychain window. The
offer sheet counts from now only before the window opens
(`ExitOffer.windowStart == nil`), then only the real deadline. A forced arm
(`force: "offer"`) on a sandbox receipt forgets an ended showing on the next
close (`resetEndedShowingForReview`), so a review device that saw it before
sees it again; a live customer never gets a second window. Legal footing: a real deadline is fine under
the FTC, the EU UCPD and the UK DMCC Act; only a timer that resets or a price
that doesn't revert is not. Keep the copy calm (hours, no seconds, no "gone
forever"): Apple has rejected a "one-time offer" exit flow under 5.6.
`-exitOffer.welcomeWindow <seconds>` (DEBUG) shortens it.
UI tests: `ExitOfferUITests` (including
`testWelcomePriceStaysOnThePaywallUntilItEnds`) (onboarding at default and AX text, and the
wait for a return),
`SeededHealthFlowUITests.testTrialSheetNotNowLeadsToTheExitOffer` (the real
trial sheet), and the `testOnboardingExitOffer` release journey.
Method, go-live steps and readout: `~/ios/growth/exit-offer-test.md`.
