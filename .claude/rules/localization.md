---
paths:
  - "Shared/Localizable.xcstrings"
  - "Vitals/InfoPlist.xcstrings"
  - "VitalsWatch/InfoPlist.xcstrings"
  - "Shared/Utilities/LocalizedText.swift"
  - "project.yml"
---

# Vitals: UI localization (2026-10-26, 1.9.1)

The app ships in en, de, fr, es, it, ja and zh-Hans. Why: Aug 13 to Oct 24
RevenueCat data showed non-English rich markets trialing at about 6% against
15 to 17% for UK/US/CA/AU at the same effective price, so the gap was language,
not price.

- One catalog, `Shared/Localizable.xcstrings`, is compiled into all four
  targets. HealthKit purpose strings live in each app's `InfoPlist.xcstrings`.
  XcodeGen derives `knownRegions` from the catalogs.
- `Text("literal")` localizes on its own. Any copy held in a `String`
  (view params, enums, copy helpers, notifications, App Intents) must be
  `String(localized:)`. Logs, analytics, RC metadata, support-mail diagnostics
  and identifiers stay plain.
- Write whole sentences as keys. Never build copy from fragments
  ("\(n) \(dayWord)", "\(noun) goal", "ahead of"/"behind"): branch and give
  each variant its own key. Singular/plural is a branch (`n == 1`).
- `.capitalized` and `.lowercased()` break German nouns: use
  `leadingCapitalized` and `midSentence` from `LocalizedText.swift`.
- Dates use `setLocalizedDateFormatFromTemplate`, never a fixed `dateFormat`
  (except the en_US_POSIX CSV date).
- Prices only ever come from `storeProduct.localizedPriceString`
  (`vitalsPriceLabel` and friends). No currency literal in UI code.
- "Vitals+", "Total Calories", "TDEE", "BMR" and "VITALS+" stay untranslated
  (`trialBadgeText != "VITALS+"` compares against the literal).
- Brand of the health app per language: Apple Health, Apple Santé, Apple
  Salud, Apple Salute, ヘルスケア, Apple 健康. "cal" is kcal (千卡 in zh).

## Adding or changing copy

1. Build once (any destination). `SWIFT_EMIT_LOC_STRINGS` writes
   `.stringsdata` files into DerivedData.
2. Sync the catalog:
   `xcrun xcstringstool sync Shared/Localizable.xcstrings --stringsdata <each
   Vitals.build/**/*.stringsdata>`. New keys arrive untranslated.
3. Translate all six languages before shipping; an untranslated key shows
   English in that language.
4. Format specifiers must match the key; reorder with positional `%1$@`.
5. A `String` parameter of a custom view helper (`primaryLabel`,
   `unfoldedPaneBackHeader`) is not auto-localized; pass
   `String(localized:)` at the call site.

## Simulator checks

- Launch with `-AppleLanguages "(de)" -AppleLocale de_DE`; add
  `-PaywallSnapshot yearly|trial|exit-sheet` for the paywalls.
- The RevenueCat test store takes the currency code from the device region
  but the price string from the dashboard (USD), so per-week figures read
  "¥1" under ja_JP. Pair a language with `-AppleLocale en_US` to check them.
- Pool devices can be left at a large Dynamic Type size; reset with
  `xcrun simctl ui <udid> content_size large` before judging layout.
