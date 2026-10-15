# Vitals - Project Guide

Personal iPhone + Apple Watch health tracker. Tracks total calories (active + resting) and steps via HealthKit. Local-only storage, no CloudKit.

XcodeGen project/scheme: `Vitals`, sim lease owner `vitals`.

## Tech Stack

- Swift 6 / SwiftUI (strict concurrency: `@MainActor`, `@Sendable`)
- HealthKit (read-only: `activeEnergyBurned`, `basalEnergyBurned`, `stepCount`)
- SwiftData (local cache for widget reads; HealthKit is the source of truth)
- WidgetKit (iOS widgets + watchOS complications)
- XcodeGen (`project.yml`). Targets: iOS 17+, watchOS 10+

## Architecture

### 4 Targets

| Target | Type | Bundle ID | Platform |
|--------|------|-----------|----------|
| Vitals | iOS app | `com.jackwallner.vitals` | iOS |
| VitalsWidget | app-extension | `com.jackwallner.vitals.widget` | iOS |
| VitalsWatch | watchOS app | `com.jackwallner.vitals.watch` | watchOS |
| VitalsWatchWidget | app-extension | `com.jackwallner.vitals.watch.widget` | watchOS |

- `Vitals` embeds `VitalsWidget` (iOS widget) and `VitalsWatch` (watch auto-install)
- `VitalsWatch` embeds `VitalsWatchWidget` (watch complications)
- All 4 targets include `Shared/` sources

**Directory layout, data flow, key services (HealthKitService/GoalSettings/DataService), the theme system, and the full UserDefaults key table: `vitals-architecture` skill.** Load it before working on Vitals internals.

## App-specific notes

- App Group: `group.com.jackwallner.vitals`.
- Rating ask: fleet policy in the `ios-dev` skill ("App Store ratings and feedback"). `requestReview()` is called directly after a **daily goal hit** (and the other one-shot positive moments in `ReviewPromptTracker`), with no "Enjoying it?" question first (App Review 5.6.1). Gates: finished setup, second launch, 30-day cooldown; only "Write a Review" ends the passive asks, feedback does not. Settings has separate "Write a Review" (`AppStoreReviewLinks.writeReviewURL`) and "Send Feedback" rows.
- App Store Submission specifics: privacy policy at `docs/privacy-policy.html` (GitHub Pages: `https://jackwallner.github.io/vitals/privacy-policy.html`); privacy manifests `Vitals/PrivacyInfo.xcprivacy` + `VitalsWatch/PrivacyInfo.xcprivacy`; `healthkit` in required device capabilities; VoiceOver labels on all interactive elements; goal validation (calories 500-50,000, steps 100-500,000); HealthKit-denied state shows guidance + Settings link.
- Paywall CTA wording test ("Start my/your free trial", 2026-10): `.claude/rules/cta-wording-test.md`.
- Android port (Health Connect, Compose, Play, RevenueCat, emulator on Pro, Console answers): `.claude/rules/android.md`.
- Astro ASO: `./scripts/astro-setup.sh` (`--extra "phrase"` for app-specific terms); local MCP `http://127.0.0.1:8089/mcp`; playbook `~/ios/aso/astro-setup-process.md`; re-sync keywords `./scripts/sync-astro-keywords.sh`.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, ratings ask, HealthKit/widget gotchas):
the global agent rules + the `ios-dev` skill.
