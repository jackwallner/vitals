# Screenshot audit: total-calories

Status: **PASS**
Disposition: **STAGED**
Target: `iphone_65` at `1284x2778`
Capture status: `ok`

This report combines file-spec checks with an independent thumbnail and OCR pass. Open each `contact-sheet.png` and `search-grid.png` before approving a set.

## Warnings

- net-deficit-led: 08-go-further.png: thumbnail OCR missed header words ['further']

## Market brief

- Category: Apple Watch calorie and macro trackers
- Audience: People who want total burn, food intake, and macros in one private daily view
- Problem: Apple Health separates total burn from food intake, so the relationship between burned calories, eaten calories, and macros is easy to miss.
- Advantage: Total Calories combines active plus resting burn with logged food, net deficit, protein, carbs, and fat, then puts the daily number on the wrist.
- Competitive context: The app connects burn and intake without an account, a social feed, or a crowded food diary, while keeping the daily check-in glanceable on iPhone and Apple Watch.

## Sets

| Set | Status | Frames |
| --- | --- | ---: |
| `calorie-intake-led` | pass | 8 |
| `net-deficit-led` | pass | 8 |

## Review contract

- Contract: `single-header-benefit-story-v3`.
- Every creative frame has exactly one large, period-free header capped at two lines. Eyebrows and subheaders are forbidden.
- Phone frames use at least 50% of the canvas for literal UI evidence.
- The selected submission set contains six to eight frames. Other sets and background variants are review alternatives, not additional ASC inventory.
- Every visible header pitches a concrete benefit backed by a per-frame problem, advantage, search term, and literal UI proof.
- The first three frames must communicate separate market value at search scale.
- Every frame declares source, source_evidence, capture_flow, device, and evidence_status. Canonical frames map one-to-one to capture-report records.
- The app screen must be real capture evidence from the referenced build.
- Health and wellness copy must stay complementary and non-diagnostic.
- Re-run the audit after every copy, source, or layout change.
