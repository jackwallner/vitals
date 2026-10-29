import Foundation

extension String {
    /// The language the app is actually showing, which can differ from
    /// `Locale.current` when the device language has no translation.
    static var appLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Start-of-sentence form, using the app language for the first letter.
    var leadingCapitalized: String {
        guard let first else { return self }
        let locale = Locale(identifier: String.appLanguage)
        return String(first).uppercased(with: locale) + dropFirst()
    }

    /// Mid-sentence form of a label like "Protein" or "30 days". German nouns
    /// keep their capital.
    var midSentence: String {
        String.appLanguage.hasPrefix("de") ? self : localizedLowercase
    }
}
