# Vitals - Project Guide

Personal iPhone + Apple Watch health tracker. Tracks total calories (active + resting) and steps via HealthKit. Local-only storage, no CloudKit.

## Tech Stack

- Swift 6 / SwiftUI (strict concurrency: `@MainActor`, `@Sendable`)
- HealthKit (read-only: `activeEnergyBurned`, `basalEnergyBurned`, `stepCount`)
- SwiftData (local cache so widgets can read data — HealthKit is the source of truth)
- WidgetKit (iOS widgets + watchOS complications)
- XcodeGen (`project.yml` → `.xcodeproj`)
- Targets: iOS 26.0, watchOS 26.0

## Build & Run

```bash
# Regenerate Xcode project (required after any project.yml or file structure change)
xcodegen generate

# Build from CLI
xcodebuild -project Vitals.xcodeproj -scheme Vitals -destination 'generic/platform=iOS' build

# Deploy: open Vitals.xcodeproj in Xcode, select Vitals scheme, run on device

# TestFlight (upload uses AppStoreUploadOptions.plist + Xcode’s App Store Connect login)
./scripts/testflight.sh
# Or upload an existing archive: ./scripts/upload-testflight.sh [build/Vitals.xcarchive]
# API key upload: ./scripts/upload-testflight-api.sh (see script header)
```

Always run `xcodegen generate` after adding/removing Swift files or changing `project.yml`.

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

### Directory Layout

```
Shared/                          # Business logic shared by all targets
  Models/HealthRecord.swift      # @Model DailyHealthRecord (SwiftData)
  Services/HealthKitService.swift # HK auth, queries, background delivery, pacing
  Services/DataService.swift     # SwiftData container + App Group setup
  Services/GoalSettings.swift    # User prefs (goals, appearance, toggles)
  Utilities/Theme.swift          # Colors, gradients, typography (iOS/watchOS adaptive)
  Utilities/DateHelpers.swift    # Date normalization utilities

Vitals/                          # iOS app (thin UI shell)
  App.swift                      # Entry point, TabView (Dashboard + History)
  Views/DashboardView.swift      # Today view: ring, counters, pacing, onboarding, settings
  Views/HistoryView.swift        # Charts, trends, periods (7D/30D/90D/1Y/Custom), CSV export
  Views/Components/ProgressRing.swift  # Circular ring + step progress bar

VitalsWidget/VitalsWidget.swift  # iOS widget: small, medium, lock screen circular/rectangular
VitalsWatch/                     # watchOS: App.swift + Views/TodayView.swift
VitalsWatchWidget/WatchComplication.swift  # Watch: circular, rectangular, inline, corner
```

### Data Flow

```
HealthKit  →  HealthKitService  →  SwiftData (DailyHealthRecord)
                                        ↓
                              App UI + Widgets read from SwiftData

GoalSettings  →  UserDefaults (App Group)  →  Widgets read goals directly
```

- **App Group**: `group.com.jackwallner.vitals` — shared container for SwiftData + UserDefaults
- **Widgets can't query HealthKit** — they read cached data from SwiftData
- **Background delivery**: `HKObserverQuery` fires hourly → updates SwiftData → reloads widget timelines

### Key Services

**HealthKitService** (singleton, `@MainActor`):
- `fetchTodayStats()` → `(active: Double, resting: Double, steps: Int)`
- `fetchHistory(days:)` / `fetchHistory(from:to:)` → array of daily records
- `fetchPacing(comparison:lookback:)` → rolling average at current hour/minute (default 30 days, same weekday)
- `refreshCache()` → updates SwiftData + triggers widget reload

**GoalSettings** (singleton, `@MainActor`, `ObservableObject`):
- `calorieGoal: Double?` / `stepGoal: Int?` — nil = no goal (counter-only mode)
- `showPacing`, `showCalories`, `showSteps` — display toggles
- `hasCompletedSetup` — first-launch onboarding flag
- `appearance: AppAppearance` — system/light/dark

**DataService** (enum):
- `appGroupID` = `"group.com.jackwallner.vitals"`
- `sharedModelContainer` — SwiftData container using app group URL

### Theme System

- `Theme.swift` uses `#if os(watchOS)` for platform-adaptive colors
- iOS: semantic system colors (`Color(.systemBackground)`, etc.)
- watchOS: hardcoded dark values (no UIKit semantic colors)
- Palette: coral/orange for calories, teal/cyan for steps
- `Theme.bigNumber(_:)` returns `.system(size:weight:design:)` with `.rounded`

## Signing

- **Team ID**: `YXG4MP6W39` (OU field from certificate, NOT serial number)
- **Signing Identity**: Apple Development: jackwallner@gmail.com
- Free Apple Developer account (max 3 apps installed at once)
- Code signing is automatic — set in `project.yml` base settings
- After `xcodegen generate`, signing team persists (no manual re-selection needed if `DEVELOPMENT_TEAM` is set correctly)

## Gotchas

- **`UILaunchScreen` required**: `Vitals/Info.plist` must have `<key>UILaunchScreen</key><dict/>` or the app renders in letterboxed compatibility mode
- **Widget app group access**: Widgets use module-level `vitalsAppGroupID` constant (defined in `DataService.swift`) since `DataService` itself is `@MainActor`
- **watchOS Theme**: No `Color(.systemBackground)` on watchOS — use `#if os(watchOS)` conditional
- **Bundle IDs**: Keep them short — free dev accounts reject deeply nested IDs (e.g., `vitals.watchapp.complication` was rejected, `vitals.watch.widget` works)
- **Swift 6 concurrency**: HK callbacks need `@Sendable` closures or async wrappers
- **Watch companion**: `WKCompanionAppBundleIdentifier` in `VitalsWatch/Info.plist` must match the iOS app's bundle ID exactly
- **File changes**: After adding/removing any `.swift` file, must run `xcodegen generate` or the file won't be in the Xcode project

## User Preferences (GoalSettings keys in UserDefaults)

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `hasCompletedSetup` | Bool | false | First-launch onboarding gate |
| `calorieGoalEnabled` | Bool | true | Whether calorie goal is active |
| `calorieGoal` | Double | 2500 | Daily calorie target |
| `stepGoalEnabled` | Bool | true | Whether step goal is active |
| `stepGoal` | Int | 10000 | Daily step target |
| `showPacing` | Bool | true | Show pace vs rolling average (default 30 days, same weekday) |
| `showCalories` | Bool | true | Display calories section |
| `showSteps` | Bool | true | Display steps section |
| `appearance` | Int | 0 | 0=system, 1=light, 2=dark |

## App Store reviews (5★ strategy)

- Cross-app playbook: `~/Desktop/app-store-5-star-review-strategy.md` — say **"go"** with that file to apply the same funnel in another app.
- Vitals: enjoyment funnel after **daily goal hit**; explicit Rate → `AppStoreReviewLinks.writeReviewURL`; `requestReview()` only after Yes + "Maybe later" dismiss.

## Astro ASO

- **Full setup (any app):** say **"go"** with `docs/astro-setup-process.md` — ASC pull + Astro keywords
- One-command: `./scripts/astro-setup.sh` (add `--extra "phrase"` for app-specific terms)
- Local MCP: `http://127.0.0.1:8089/mcp` (Astro app must be running)
- App snapshot: `docs/astro-aso-setup.md` | Process playbook: `docs/astro-setup-process.md`
- Pull ASC metadata: `./scripts/pull-appstore-metadata.sh`
- Re-sync keywords only: `./scripts/sync-astro-keywords.sh`

## Scripts

- `scripts/testflight.sh` — push to TestFlight / ship a build
- `scripts/upload-testflight.sh [build/Vitals.xcarchive]` — upload existing archive (.ipa) only
- `scripts/upload-testflight-api.sh` — API-key based upload (see script header)
- `scripts/pull-appstore-metadata.sh` — snapshots `fastlane/metadata/` to `metadata.bak.<timestamp>/`, then runs `fastlane deliver download_metadata`. ALWAYS run before editing `fastlane/metadata/*.txt`; diff against the snapshot to confirm what changed remotely.
- `scripts/upload-appstore-metadata.sh` — `fastlane upload_metadata` (screenshots + listing copy, no binary, no submit-for-review).

ASC API key (shared across apps): `~/.baseball_credentials` (`ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`).

## App Store Submission

- **Privacy policy**: `docs/privacy-policy.html` — host via GitHub Pages at `https://jackwallner.github.io/vitals/privacy-policy.html`
- **Privacy manifest**: `Vitals/PrivacyInfo.xcprivacy` and `VitalsWatch/PrivacyInfo.xcprivacy`
- **App Store metadata**: `docs/app-store-metadata.md` — description, keywords, review notes
- **Required device capabilities**: `healthkit` declared in `Vitals/Info.plist`
- **Accessibility**: VoiceOver labels on all interactive elements (ring, charts, metrics, pacing pills)
- **Goal validation**: Calories 500-50,000, steps 100-500,000
- **HealthKit denied state**: Shows guidance + Settings link when permissions denied
