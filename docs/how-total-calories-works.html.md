# How Total Calories Counts Calories Burned: Methodology

> How Total Calories works out your daily burn: which Apple Health and Health Connect records it reads, how it adds them, and where the numbers come from.

Web page: https://jackwallner.com/ios/vitals/how-total-calories-works.html

## How Total Calories counts your calories burned

Last updated October 30, 2026

Total Calories does not estimate your burn itself. It reads the energy records your watch and phone already write to Apple Health or Health Connect, adds active and resting energy for the day, and shows the result. This page explains exactly which records it reads and how the math works.

## What it reads

- **iPhone and Apple Watch:** Active Energy, Resting Energy and Steps from Apple Health. If you open the body profile, it reads height and weight for BMI. With Vitals+ net deficit or macros turned on, it also reads the dietary energy and macros another app logs to Health.
- **Android:** active calories, total calories, basal metabolic rate and steps from Health Connect.

Every permission is read-only. The app never writes to Health, has no account and keeps your data on your device.

## How the daily total is calculated

total calories = Active Energy + Resting Energy
for each day, midnight to now

- Each field is summed with Apple Health's statistics query. When two sources record the same minutes, such as your iPhone and your Apple Watch, Health merges them using your source priority instead of counting them twice.
- Days are bucketed by your local midnight. A sample that crosses midnight, such as a late workout, is split between the two days by time, so Today and History always agree.
- If Steps permission is off, calories still show; steps are optional.

## Where the numbers come from

Resting energy is Apple's estimate of your basal metabolism, computed from the weight, height, age and sex in your Health profile. Active energy comes from motion and heart rate. In Apple's lab tests against a metabolic cart, workout calories averaged near zero error with a spread of about 9 to 20% by activity, and Apple publishes no accuracy figure for resting energy. Total Calories passes those numbers through unchanged, so your total matches what you get by adding the two rows in the Health app. [More on accuracy](https://jackwallner.com/ios/vitals/apple-watch-active-vs-resting-calories.html).

## Tested on 30,000+ data points

Total Calories is built and checked against its developer's own Apple Watch history: more than 30,000 step data points, compared with the totals in the Health app. Since its April 2026 launch it has passed 2,900 downloads and averages 4.9 stars across 22 App Store ratings worldwide.

## Averages: TDEE and BMR (Vitals+)

TDEE is your average daily total over the last 30 days of your own data, and BMR is your average resting energy over the same days. Days you exclude, such as a sick day or a day the watch stayed on the charger, are left out of every average, total and streak.

## Keeping the numbers useful

- Keep your weight current in Health; resting energy is computed from it.
- Wear the watch all day so active energy includes walking and chores.
- Use a 7-day or 30-day average for decisions. Any single day is noisy.

Total Calories is a personal tracking tool, not a medical device. Informational only, not medical advice.

## Common questions

### How does Total Calories calculate calories burned?

It adds Active Energy and Resting Energy from Apple Health for each day, from midnight to now. On Android it reads the same records from Health Connect.

### Does Total Calories double count my iPhone and Apple Watch?

No. It uses Apple Health's statistics query, which merges overlapping sources by your source priority, the same way the Health app does.

### Will the total match the Health app?

It should. It reads the same records, so it matches the sum of the Active Energy and Resting Energy rows in the Health app for the same day.

### Related guides

[Active vs resting calories on Apple Watch](https://jackwallner.com/ios/vitals/apple-watch-active-vs-resting-calories.html)[TDEE calculator](https://jackwallner.com/ios/vitals/tdee-calculator.html)

## See your real burn, counted the same way Health does

Total Calories reads active and resting energy from Apple Health or Health Connect and shows your daily total. Free to start, no account.

[Download Total Calories](https://apps.apple.com/us/app/total-calories-daily-tracker/id6761743504?pt=128748779&ct=jw-vitals-methodology&mt=8)
