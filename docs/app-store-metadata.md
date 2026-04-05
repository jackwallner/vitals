# App Store Metadata — Vitals

## App Information

- **App Name:** Vitals
- **Subtitle:** Calories & Steps Tracker
- **Category:** Health & Fitness
- **Secondary Category:** Lifestyle
- **Age Rating:** 9+
- **Price:** Free
- **Copyright:** 2026 Jack Wallner

## Description

Track your daily calories burned and steps — simply and privately.

Vitals gives you a clean, glanceable view of your daily health metrics pulled directly from Apple Health. No accounts, no cloud sync, no tracking. Just your data, on your device.

Features:
- Total calories burned (active + resting) with tap-to-reveal breakdown
- Daily step count with optional goals and progress rings
- Pacing indicator showing how you compare to your 14-day average at this time of day
- History charts with 7-day, 30-day, 90-day, 1-year, and custom date range views
- Trend analysis and peak day highlights
- CSV export for your records
- Home screen and lock screen widgets
- Apple Watch app with complications for your watch face
- Light, dark, and system appearance options
- First-launch setup to configure your goals — or skip for a pure counter experience

Your health data never leaves your device. No analytics. No ads. No servers.

## Keywords

health, fitness, calories, steps, tracker, pedometer, activity, healthkit, widget, watch

## What's New (Version 1.0.0)

Initial release.

## Support URL

https://jackwallner.github.io/vitals/support.html

## Privacy Policy URL

https://jackwallner.github.io/vitals/privacy-policy.html

(Host the `docs/` folder via GitHub Pages — see instructions below)

## Screenshots Needed

### iPhone (6.7" display — iPhone 15 Pro Max / 17 Pro Max)
1. Dashboard with calorie ring and steps card (data populated)
2. Dashboard in minimal mode (no goals, clean counters)
3. History view with 30-day chart and trend cards
4. Settings sheet showing goal toggles and appearance
5. Onboarding / welcome screen

### iPhone (6.1" display — iPhone 15 Pro / 17 Pro)
Same 5 screenshots at smaller resolution.

### Apple Watch (Ultra 2)
1. Today view showing calories and steps
2. Complication on watch face (circular calories gauge)
3. Complication on watch face (rectangular steps)

## How to Publish Support + Privacy Pages via GitHub Pages

1. Push the `docs/` folder to the `main` branch on GitHub
2. Go to github.com/jackwallner/vitals → Settings → Pages
3. Set Source to "Deploy from a branch" → `main` → `/docs`
4. Save — your pages will be at:
   - https://jackwallner.github.io/vitals/privacy-policy.html
   - https://jackwallner.github.io/vitals/support.html

## App Review Notes (optional, for Apple reviewer)

Vitals is a personal health tracker that reads calorie and step data from HealthKit. It does not write to HealthKit. All data is stored locally on the device — there is no server component, no user accounts, and no data collection. The app requires HealthKit access to function; without it, an explanatory screen guides the user to enable access in Settings. Privacy Policy and Support links are available in the Settings sheet inside the app.
