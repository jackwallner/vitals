# Vitals+ Subscription — Implementation Complete ✅

> **Status: DONE.** All code is implemented and tested. Remaining work is App Store Connect configuration only.
> See `docs/app-store-metadata.md` for the ASC setup checklist.
>
> Original plan below kept for reference. Product IDs in code use `plus` (not `pro`), pricing is $1.99/mo / $14.99/yr / $29.99 lifetime.

## 1. Product Overview
**Goal:** Introduce an optional "Vitals+" premium tier as an auto-renewable subscription (e.g., $0.99/month or $9.99/year). This subscription will unlock an advanced **Monthly Summary & PDF Export** feature, allowing users to generate beautifully styled, shareable reports of their health data.

**Core Philosophy:** The existing app remains completely free. Vitals+ builds strictly on top, offering deeper insights and professional reporting for power users.

## 2. StoreKit 2 Integration Strategy
Since Vitals is a privacy-first, on-device app with no backend server, the subscription state will be managed entirely via **StoreKit 2** on the device.

- **App Store Connect Setup:**
  - Create an Auto-Renewable Subscription group (`Vitals+`).
  - Create subscription products (e.g., `com.jackwallner.vitals.pro.monthly` and `com.jackwallner.vitals.pro.yearly`).
  - Define introductory offers (e.g., 1-week free trial).
  - Add standard Apple EULA link to App Store metadata.

- **`StoreService.swift` (New Singleton `@MainActor`):**
  - Expose `@Published private(set) var isPro: Bool = false`.
  - Expose `@Published private(set) var products: [Product] = []`.
  - Implement `fetchProducts()` using `Product.products(for: ["com.jackwallner.vitals.pro.monthly", "com.jackwallner.vitals.pro.yearly"])`.
  - Implement `purchase(_ product: Product) async throws -> Transaction?`.
  - Implement `updateCustomerProductStatus()` using `Transaction.currentEntitlements` to check for active subscriptions on app launch and network recovery.
  - Listen to `Transaction.updates` via a long-running Task for out-of-app renewals, cancellations, or billing issues.
  - Implement `restorePurchases()` via `AppStore.sync()`.

## 3. UI Integration & Paywall

- **`Vitals/App.swift` Updates:**
  - Inject `StoreService.shared` into the environment.
  - Start the `Transaction.updates` listener when the app initializes.
  - Call `StoreService.shared.updateCustomerProductStatus()` on launch.

- **`Vitals/Views/DashboardView.swift` (Settings Sheet) Updates:**
  - Add a new "Vitals+" section at the top of the `SettingsSheet`.
  - If `isPro` is false, show an "Unlock Vitals+" button that opens the `PaywallView`.
  - If `isPro` is true, show "Vitals+ Active" and a "Manage Subscription" button that deep-links to the iOS subscription management screen (`https://apps.apple.com/account/subscriptions`).
  - Update `VitalsLinks` enum to include Apple's Standard EULA URL (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`) required for the Paywall.

- **The Paywall (`Vitals/Views/PaywallView.swift`):**
  - A modal sheet presented when tapping "Unlock Vitals+" or trying to generate a summary.
  - Shows feature benefits: "Unlock Monthly PDF Summaries & Deep Trends".
  - Fetches and displays localized prices via `StoreService`.
  - Includes required StoreKit legalese: Links to Privacy Policy, Terms of Use (EULA), and a "Restore Purchases" button.

## 4. The "Monthly Summary" Feature (`HistoryView`)
When a user has an active subscription, they gain access to the new feature.

- **UI Addition in `HistoryView.swift`:** 
  - Add a "Summary Report" button near the top of the view or alongside the existing "Export CSV" button.
  - If `!storeService.isPro`, tapping the button sets `showPaywall = true`.
  - If `storeService.isPro`, tapping it triggers the PDF generation flow.

- **The Report Generation (`Shared/Services/SummaryReportGenerator.swift`):**
  - Takes a date range (e.g., the last 30 days of `DayRecord` data).
  - Aggregates Total Calories, Active Calories, Resting Calories, and Steps.
  - Identifies peak days, averages, and calculates period-over-period trend percentages.

- **PDF Export (`Vitals/Views/SummaryReportView.swift`):**
  - A visually rich, print-friendly SwiftUI view designed specifically to be rendered into a PDF. Includes bar charts, aggregated metric cards, and the Vitals+ branding.
  - Rendered to a PDF document context using `@MainActor ImageRenderer` (iOS 16+).
  - Presents the standard iOS Share Sheet (`UIActivityViewController` / `ShareSheet`) with the generated `.pdf` file url.

## 5. Architecture & File Additions

**New Files:**
- `StoreKit.storekit` (Local StoreKit testing config for Simulator)
- `Shared/Services/StoreService.swift`
- `Vitals/Views/PaywallView.swift`
- `Shared/Services/SummaryReportGenerator.swift`
- `Vitals/Views/SummaryReportView.swift`

**Modified Files:**
- `project.yml` (Register the new `.swift` files and the `.storekit` config)
- `Vitals/App.swift` (Lifecycle hooks)
- `Vitals/Views/DashboardView.swift` (Settings sheet entry points)
- `Vitals/Views/HistoryView.swift` (Paywall trigger & PDF ShareSheet)
- `Shared/Models/CalorieTrendSummary.swift` (Reuse existing trend logic for the report if applicable)

## 6. Execution Steps
1. **Define StoreKit Config:** Create `StoreKit.storekit` and define the monthly/yearly auto-renewable subscriptions.
2. **Update XcodeGen:** Modify `project.yml` to include the new files and configure the Xcode scheme to use the `StoreKit.storekit` file. Run `xcodegen generate`.
3. **Implement StoreService:** Build `StoreService.swift` with full StoreKit 2 support (`Transaction.updates`, `currentEntitlements`, `Product.products`).
4. **App Initialization:** Hook `StoreService` into `App.swift`.
5. **Settings Integration:** Add Vitals+ status to `SettingsSheet` in `DashboardView.swift`.
6. **Build the Paywall:** Create `PaywallView.swift` with purchase buttons, restoring, and EULA links.
7. **Build the Report Logic:** Create `SummaryReportGenerator.swift` and `SummaryReportView.swift`. Implement PDF rendering via `ImageRenderer`.
8. **Integrate into History:** Add the "Summary Report" button to `HistoryView.swift`, triggering either the paywall or the PDF generation.
9. **Test End-to-End:** Validate local purchases in the Simulator, verify the PDF outputs correctly, and ensure the paywall handles edge cases (like network failures or deferred purchases).