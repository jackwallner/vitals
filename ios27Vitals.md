# iOS 27 compatibility audit: Vitals

- Audit date: 2026-08-05
- Runtime: iOS 27.0 (24A5390f)
- Xcode: 26.6 (17F113)
- Scheme: `Vitals`
- Unit target: `VitalsTests`
- Overall: Blocked on launch

## Checks

- Debug build: Pass.
- Unit tests: Pass.
- Normal rebuild after tests: Pass.
- Install: Pass.
- Launch smoke test: Fail. The process terminates with `SIGTRAP`.
- Runtime UI snapshot: The simulator returned to the Home screen after termination.

## Findings

1. Console launch output:

   `RevenueCat/Purchases.swift:73: Fatal error: Purchases has not been configured. Please call Purchases.configure()`

2. `Shared/Services/StoreService.swift:444-451` returns early from `configureIfNeeded()` under `targetEnvironment(simulator)`, but later product/customer-status paths still call `Purchases.shared`. The simulator guard therefore prevents configuration and does not prevent RevenueCat API access.
3. The build also reports `Shared/Services/SummaryReportGenerator.swift:78` unused `nonZeroStepDays` and `Vitals/Views/DashboardView.swift:1477` an `await` with no async operations.

## Required follow-up

- Guard every RevenueCat read/write path on simulator, or route simulator execution through the intended local StoreKit fixture path. Do not configure the production `appl_` key on the simulator.
- Re-run launch and UI smoke tests after that fix. This is the only app in this audit with a confirmed iOS 27 simulator launch blocker.
