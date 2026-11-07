---
name: vitals-architecture
description: Detailed Vitals app architecture — directory layout, data flow, key services (HealthKitService/GoalSettings/DataService), and the theme system. Load before working on Vitals internals (services, widgets, data flow, HealthKit).
---

# Vitals — detailed architecture

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

### User Preferences (GoalSettings keys in UserDefaults)

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
