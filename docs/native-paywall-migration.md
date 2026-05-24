# Migrating from RevenueCat-Hosted Paywall to a Native SwiftUI Paywall

**Playbook for iOS apps using RevenueCat.** Use this when you want full control
over paywall UI/layout/copy (and fewer dashboard/design headaches) while **keeping
RevenueCat as the purchase, entitlement, and analytics backend**.

**Reference implementation:** [Vitals](https://github.com/jackwallner/vitals)  
(`main`, May 2026 — commits `54a32e6` through follow-up polish on impression dedupe).

---

## What changes vs. what stays the same

| Layer | Hosted paywall (`RevenueCatUI`) | Native paywall (this guide) |
|-------|--------------------------------|-----------------------------|
| **UI** | RC dashboard / `PaywallView` from SDK | Your SwiftUI (`PaywallView`, sheets, tabs) |
| **Products & prices** | `Purchases.shared.offerings()` | **Same** — still RC Offerings |
| **Purchases** | `Purchases.shared.purchase(package:)` | **Same** |
| **Trials / renewals / restores** | RC + Apple server-side | **Same** |
| **Entitlements** | `customerInfo.entitlements` | **Same** |
| **Impressions / funnel in RC** | Automatic | **You must call** `trackCustomPaywallImpression` |
| **Close / abandon events in RC** | Hosted only | **Not available** for custom paywalls (SDK limit) |
| **SPM dependency** | `RevenueCat` + `RevenueCatUI` | **`RevenueCat` only** (remove `RevenueCatUI`) |

**TL;DR:** You are only replacing the **presentation layer**. The money path stays:

```
Your PaywallView  →  StoreService.purchase(package)  →  Purchases.shared.purchase(package:)
```

---

## Why teams migrate

- **Design control** — typography, motion, feature bullets, plan layout, dark mode, accessibility without fighting the RC builder.
- **App Review (3.1.2)** — disclosure copy, EULA/privacy links, and trial wording live in code next to the buy button; easier to audit in PRs.
- **Fewer moving parts** — no “hosted paywall v3 doesn’t match production Offering” drift; UI renders whatever `offerings()` returns.
- **Same RC dashboard** — offerings, entitlements, customer history, webhooks unchanged.

**Tradeoffs:**

- You own impression tracking and eligibility checks the hosted UI did for free.
- RC A/B paywall experiments tied to **hosted** templates won’t apply; you can still experiment in your own UI or via Offering identifiers.
- No RC “close without purchase” event for custom paywalls — use your analytics tool on dismiss if you need it.

---

## Prerequisites

- **RevenueCat iOS SDK ≥ 5.67.0** (custom paywall impressions). Vitals uses **5.71.0**.
- Existing `Purchases.configure`, offerings fetch, `purchase(package:)`, `restorePurchases()`, and entitlement checks.
- App Store Connect products linked to RC Offerings (unchanged).

---

## Migration steps (any project)

### 1. Remove `RevenueCatUI`, keep `RevenueCat`

In SPM / CocoaPods / `project.yml`:

- **Remove** product `RevenueCatUI` from app targets.
- **Keep** product `RevenueCat` everywhere you purchase or read `Package` / `CustomerInfo`.

Regenerate the Xcode project if you use XcodeGen.

### 2. Build a native `PaywallView`

Minimum surface area (Vitals pattern):

1. **Load plans** — `await Purchases.shared.offerings()` → pick your offering (`default` or named) → `availablePackages`, sorted (lifetime / annual / monthly).
2. **Plan cards** — selectable rows; show localized price, optional “BEST VALUE”, trial badge when eligible.
3. **CTA** — dynamic label: `Start Free Trial` / `Subscribe` / `Unlock Lifetime` from selected `Package`.
4. **Apple 3.1.2 disclosure** — adjacent to the button, **per selected plan**:
   - Trial: trial length, then price, auto-renew, cancel at least 24h before period end.
   - Subscription (no trial): price + auto-renew + cancel instructions.
   - Lifetime: one-time price, no subscription.
5. **Restore Purchases** — `Purchases.shared.restorePurchases()`.
6. **Legal links** — standard Apple EULA + your privacy policy (shared `PaywallLinks` enum if multiple surfaces use them).
7. **States** — loading skeleton, empty/retry (airplane mode), purchase error, restore message.
8. **Dismiss on success** — `.onChange(of: isPro)` → `dismiss()` for sheet presentation.

Keep the **same public initializer** as your old wrapper if possible (`displayCloseButton:` etc.) so callsites don’t churn.

### 3. Intro-offer eligibility (required for trial copy)

The hosted paywall hides trial UI for ineligible users automatically. **You must replicate this** or risk 3.1.2 rejection.

After loading products:

```swift
let ids = packages
    .filter { $0.storeProduct.introductoryDiscount != nil }
    .map(\.storeProduct.productIdentifier)

let result = await Purchases.shared
    .checkTrialOrIntroDiscountEligibility(productIdentifiers: ids)

introEligibility = result.mapValues { $0.status == .eligible }
```

Gate trial badge + “Start Free Trial” CTA:

```swift
func isEligibleForIntroOffer(_ package: Package) -> Bool {
    guard packageHasFreeTrialIntro(package) else { return false }
    return introEligibility[package.storeProduct.productIdentifier] ?? true
    // ↑ unknown → true: avoid hiding trial on transient failure (Vitals choice).
    // For fail-closed: use `?? false`.
}
```

### 4. Wire custom paywall impressions (RevenueCat analytics)

Hosted paywalls report impressions automatically. Custom paywalls **do not**.

```swift
func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
    if oncePerSession, alreadyReported(id) { return }
    Purchases.shared.trackCustomPaywallImpression(
        CustomPaywallImpressionParams(paywallId: id)
    )
}
```

**Where to fire (critical):**

| Entry point | Good hook | Bad hook |
|-------------|-----------|----------|
| **Sheet paywall** | `.task { track(...) }` on the sheet content | `onAppear` (re-fires on parent updates) |
| **Tab / opacity-toggled paywall** | `.onChange(of: selectedTab)` when tab becomes paywall **and** user isn’t subscribed | Paywall view `onAppear` (fires at launch while hidden) |

**Deduping:** Tab users flip away and back often. Use `oncePerSession: true` for tab entry ids so RC isn’t inflated. **Do not** session-dedupe sheet ids — each sheet open should count.

Vitals ids:

- `vitals_upgrade_tab` — tab, `oncePerSession: true`
- `vitals_trial_sheet` — sheet, `oncePerSession: false` (default)

Skip tracking in screenshot/UI-test modes.

**SDK limitation:** There is **no** `trackCustomPaywallClose`. Abandonment = impressions minus purchases in RC, or your own analytics on dismiss.

### 5. Audit callsites

List every place that presented `RevenueCatUI.PaywallView` or your thin wrapper. Each should now present **your** `PaywallView` with `StoreService` / `environmentObject`.

Decide per entry point:

- **Full plan picker** (all packages) — native `PaywallView`.
- **Lightweight trial pitch** (optional) — separate sheet that can call `purchase()` for one package *or* chain to full paywall via “See all plans”.

Present **one sheet at a time** — set `showPaywall = true` in the *previous* sheet’s `onDismiss`, not in the same runloop as dismissing the first sheet (SwiftUI drops the second sheet).

### 6. Do **not** change the purchase pipeline

Keep:

- `Purchases.shared.purchase(package:)`
- `Purchases.shared.restorePurchases()`
- `PurchasesDelegate` / `customerInfo` updates
- `Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)` after cancel in sandbox

### 7. Delete or archive stale docs

Remove internal specs written for the RC paywall builder so future you doesn’t reintroduce `RevenueCatUI`.

---

## Apple App Review checklist (3.1.2)

Before shipping:

- [ ] Price visible for the **selected** plan before purchase.
- [ ] Auto-renew language + how to cancel (Settings), including 24h-before-period-end for trials.
- [ ] Privacy Policy + EULA links on the paywall.
- [ ] No “free trial” shown when `checkTrialOrIntroDiscountEligibility` says ineligible.
- [ ] Restore Purchases available.
- [ ] Tab-bar or navigation escape hatch if paywall is a tab (users must not feel trapped).

---

## RevenueCat verification checklist (sandbox)

- [ ] Purchase from native paywall → transaction in RC Customer History.
- [ ] Trial start recorded for trial purchase.
- [ ] Entitlement flips app to Pro; paywall dismisses.
- [ ] Restore works for Apple ID with active subscription.
- [ ] Sandbox cancel → `customerInfo` refresh clears Pro.
- [ ] Custom paywall impressions appear in RC (per `paywallId`).
- [ ] Tab impression not multiplied by revisiting the tab in one session (if using `oncePerSession`).

---

## Vitals-specific notes (reference only)

Optional product work that shipped alongside the paywall swap (not required for other apps):

- **Trial sheet** before full paywall for locked features (`TrialOfferCoordinator`).
- **14-day cooldown** on passive trial prompts; intent taps bypass cooldown.
- **Milestone celebrations** → trial chain (`MilestoneCalculator`).

Files to read in the Vitals repo:

| File | Purpose |
|------|---------|
| `Vitals/Views/PaywallView.swift` | Native paywall UI |
| `Shared/Services/StoreService.swift` | Offerings, eligibility, purchase, `trackPaywallImpression` |
| `Vitals/App.swift` | Tab vs sheet presentation, impression hooks, trial sheet chain |

---

## Common pitfalls

1. **Calling `onAppear` on a paywall that’s always in the hierarchy** (opacity tab) → bogus impressions at launch. Use tab `onChange` instead.
2. **Forgetting impressions entirely** → RC conversion metrics flatline for the new UI.
3. **Showing trial to ineligible users** → review risk; always gate on eligibility API.
4. **Bundling new HealthKit types with old ones in `requestAuthorization`** → iOS may suppress the sheet (unrelated to paywall, but same “native replaces hosted magic” theme).
5. **Two sheets in one tick** → second sheet never appears; chain in `onDismiss`.
6. **Removing `RevenueCat` by mistake** — only remove `RevenueCatUI`.

---

## Optional: copy this doc into your repo

Suggested path: `docs/native-paywall-migration.md` so the playbook travels with the project. The Desktop copy can stay as a template you duplicate per app.

---

*Last updated: 2026-05-24 (Vitals reference + impression `oncePerSession` dedupe).*
