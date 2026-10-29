---
paths:
  - "Shared/**/*.swift"
  - "Vitals/**/*.swift"
  - "VitalsWidget/**/*.swift"
  - "VitalsWatch/**/*.swift"
  - "VitalsWatchWidget/**/*.swift"
  - "Vitals/Info.plist"
  - "VitalsWidget/Info.plist"
  - "VitalsWatch/Info.plist"
  - "VitalsWatchWidget/Info.plist"
  - "Shared/Localizable.xcstrings"
  - "Vitals/InfoPlist.xcstrings"
  - "VitalsWatch/InfoPlist.xcstrings"
  - "Vitals/AppShortcuts.xcstrings"
  - "Vitals/Intents/**"
  - "Shared/Utilities/LocalizedText.swift"
  - "Tools/Localization/**"
  - "project.yml"
---

# Vitals: UI localization (2026-10-28)

The app, iOS widgets, Watch app, Watch complications, App Intents, and
notifications ship in English plus 35 languages: ar, cs, da, de, el, es, et,
fa, fi, fr, he, hi, hr, hu, id, it, ja, ko, lv, ms, nb, nl, pl, pt-BR, pt-PT,
ro, ru, sk, sv, th, tr, uk, vi, zh-Hans, and zh-Hant. The 31 priority locales
are de, fr, es, ja, ar, pl, it, nl, zh-Hans, pt-BR, sv, he, th, da, fi, vi,
ru, zh-Hant, id, hu, nb, ro, cs, uk, tr, el, pt-PT, ko, sk, ms, and hr. Keep
the existing et, fa, hi, and lv translations too.

## Setup

- `Shared/Localizable.xcstrings` is the UI catalog. `Shared/` is included in
  all four app and widget targets, so every target compiles the same strings.
- HealthKit purpose text lives in `Vitals/InfoPlist.xcstrings` and
  `VitalsWatch/InfoPlist.xcstrings`. Shortcut phrases live in
  `Vitals/AppShortcuts.xcstrings`; each phrase keeps `${applicationName}` once,
  unchanged and uninflected.
- XcodeGen 2.39 or later reads String Catalog locales into `knownRegions`.
  Every target Info.plist lists `en` and all 35 translated locales in
  `CFBundleLocalizations`.
- Run `python3 Tools/Localization/check.py` from the repo root. It checks
  localizable Swift literals, every catalog's locale coverage, format
  specifiers, shortcut application-name tokens, and Info.plist localization
  declarations. It does not need Xcode.
- `VitalsTests/LocalizationTests.swift` checks that the 31 priority locale
  bundles ship and that Russian plural forms resolve for one, few, and many.

## Copy rules

- SwiftUI text literals localize automatically. Any copy stored in a `String`,
  including model values, view parameters, errors, notifications, and App
  Intent dialogs, must use `String(localized:)`. App Intent titles and
  descriptions use `LocalizedStringResource` and `IntentDescription`.
- Use complete messages as keys. Do not concatenate translated pieces or
  assemble a sentence from translated fragments. Branch and provide a complete
  key for each variant. Use String Catalog plural variations for counts.
- Keep locale-sensitive numbers, dates, units, and durations in Foundation
  formatters. Dates use `setLocalizedDateFormatFromTemplate` or `formatted()`.
  Prices come only from StoreKit's localized price strings.
- Do not call `.capitalized` or `.lowercased()` on translated text. Use
  `leadingCapitalized` and `midSentence` from `LocalizedText.swift` where
  needed.
- Keep the brand names `Vitals+` and `Total Calories`, and the abbreviations
  TDEE and BMR. Calorie values are kcal: use 千卡 in zh-Hans, 大卡 in zh-Hant,
  and ккал in ru and uk. Use Apple's localized Health app name and its
  localized energy and step terms in each market.
- German uses informal `du`. Keep tight labels short, especially in German,
  Finnish, and Russian. Arabic and Hebrew must retain right-to-left layout and
  use semantic leading/trailing placement and forward/backward symbols.
- Health copy remains descriptive and must not imply treatment, diagnosis, or
  prevention.

## Adding strings

1. Route visible copy through a SwiftUI text API or `String(localized:)`.
   String parameters to custom view helpers are not localized automatically.
2. Use a complete message key and preserve every format argument. Add catalog
   translations for all 35 languages, including correct plural variations.
3. Keep `sourceLanguage` set to `en`, mark manually added entries with
   `extractionState: manual`, then run `python3 Tools/Localization/check.py`.
4. Regenerate the Xcode project after changing `project.yml` or adding/removing
   Swift files. Do not edit `project.pbxproj` by hand.

## Verification

- `gh-sim test` runs the Vitals unit suite and the localization bundle/plural
  checks on GitHub's Macs.
- For screenshots, pass one `--screen` per locale with both
  `-AppleLanguages (<language>)` and `-AppleLocale <locale>`. Use the seeded
  scenes in `Shared/Utilities/ScreenshotConfig.swift` for onboarding and the
  main screen, and `-PaywallSnapshot trial` for the trial page. Capture the
  actual Home Screen widget through `VitalsUITests/AuditFeaturesUITests.swift`
  (`testLargeWidgetAddAndTap`); it has no app launch scene. Inspect RTL,
  German, Finnish, and Russian first for mirroring and tight-label fit.
