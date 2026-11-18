---
paths:
  - "Shared/Utilities/JanuaryChallenge.swift"
  - "Vitals/Views/JanuaryChallengeView.swift"
  - "VitalsUITests/JanuaryChallengeUITests.swift"
---

# Total Calories: New Year Goal Challenge 2027 (added 2026-11-18)

The real, dated thing behind the App Store in-app event "New Year Goal
Challenge" (January 1 to 31, 2027; App Review 2.3.13 wants an event to be
timely and its link to land on it). Event spec, art and state:
`~/ios/growth/2026-11-18-listing-strategy/january-events/`.

- `JanuaryChallenge` (Shared) is pure date math over January's Health history.
  A goal day is one where the calorie goal or the step goal was reached, the
  same rule as `MilestoneCalculator.currentGoalStreak`.
- Today shows the row from December 18, 2026 (the day the App Store starts
  promoting the event) to February 7, 2027, when no prompt or Health notice is
  up. The sheet shows the count and the month. Nothing in it is paid.
- `totalcalories://challenge` (`DeepLink.challenge`) opens the sheet on Today.
  A link that arrives before setup is done waits for it. From February 8, 2027
  the link just opens Today.
- DEBUG launch args: `-challengeNow 2027-01-12` sets the date the challenge
  reads, `-openChallenge` does what the link does. In screenshot mode the month
  comes from `ScreenshotFixtures.challengeHistory`. UI tests:
  `VitalsUITests/JanuaryChallengeUITests` under the `VitalsUITests` scheme.
- After February 2027 the code can be removed, or re-dated for the next
  January: change `year` and the three catalog keys.
