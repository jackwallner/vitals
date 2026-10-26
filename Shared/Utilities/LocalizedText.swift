import Foundation

extension String {
    /// The language the app is actually showing, which can differ from
    /// `Locale.current` when the device language has no translation.
    static var appLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Start-of-sentence form of a label like "7-day free trial". English keeps
    /// its title case; other languages only raise the first letter.
    var leadingCapitalized: String {
        if String.appLanguage.hasPrefix("en") { return capitalized }
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Mid-sentence form of a label like "Protein" or "30 days". German nouns
    /// keep their capital.
    var midSentence: String {
        String.appLanguage.hasPrefix("de") ? self : localizedLowercase
    }
}
