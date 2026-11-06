# Vitals: the paywall exit offer (removed 2026-11-06)

The half-price yearly exit offer shipped in 1.9.1 (2026-10-21) as a 50/50 hashed
test. It ended 2026-11-06: the holdout won, and the code is removed. Every
customer now gets what the holdout arm got: the same paywalls, trial pitches,
plans and copy.

Keep the `exit_offer` offering, its `exit_annual` package and the App Store
Connect plan `com.jackwallner.vitals.yearly.exit` live and sellable while the
1.9.1-1.9.3 binaries are in the wild. A customer on those builds who is owed the
sheet waits for that package, and has the passive trial pitches held off until
it loads.

Method and readout: `~/ios/growth/exit-offer-test.md`.
