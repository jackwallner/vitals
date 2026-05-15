# Handoff — Vitals+ RevenueCat-Hosted Paywall (v3)

For: RevenueCat AI paywall builder (Dashboard → Paywalls → AI draft).
Goal: Produce a hosted paywall for the `default` offering that we can render on iOS via `RevenueCatUI.PaywallView` and replace the legacy custom SwiftUI paywall. The legacy custom paywall is currently shipping and passed Apple Review — its compliance pattern is the source of truth.

## Fix these things from the v2 draft

1. **Net Deficit must be the hero pitch AND the leading feature row.** v2 had it only as a small subhead line and it got lost. Keep the hero subhead and ALSO promote Net Deficit to feature #1 in the card. It's the one thing only Vitals does — never bury it.
2. **Hardcoded prices are wrong.** v2 rendered "$69.99 / $9.99 / $119.99". Real prices from App Store Connect are $14.99 / $1.99 / $29.99. Bind every price string to the package's localized price variable — do not type prices into the template.
3. **The full Apple Guideline 3.1.2(a) disclaimer is still missing.** A "Start Free Trial" CTA without disclosure of (a) trial length, (b) what auto-renews after, (c) post-trial price, (d) renewal frequency, (e) how to cancel — all visible *before* the tap — fails App Review. The legacy paywall (currently approved) has three compliance layers below the CTA. All three are required:
   - **CTA subtext line** directly under the button (varies by package — copy in "CTA subtext" section below).
   - **Per-package intro line** on each subscription card ("7-day free trial included — then renews $X.XX/period").
   - **Full disclaimer paragraph** above the footer links (exact copy in "Legal disclaimer" section — do not paraphrase).
4. **Use SF Symbols literally as named.** v2 used solid coral dots instead of icons. The symbols are real iOS system glyphs: `plus.forwardslash.minus`, `doc.richtext.fill`, `chart.line.uptrend.xyaxis`, `flame.fill`, `lock.shield.fill`. Render the actual glyphs, not placeholder shapes.

## Compliance reference — what's already approved

The current shipping paywall passed Apple Review with these patterns. Mirror them:

- **CTA copy** when trial is active: "Start Free Trial" (button) + "Includes a 7-day free trial. Cancel anytime." (subtext directly below button).
- **CTA copy** when no trial: "Subscribe — $14.99" (button shows price) + "Auto-renews until cancelled." (subtext).
- **CTA copy** for lifetime: "Buy Lifetime — $29.99" (button shows price) + "One-time purchase. No subscription or renewal." (subtext).
- **Savings badge "Save 38%"** — allowed (truthful comparison: $1.99 × 12 = $23.88, vs $14.99 = ~37% savings, rounded to 38%).
- **Full disclaimer paragraph** above footer links — non-negotiable, exact wording below.

## App context

- **App**: Vitals — a personal iPhone + Apple Watch health tracker. Tracks total calories (active + resting) and steps via HealthKit. 100% on-device, no accounts, no cloud sync.
- **Bundle ID**: `com.jackwallner.vitals`
- **Min iOS**: 17.0
- **Tone**: Calm, focused, body-aware. Print-quality. Not a fitness-bro app — closer to a high-end health journal. Avoid hype, exclamation marks, ALL CAPS.

## RevenueCat configuration

- **API key (iOS)**: `appl_uiELZiyBHXCKzJyjqwaCbVkZRXB`
- **Offering identifier**: `default` (this is what the app fetches; falls back to `current`)
- **Entitlement**: `Vitals+` (any active entitlement unlocks pro; the lookup is permissive)

### Packages in the `default` offering — render ALL THREE

| Order | Package type   | Product ID | Price             | Badge          | Notes |
|-------|----------------|------------|-------------------|----------------|-------|
| 1     | `$rc_annual`   | `yearly`   | $14.99 / year     | "Save 38%"     | **Default selection.** 7-day free trial intro offer. Highlight as recommended / best value. |
| 2     | `$rc_monthly`  | `monthly`  | $1.99 / month     | —              | 7-day free trial intro offer. |
| 3     | `$rc_lifetime` | `lifetime` | $29.99 (one-time) | "One-time"     | **Required — do not omit.** No renewal. |

Default selected package: **annual** (yearly).

Savings copy: Yearly saves ~38% vs. monthly annualized. Use a dynamic "Save XX%" badge if the template supports it; otherwise hardcode "Save 38%".

Pull all price strings from the package's localized price — do not hardcode dollar amounts in the layout.

## Brand

- **Palette**: Coral / orange gradient for calories — the primary brand color and what CTAs use.
  - Primary: a warm coral `#FF7A59` → orange `#FF9F43` linear gradient (top-left to bottom-right).
  - Accent (secondary, used for steps): teal/cyan `#34C8C5`. Use sparingly — paywall is calorie-led.
- **Background**: System background (adapts to light/dark). Card surfaces use a subtle elevated material.
- **Typography**: SF Rounded (`.system(.body, design: .rounded)`). Bold rounded for headlines, regular rounded for body.
- **Iconography**: SF Symbols only — use the exact symbol names provided below. Hero icon: `sparkles` inside a coral-gradient circle.
- **Vibe**: Spacious, low-density, plenty of breathing room. Soft shadows, large corner radii (~14–20pt).

## Required content

### Header block (the top "weird" zone — make this feel composed, not stranded)

- Hero icon: `sparkles` SF Symbol, white, inside a ~56pt coral-gradient circle with a soft drop shadow.
- Title: **"Vitals+"** — 26–28pt, SF Rounded, bold.
- Subhead: **"See your real calorie deficit — burn minus food from Apple Health."** 14–15pt, secondary text color, centered, max ~2 lines, tight line height.
- Optional micro-line under the subhead (small/tertiary): **"7-day free trial · cancel anytime"** — only render when a trial is available on the selected package.

The header should read as one composed unit. Tight vertical spacing between icon → title → subhead → micro-line. Don't leave a big air gap between title and subhead.

### Feature list (5 rows — Net Deficit leads)

In a single rounded card with subtle background. Order matters — Net Deficit is the lead. Render real SF Symbol glyphs, not coral dots:

1. **Net Deficit** — `plus.forwardslash.minus` — Calories burned minus food from Apple Health.
2. **Monthly + Custom PDFs** — `doc.richtext.fill` — Print-ready reports for any range.
3. **Deep Trends** — `chart.line.uptrend.xyaxis` — Period-over-period comparison on every view.
4. **Active + Resting Breakdown** — `flame.fill` — Movement vs. metabolism, live.
5. **Stays Private** — `lock.shield.fill` — Generated on-device. Nothing leaves your phone.

Yes, Net Deficit also appears in the hero subhead. That's intentional — it's the headline pitch and it's also the leading feature. The repetition is a feature, not a bug.

### Package selector

Three radio-style cards stacked vertically in this order: Yearly → Monthly → Lifetime. Each card shows:
- Name (Yearly / Monthly / Lifetime), bold.
- Badge if applicable ("Save 38%" on Yearly, "One-time" on Lifetime).
- Price line — **bind to the package's localized price variable**, do not hardcode. Expected real values are $14.99/year, $1.99/month, $29.99 one-time. If your draft shows anything else (e.g. $69.99), the binding is wrong.
- Intro-offer sub-line on Yearly + Monthly (Apple-required disclosure of post-trial renewal): "7-day free trial included — then renews at {price}/{period}".

The Yearly card starts selected.

### CTA button

Full-width capsule, coral gradient fill, white bold text. Label depends on selected package:

- Annual with trial selected → **"Start Free Trial"**
- Monthly with trial selected → **"Start Free Trial"**
- Lifetime selected → **"Buy Lifetime — $29.99"** (pull price from package variable)
- Annual without trial → **"Subscribe — $14.99"** (pull price from package variable)

### CTA subtext (one line under the button, small grey)

- Trial selected: "Includes a 7-day free trial. Cancel anytime."
- Lifetime: "One-time purchase. No subscription or renewal."
- Otherwise: "Auto-renews until cancelled."

### Legal disclaimer — REQUIRED, do not omit

Render this full paragraph below the CTA subtext and above the footer links. 10pt, tertiary text color, centered or left-aligned with comfortable line height. Exact copy:

> Payment will be charged to your Apple ID account at confirmation of purchase. Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → Apple ID → Subscriptions. Lifetime access is a one-time purchase.

This is non-negotiable — Apple App Review rejects builds that ship a paywall without it (Guideline 3.1.2(a)).

### Footer links (visible without scrolling past the bottom of the disclaimer)

Both links rendered as small coral-tinted text, separated by a middle dot:

- **Privacy Policy** → `https://jackwallner.github.io/vitals/privacy-policy.html`
- **Terms of Use** → `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` (Apple's standard EULA)

### Restore button
Top-right toolbar, label: **"Restore"**, coral text color.

### Close button
Top-left toolbar, label: **"Close"** (X icon also fine), secondary/grey color. The hosting app may suppress the close button when the paywall is rendered as a tab — design should still look balanced without it.

## Layout (top → bottom, in order)

1. Header block — icon, title, subhead, optional trial micro-line. Composed as one tight unit.
2. Feature card — 4 rows (Net Deficit is in the hero, not here).
3. Package selector — Yearly (default selected, with "Save 38%") → Monthly → **Lifetime ("One-time")**. All three required.
4. CTA button — full width, capsule, coral gradient.
5. CTA subtext (one line).
6. **Legal disclaimer paragraph** — required, 10pt tertiary.
7. Footer links: Privacy Policy · Terms of Use.

## Reference

- The legacy custom paywall this is replacing lives in git history at `Vitals/Views/PaywallView.swift` (pre-swap commit). Use it as the visual reference of record — it had Net Deficit messaging, all three packages, and the full disclaimer block correctly laid out.
- Screenshot at repo root: `paywall_screenshot.png`.

## States to design for

- **Loading** — packages still fetching. Spinner in the package-selector slot.
- **Error / no packages** — copy: "Subscriptions unavailable. Check your connection and try again." + a "Try Again" link.
- **Purchase in flight** — disable CTA, swap label for a spinner + "Waiting for the App Store purchase sheet…"
- **Already pro** — paywall should not render; the app gates this upstream, but the success path post-purchase should auto-dismiss.

## Out of scope for this handoff

- watchOS paywall (not used — watch app reads entitlement from iOS via WatchConnectivity).
- Localization beyond `en-US`.
- A/B test variants — single template for now.
