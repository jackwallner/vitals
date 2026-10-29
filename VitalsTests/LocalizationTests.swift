import Foundation
import Testing
@testable import Vitals

@Suite("Localization")
struct LocalizationTests {
    static let languages = [
        "ar", "cs", "da", "de", "el", "es", "fi", "fr", "he", "hr", "hu", "id", "it",
        "ja", "ko", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv",
        "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
    ]

    private func bundle(_ language: String) -> Bundle? {
        let hosts = [Bundle.main] + Bundle.allBundles
        for host in hosts {
            guard let path = host.path(forResource: language, ofType: "lproj") else { continue }
            return Bundle(path: path)
        }
        return nil
    }

    @Test func everyTargetLanguageShips() {
        for language in Self.languages {
            #expect(bundle(language) != nil, "\(language).lproj is missing")
        }
    }

    @Test func russianPluralsSelectOneFewAndMany() throws {
        let russian = try #require(bundle("ru"))
        let locale = Locale(identifier: "ru")

        #expect(String(localized: "\(1) Excluded Days", bundle: russian, locale: locale) == "1 исключённый день")
        #expect(String(localized: "\(3) Excluded Days", bundle: russian, locale: locale) == "3 исключённых дня")
        #expect(String(localized: "\(5) Excluded Days", bundle: russian, locale: locale) == "5 исключённых дней")
    }

    @Test func arabicPluralsSelectEveryCategory() throws {
        let arabic = try #require(bundle("ar"))
        let locale = Locale(identifier: "ar")
        let cases: [(Int, String)] = [
            (0, "يوم مستبعد"),
            (1, "يوم مستبعد"),
            (2, "يومان مستبعدان"),
            (3, "أيام مستبعدة"),
            (11, "يومًا مستبعدًا"),
            (100, "يوم مستبعد"),
        ]

        for (count, expectedText) in cases {
            let value = String(localized: "\(count) Excluded Days", bundle: arabic, locale: locale)
            #expect(value.contains(expectedText), "Unexpected Arabic plural for \(count): \(value)")
        }
    }

    @Test func arabicStepsSelectPluralForms() throws {
        let arabic = try #require(bundle("ar"))
        let locale = Locale(identifier: "ar")
        let cases: [(Int, String)] = [(1, "خطوة"), (2, "خطوتان"), (3, "خطوات"), (11, "خطوة")]
        for (count, expectedText) in cases {
            let value = String(localized: "\(count) steps", bundle: arabic, locale: locale)
            #expect(value.contains(expectedText), "Unexpected Arabic steps plural for \(count): \(value)")
        }
    }
}
