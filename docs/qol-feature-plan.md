# QOL Feature Implementation Plan

Small quality-of-life improvements for `Vitals` that keep the core app behavior the same:

- HealthKit remains read-only.
- SwiftData remains the local cache and widget data source.
- The main product stays focused on total calories, steps, goals, pacing, history, widgets, and watch glanceability.

## Product guardrails

- Do not add accounts, sync, social features, coaching, or anything that changes the app from a simple personal tracker.
- Prefer clarity, trust, and convenience improvements over new data models.
- Reuse existing surfaces before adding entirely new ones.
- Keep first-pass work low risk and easy to ship incrementally.

## Recommended release order

### Release 1: Trust and clarity

1. Today pull-to-refresh plus last updated status
2. History failure state plus retry
3. Discoverable calorie breakdown affordance

### Release 2: State polish

4. Persist history period and custom range
5. Replace generic sample-data fallback with clearer empty and permission states

### Release 3: Cross-surface consistency

6. Widget and watch preference parity
7. Settings and onboarding polish

---

## 1. Today pull-to-refresh plus last updated status

**Priority:** High

**Why this is worth doing**

The Today screen is the most important surface in the app, but it currently relies on foreground refreshes, settings dismissals, and background delivery. Users have no obvious manual refresh path and no quick way to tell whether the displayed numbers are fresh.

**What would change**

- Wrap the Today content in a scrollable container that supports `.refreshable`.
- Keep the current inline refresh spinner.
- Add a subtle status line near the date header:
  - `Updated 9:41 AM`
  - `Refreshing...`
  - `Using sample data`
- Prefer real cache metadata where possible:
  - short term: store a local `lastRefreshDate` in `DashboardView`
  - better long term: read from `DailyHealthRecord.lastUpdated`

**Likely files**

- `Vitals/Views/DashboardView.swift`
- `Shared/Models/HealthRecord.swift` if any display-friendly helper is added
- `Shared/Services/HealthKitService.swift` only if refresh metadata is surfaced more explicitly

**Positive for users**

- They can force a refresh when the numbers feel stale.
- The app feels more trustworthy because freshness is visible.
- The app becomes easier to understand after workouts, walks, or delayed Health updates.

**Negative for users**

- The Today screen may feel slightly less static if it becomes pull-to-refresh driven.
- Some refreshes will not visibly change the values because Apple Health may not have new samples yet.
- A status line adds a small amount of visual density to a minimal screen.

**Implementation notes**

- Keep the pull gesture lightweight so it does not fight the custom tab bar layout.
- If scroll behavior feels awkward, allow just enough vertical bounce to expose refresh without making the screen feel like a feed.

**Done looks like**

- User can pull down on Today to refresh.
- Header shows a useful freshness state after refresh.
- No layout regressions in goal and no-goal modes.

---

## 2. History failure state plus retry

**Priority:** High

**Why this is worth doing**

History currently logs errors but does not tell the user when loading failed. That can make failed refreshes look like empty data, stale data, or a bug in HealthKit.

**What would change**

- Add a visible inline error card or banner in `HistoryView`.
- Differentiate between:
  - first load failed
  - refresh failed but old records still exist
- Add a `Retry` action that calls `loadHistory()` again.
- Preserve the existing charts and export flow when cached records are still available.

**Likely files**

- `Vitals/Views/HistoryView.swift`

**Positive for users**

- Users know when data failed to load instead of assuming their history disappeared.
- Retry gives them a simple recovery path.
- The app feels more stable and honest.

**Negative for users**

- Transient HealthKit issues become more visible.
- This adds one more state to the screen, which slightly increases UI complexity.

**Implementation notes**

- Avoid modal alerts for routine load failures.
- An inline card above the charts is less disruptive and works better with pull-to-refresh.
- If records already exist, keep them on screen and label them as stale rather than clearing them.

**Done looks like**

- First-load failures show a dedicated failure state.
- Refresh failures preserve prior data and show retry UI.
- No case exists where a failed load silently looks like true empty history.

---

## 3. Discoverable calorie breakdown affordance

**Priority:** High

**Why this is worth doing**

The calorie breakdown feature already exists, but the collapsed control is almost invisible. That means a useful detail view is hidden behind an interaction users may never discover.

**What would change**

- Replace the empty collapsed button with a visible row:
  - `Show active/resting breakdown`
  - chevron indicating expandable behavior
- When expanded, keep the existing pills and add a clear collapse affordance.
- Optionally add a very small watch hint only if it fits the current layout cleanly.

**Likely files**

- `Vitals/Views/DashboardView.swift`
- `VitalsWatch/Views/TodayView.swift` only if watch discoverability is also adjusted

**Positive for users**

- Existing functionality becomes discoverable without a tutorial.
- Users understand that total calories include active and resting energy.
- The app communicates more of its value immediately.

**Negative for users**

- The screen becomes a little less minimal.
- Some users who never care about the breakdown will see one more row on Today.

**Implementation notes**

- Keep the control visually quiet.
- Do not let the affordance compete with the ring or steps card.

**Done looks like**

- A first-time user can tell the calorie section is expandable.
- Expanded and collapsed states are visually obvious.

---

## 4. Persist history period and custom range

**Priority:** Medium

**Why this is worth doing**

Users who repeatedly check `30D`, `90D`, or a custom date range have to reselect it every time. Remembering their last view makes History feel more personal and less repetitive.

**What would change**

- Store the selected history period in `UserDefaults`.
- Store custom start and end dates.
- Restore the last state on app launch.
- When `Custom` is active, show the actual date span somewhere visible:
  - in a label below the segmented control
  - or inside the selected card header

**Likely files**

- `Vitals/Views/HistoryView.swift`
- `Shared/Services/GoalSettings.swift` if history preferences are folded into the same settings store
- or a new lightweight preferences helper under `Shared/`

**Positive for users**

- Fewer repeated taps.
- Better continuity between sessions.
- Custom ranges become much more usable.

**Negative for users**

- Users may forget they left History on an old custom range.
- Persisted state can make the screen feel surprising if the current range is not obvious.

**Implementation notes**

- If this ships, the active range must be visible at a glance.
- Keep persistence local only and simple.

**Done looks like**

- Reopening the app restores the last History view.
- Custom range users can immediately tell which dates they are viewing.

---

## 5. Replace generic sample-data fallback with clearer empty and permission states

**Priority:** Medium

**Why this is worth doing**

Right now an all-zero result often turns into sample data. That helps demo the app, but it can blur together several very different realities:

- no Health access yet
- user truly has no data yet
- temporary fetch issue
- the user simply has very little activity recorded

**What would change**

- Keep screenshot and preview fixtures for debug flows only.
- In production UI, distinguish these states more clearly:
  - `Health access needed`
  - `No data yet today`
  - `Couldn't refresh right now`
- Replace fake numbers with real empty-state UI where practical.
- Keep the existing helpful actions:
  - open Health
  - open Settings
  - support links where appropriate

**Likely files**

- `Vitals/Views/DashboardView.swift`
- `VitalsWatch/Views/TodayView.swift`
- `Shared/Services/HealthKitService.swift` if state helpers are introduced

**Positive for users**

- The app feels more honest.
- New users better understand what is happening.
- Permission issues are easier to resolve.

**Negative for users**

- The first-use experience may feel less visually exciting because fake numbers are removed.
- HealthKit does not expose every permission detail cleanly, so some messaging will still be best-effort.

**Implementation notes**

- Avoid overengineering authorization state if HealthKit APIs do not support exact certainty.
- Even without perfect granularity, clearer copy is better than demo numbers in most cases.

**Done looks like**

- Production UI no longer uses fake numbers as the default response to zero data.
- Empty, denied, and transient failure states feel distinct.

---

## 6. Widget and watch preference parity

**Priority:** Medium

**Why this is worth doing**

The app lets users hide calories or steps, but widgets and complications mostly ignore those choices. That makes the app feel inconsistent across surfaces.

**What would change**

- Extend widget and watch entry generation to read:
  - `showCalories`
  - `showSteps`
- Trigger `WidgetCenter.shared.reloadAllTimelines()` when those toggles change.
- Adjust widget layouts so they still look intentional when only one metric is enabled.
- Optionally surface freshness metadata like `Updated 9:41 AM` where space allows.

**Likely files**

- `Shared/Services/GoalSettings.swift`
- `VitalsWidget/VitalsWidget.swift`
- `VitalsWatchWidget/WatchComplication.swift`
- possibly a new shared helper in `Shared/` for reading app group widget preferences

**Positive for users**

- Widgets and watch surfaces feel aligned with the app.
- Hidden metrics actually stay hidden everywhere.
- The app feels more polished and intentional.

**Negative for users**

- Small widget families may feel sparse with only one metric enabled.
- If both metrics are hidden, a strict interpretation may produce an empty-looking widget.

**Implementation notes**

- Add sensible fallback behavior if both metrics are disabled.
- While doing this, remove duplicated goal-loading logic from widget targets and centralize it.

**Done looks like**

- App display preferences are reflected on widgets and complications.
- Toggle changes refresh widget timelines quickly.

---

## 7. Settings and onboarding polish

**Priority:** Medium

**Why this is worth doing**

The current settings flow works, but it can drop edits on cancel and onboarding still carries older `Total Calories` branding in places. Small polish here improves perceived quality without changing functionality.

**What would change**

- Add unsaved-changes confirmation to `SettingsSheet` when the form has been edited.
- Add a clearer secondary onboarding action:
  - `No goals for now`
  - or `Use as simple counter`
- Rename onboarding copy from `Total Calories` to `Vitals` if that is the intended product name going forward.
- Keep the same goal validation ranges and storage model.

**Likely files**

- `Vitals/Views/DashboardView.swift`
- `docs/app-store-metadata.md` only if branding language should also be aligned later

**Positive for users**

- Fewer accidental lost edits.
- Faster and clearer first-run setup.
- Less branding mismatch.

**Negative for users**

- Unsaved changes confirmation adds one more tap when dismissing edited settings.
- Onboarding gets slightly busier if another button is added.

**Implementation notes**

- Use a lightweight dirty-state check instead of building a complex form model.
- Keep onboarding short and do not add extra screens.

**Done looks like**

- Canceling settings after edits prompts before discarding changes.
- Onboarding has an obvious no-goal path.
- Branding is consistent within the app flow.

---

## Suggested coding sequence

1. Update `DashboardView.swift` for refresh trust and breakdown discoverability.
2. Update `HistoryView.swift` for error handling and state persistence.
3. Revisit production empty and permission handling in iPhone and watch views.
4. Add shared widget preference plumbing and update widget and complication layouts.
5. Finish with settings and onboarding polish.

## Suggested validation

- Manual test Today with:
  - goals enabled
  - goals disabled
  - calories hidden
  - steps hidden
  - both hidden
- Manual test History with:
  - normal data load
  - custom range
  - app relaunch after selecting custom range
  - simulated fetch failure if possible
- Manual test widgets and watch after toggling display settings.
- Verify no changes to HealthKit scopes, cache model, or app group behavior.

## Ideas to defer for now

- Haptics for goal completion
- More aggressive widget timeline refresh cadence
- Additional complication families or alternate dashboard layouts
- New analytics cards or more trend math

These are reasonable ideas, but they are lower value than clarity, trust, and consistency work.
