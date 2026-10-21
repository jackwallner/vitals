# Screenshot audit: vitals

Status: **PASS**
Disposition: **RELEASE-READY**
Target: `iphone_duo_outer` at `1398x2034`
Capture status: `ok`

This report combines file-spec checks with an independent thumbnail and OCR pass. Open each `contact-sheet.png` and `search-grid.png` before approving a set.

## Market brief

- Category: Apple Watch calorie and activity trackers
- Audience: iPhone Duo and Apple Watch users who want total calories burned visible during the day without logging food or opening Health
- Problem: Apple Health separates energy details and activity surfaces emphasize movement, so total daily burn is easy to miss at the moment of decision.
- Advantage: Total Calories combines active plus resting energy into one daily number and puts it on the Watch face, widgets, and Lock Screen, free and on-device.
- Competitive context: The app competes with activity rings and calorie trackers that make users open a phone, log food, create an account, or pay for basic visibility. It wins on total-burn visibility in the surfaces users already check.

## Sets

| Set | Status | Frames |
| --- | --- | ---: |
| `duo-folded` | pass | 6 |

## Review contract

- Contract: `single-header-benefit-story-v3`.
- Every creative frame has exactly one large, period-free header capped at two lines. Eyebrows and subheaders are forbidden.
- Phone frames use at least 50% of the canvas for literal UI evidence.
- The selected submission set contains six to eight frames. Other sets and background variants are review alternatives, not additional ASC inventory.
- Every visible header pitches a concrete benefit backed by a per-frame problem, advantage, search term, and literal UI proof.
- The first three frames must communicate separate market value at search scale.
- Every frame declares source, source_evidence, capture_flow, device, and evidence_status. Validated-staged frames identify local preview evidence; canonical frames map one-to-one to capture-report records.
- The app screen must be real capture evidence from the referenced build.
- Health and wellness copy must stay complementary and non-diagnostic.
- Re-run the audit after every copy, source, or layout change.
