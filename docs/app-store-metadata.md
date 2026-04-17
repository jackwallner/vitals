# App Store Connect — Total Calories

All fields below map directly to App Store Connect. Copy-paste each value into the corresponding field.

---

## App Information

| Field | Value |
|-------|-------|
| App Name | `Total Calories - Daily Tracker` |
| Subtitle | `Burned Calories & Step Count` |
| Primary Language | English (U.S.) |
| Category | Health & Fitness |
| Secondary Category | Lifestyle |
| Content Rights | Does not contain, show, or access third-party content |
| Age Rating | 9+ (no objectionable content) |
| Price | Free |
| Copyright | `2026 Jack Wallner` |

App Name is exactly 30 characters (the maximum). Subtitle is 28/30.

---

## Description

Plain text only — no markdown, no HTML. Copy everything between the lines below.

---COPY START---

Track your total daily calories burned and steps at a glance. Total Calories reads your data directly from Apple Health and keeps everything on your device. No accounts, no servers, no tracking.

CALORIES & STEPS
See your total calories burned — active plus resting — and your daily step count on one clean dashboard. Tap the calorie total to reveal the active vs. resting breakdown.

GOALS & PROGRESS RINGS
Set optional daily calorie and step goals. Watch your progress fill up with animated rings and progress bars. Or skip goals entirely and use it as a simple counter.

PACING
A built-in pace indicator compares your current day to your 30-day average at the same time of day. Know whether you're ahead or behind your usual pace.

HISTORY & TRENDS
View your full history: 7 days, 30 days, 90 days, 1 year, or any custom date range. See trend arrows, peak days, and export your data as a CSV file.

WIDGETS & COMPLICATIONS
Home screen and lock screen widgets show your calories and steps without opening the app. Apple Watch face complications keep your data visible all day.

PRIVATE BY DESIGN
All data stays on your device. No analytics, no ads, no servers, no account required. Read-only Apple Health access — the app never writes to your health records.

Total Calories is not a medical device and is not intended to diagnose, treat, or prevent any medical condition. Always consult a healthcare professional for medical advice.

---COPY END---

The first sentence (visible "above the fold" before users tap "Read More") leads with the core value proposition and mentions Apple Health for discoverability. Description is ~1,350 characters (well under the 4,000 limit).

---

## Promotional Text

Can be updated anytime without a new app version. Not indexed for search. 170 character max.

```
See your total calories burned and steps in one place. Private, simple, always up to date from Apple Health.
```

109/170 characters.

**Alternate (mentions widgets + Watch):**

```
Home screen widgets, Apple Watch complications, and a clean dashboard — all from Apple Health, all on device.
```

155/170 characters.

---

## Keywords

100 characters max. Comma-separated, no spaces after commas. Words from the App Name and Subtitle are already indexed — do NOT repeat them here.

**Already indexed from name/subtitle:** total, calories, daily, tracker, burned, step, count

```
health,fitness,pedometer,activity,widget,watch,energy,exercise,walking,progress,goal,ring,TDEE,BMR
```

98/100 characters. All terms are unique and not in the name/subtitle.

---

## What's New (Version 1.1.0)

Paste into **What’s New in This Version** (plain text, no markdown). This list covers **everything user-facing since 1.0.0** (git history through current `main`, including reliability work after the initial launch).

**Full notes** (~1,900 characters — under the 4,000 limit):

---COPY START---

What’s new since 1.0.0

Reliability & Apple Health
• Fixes a rare crash during background refresh.
• Better handling when connecting to Apple Health — authorization is coordinated with onboarding and refresh, so data loads more predictably.
• Today’s calories and steps use the same daily totals logic as the History tab, so the dashboard and charts stay consistent.
• Clearer messages when Health access is still needed, data is still syncing, or a refresh failed (instead of silent empty screens).

Today & History
• Pull down on Today to refresh; the screen shows when values were last updated.
• History remembers your last period (7 / 30 / 90 / 365 days or a custom range) across launches.
• History has improved error handling with retry when a load fails.

Widgets, Lock Screen & Apple Watch
• Home screen widgets, lock screen widgets, and watch complications respect which metrics you’ve turned on in Settings.
• Widgets and complications show goal-style progress when you use goals, and scale better when only one metric is visible.
• Calorie and step goals set on iPhone sync to Apple Watch for a consistent experience.

Other
• Optional coaching discovery (E3 Fitness) appears in Settings and History if you want to explore training services.
• Privacy policy and support pages updated on the web site linked from the app.

---COPY END---

**Short notes** (if you prefer a compact App Store blurb):

---COPY SHORT START---

• Fixes background-refresh stability and Health loading edge cases.
• Today’s totals now match History; pull to refresh on Today.
• History remembers your chart period; better errors with retry.
• Widgets & Watch complications respect your toggles and goals; goals sync phone ↔ watch.
• Clearer Health permission and status messages.

---COPY SHORT END---

## What's New (Version 1.0.0) — archive

```
Initial release.
```

---

## URLs

| Field | Value |
|-------|-------|
| Support URL | `https://jackwallner.github.io/vitals/support.html` |
| Privacy Policy URL | `https://jackwallner.github.io/vitals/privacy-policy.html` |
| Marketing URL | _(leave blank)_ |

Verify both URLs return 200 before submitting. See GitHub Pages setup at the bottom of this file.

---

## App Privacy (App Store Connect > App Privacy)

### Do you or your third-party partners collect data from this app?

**No.**

The app reads HealthKit data and caches it locally via SwiftData. No data is transmitted off the device. On-device-only processing does not count as "collection" per Apple's privacy guidelines.

### Does this app track users?

**No.**

If Apple requires you to declare HealthKit under "Health & Fitness" data:

| Data Type | Collected? | Purpose | Linked to Identity | Used for Tracking |
|-----------|-----------|---------|-------------------|-------------------|
| Health & Fitness | Not Collected | App Functionality | No | No |

---

## App Review

### Contact Information

| Field | Value |
|-------|-------|
| First Name | Jack |
| Last Name | Wallner |
| Email | jackwallner@gmail.com |
| Phone | _(enter your phone number)_ |

### Sign-In Required

**No** — the app does not have user accounts or sign-in.

### Notes for Review

Copy everything between the lines below into the "Notes" field.

---COPY START---

Total Calories reads calorie and step data from Apple Health (HealthKit) in read-only mode. It does not write to HealthKit. All data is stored locally — no server, no accounts, no data collection.

HEALTHKIT SETUP — PLEASE GRANT ACCESS WHEN PROMPTED

On first launch, the app asks you to set optional goals (you may skip this). iOS then prompts for HealthKit read access. Please allow all three types:

- Active Energy Burned
- Basal Energy Burned
- Step Count

If access is denied or not yet granted, the app shows a banner explaining that Health access is needed (no fake or placeholder health numbers). Users can open Settings or the Health app from that banner.

iPHONE FEATURES

- Dashboard with animated calorie ring and step progress bar
- Tap to reveal active vs. resting calorie breakdown
- Pacing indicator: current day vs. configurable rolling average (default: 30 days, same weekday) at the same time of day
- History tab: bar charts for 7D / 30D / 90D / 1Y / custom range
- Trend arrows and peak day highlights
- CSV data export
- Home screen widgets (small, medium) and lock screen widgets (circular, rectangular)
- Settings: goals, display toggles, appearance (system / light / dark)

APPLE WATCH

The watch experience is delivered primarily through watch face complications (circular, rectangular, inline, corner). These show live calorie and step data. The companion watch app provides a today view and serves as the complication container.

PRIVACY

- Read-only HealthKit (never writes)
- No data leaves the device
- No analytics, ads, tracking, or third-party SDKs
- No network requests of any kind
- Privacy Policy: https://jackwallner.github.io/vitals/privacy-policy.html

Privacy Policy and Support links are accessible in the iPhone Settings sheet and Apple Watch Help sheet.

---COPY END---

### Attachment (optional)

If available, attach a short screen recording showing the dashboard, history tab, and a widget on the home screen. This helps reviewers see the full experience without needing their own health data.

---

## Screenshots Required

### iPhone 6.5" Display (Media Manager slot)

App Store Connect only accepts **exact** pixel sizes for this slot, for example:

- **Portrait:** `1284 × 2778` or `1242 × 2688`
- **Landscape:** `2778 × 1284` or `2688 × 1242`

**Best source:** Xcode **Simulator** → choose a 6.5" class phone (e.g. iPhone 14 Pro Max / 16 Pro Max) → run the app → **File → Save Screen** (saves correct dimensions). Or full-resolution PNGs from a physical device export (Photos → Share → Save to Files), then resize if needed.

**Resize tool (repo):** from the project root, with Pillow installed (`pip3 install Pillow`):

```bash
python3 scripts/letterbox_app_store_iphone65.py --out ./build/app_store_iphone65 ~/path/to/raw-screenshots/*.png
```

Outputs **1284×2778** letterboxed PNGs App Store Connect accepts. Use **high-resolution** sources — upscaling small thumbnails looks blurry in the store.

### iPhone 6.7" (required)

Device: iPhone 15 Pro Max or 17 Pro Max

1. Dashboard with calorie ring and steps card (goals enabled)
2. History view with 30-day chart and trend cards
3. Dashboard in minimal / counter-only mode
4. Settings sheet showing goal toggles and appearance
5. Onboarding / welcome screen

Lead with the dashboard screenshot — it shows the most functionality at a glance.

### iPhone 6.1" (optional but recommended)

Same 5 screenshots at 6.1" resolution (iPhone 15 Pro or 17 Pro).

### Apple Watch (required)

Device: Apple Watch Ultra 2 or Series 10

1. Today view showing calories and steps
2. Calorie breakdown overlay (active + resting)
3. Help / support screen

Optional: complication shown on a watch face.

---

## Pre-Submission Checklist

- [ ] Privacy policy URL returns 200
- [ ] Support URL returns 200
- [ ] HealthKit usage descriptions are specific in both Info.plist files
- [ ] App handles denied HealthKit permissions (guidance + Settings link)
- [ ] App handles empty Health data without crashing
- [ ] No health data stored in iCloud
- [ ] App Privacy declarations completed in App Store Connect
- [ ] Medical disclaimer in description
- [ ] All required screenshot sizes uploaded
- [ ] Review notes entered with HealthKit instructions
- [ ] Phone number entered in review contact info
- [ ] Build uploaded and selected for this version

---

## GitHub Pages Setup (for Support + Privacy URLs)

1. Push the `docs/` folder to the `main` branch on GitHub
2. Go to github.com/jackwallner/vitals > Settings > Pages
3. Source: "Deploy from a branch" > `main` > `/docs`
4. Save — pages will be live at:
   - https://jackwallner.github.io/vitals/privacy-policy.html
   - https://jackwallner.github.io/vitals/support.html
5. Wait 1-2 minutes, then verify both URLs load correctly
