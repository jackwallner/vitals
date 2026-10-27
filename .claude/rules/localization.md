---
paths:
  - "Shared/Localizable.xcstrings"
  - "Vitals/InfoPlist.xcstrings"
  - "VitalsWatch/InfoPlist.xcstrings"
  - "Vitals/AppShortcuts.xcstrings"
  - "Vitals/Intents/**"
  - "Shared/Utilities/LocalizedText.swift"
  - "project.yml"
---

# Vitals: UI localization (2026-10-26, 1.9.1; 29 more languages 2026-10-27)

The app ships in en plus 35 languages: de, fr, es, it, ja, zh-Hans (10-26) and
ar, cs, da, el, et, fa, fi, he, hi, hr, hu, id, ko, lv, ms, nb, nl, pl, pt-BR,
pt-PT, ro, ru, sk, sv, th, tr, uk, vi, zh-Hant (10-27, every region with 2+ new
customers in 30 days). Why: RevenueCat data showed non-English rich markets
trialing at about 6% against 15 to 19% for UK/US/CA/AU at the same price, while
the App Store pages were already translated, so the drop was inside the app.

- One catalog, `Shared/Localizable.xcstrings`, is compiled into all four
  targets. HealthKit purpose strings live in each app's `InfoPlist.xcstrings`;
  Siri/Shortcuts phrases in `Vitals/AppShortcuts.xcstrings` (each keeps
  `${applicationName}` exactly once, uninflected). XcodeGen derives
  `knownRegions` from the catalogs.
- Plurals: Slavic, Baltic, Arabic, Hebrew and Romanian use catalog plural
  variations on single-`%lld` keys. Keys with two or more numbers are phrased
  so no agreement is needed ("Dny s daty: %1$lld z %2$lld").
- The trial label (`%lld-day free trial`) is inserted into "Start %@" (the
  paywall button), "%@, on us." and "%1$@, then %2$@. %3$@": translate it as a
  phrase that reads in all three ("7 Tage gratis" + "%@ testen").
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
- Brand of the health app per language: Apple's own name (de keeps Apple
  Health; Apple Santé, Apple Salud, Apple Salute, ヘルスケア, Apple 健康, Apple
  Здоровье, Apple Zdrowie, Apple Sağlık, صحتي, בריאות, Apple 건강, Apple สุขภาพ,
  Apple स्वास्थ्य and so on). et, fa and lv have no iOS
  Health localization, so they keep "Apple Health" and the English HealthKit
  type and MyFitnessPal menu names. "cal" is kcal (千卡 zh-Hans, 大卡 zh-Hant,
  ккал ru/uk, kcal elsewhere). No bare `%` a key lacks ("HALF OFF" is words).

## Adding or changing copy

1. Build once (any destination). `SWIFT_EMIT_LOC_STRINGS` writes
   `.stringsdata` files into DerivedData.
2. Sync the catalog:
   `xcrun xcstringstool sync Shared/Localizable.xcstrings --stringsdata <each
   Vitals.build/**/*.stringsdata>`. New keys arrive untranslated.
3. Translate all 35 languages before shipping; an untranslated key shows
   English in that language. No Xcode at hand: edit the JSON directly
   (sourceLanguage en, `extractionState` manual for new keys) and check every
   key has every language with matching format specifiers.
4. Format specifiers must match the key; reorder with positional `%1$@`.
5. A `String` parameter of a custom view helper (`primaryLabel`,
   `unfoldedPaneBackHeader`) is not auto-localized; pass
   `String(localized:)` at the call site.

## Simulator checks

- Launch with `-AppleLanguages "(de)" -AppleLocale de_DE`; add
  `-PaywallSnapshot yearly|trial|exit-sheet` for the paywalls and
  `-ScreenshotScene onboarding` for onboarding. Check ar/he for RTL mirroring.
- The RevenueCat test store takes the currency code from the device region
  but the price string from the dashboard (USD), so per-week figures read
  "¥1" under ja_JP. Pair a language with `-AppleLocale en_US` to check them.
- Pool devices can be left at a large Dynamic Type size; reset with
  `xcrun simctl ui <udid> content_size large` before judging layout.
