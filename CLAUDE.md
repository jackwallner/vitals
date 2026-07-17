# Vitals - Project Guide

Personal iPhone + Apple Watch health tracker. Tracks total calories (active + resting) and steps via HealthKit. Local-only storage, no CloudKit.

XcodeGen project/scheme: `Vitals`, simulator device `agent-vitals`.

## Tech Stack

- Swift 6 / SwiftUI (strict concurrency: `@MainActor`, `@Sendable`)
- HealthKit (read-only: `activeEnergyBurned`, `basalEnergyBurned`, `stepCount`)
- SwiftData (local cache so widgets can read data — HealthKit is the source of truth)
- WidgetKit (iOS widgets + watchOS complications)
- XcodeGen (`project.yml`). Targets: iOS 26.0, watchOS 26.0

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
- Review funnel triggers after a **daily goal hit**; `AppStoreReviewLinks.writeReviewURL`. (Shared funnel mechanics + playbook in the `ios-dev` skill.)
- App Store Submission specifics: privacy policy at `docs/privacy-policy.html` (GitHub Pages: `https://jackwallner.github.io/vitals/privacy-policy.html`); privacy manifests `Vitals/PrivacyInfo.xcprivacy` + `VitalsWatch/PrivacyInfo.xcprivacy`; `healthkit` in required device capabilities; VoiceOver labels on all interactive elements; goal validation (calories 500-50,000, steps 100-500,000); HealthKit-denied state shows guidance + Settings link.
- Astro ASO: `./scripts/astro-setup.sh` (`--extra "phrase"` for app-specific terms); local MCP `http://127.0.0.1:8089/mcp`; playbook `~/ios/aso/astro-setup-process.md`; re-sync keywords `./scripts/sync-astro-keywords.sh`.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, review funnel, HealthKit/widget gotchas):
always-loaded global CLAUDE.md + the `ios-dev` skill.

## Subagent delegation
Follow the global CLAUDE.md subagent rules: ask Jack for the model before spawning, spawn at most one at a time unless Jack explicitly approves more, and never allow a subagent to spawn another subagent.
