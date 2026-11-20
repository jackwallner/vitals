import Foundation

/// Reads a number the user typed. The number pad types the region's digits
/// (Arabic-Indic in Saudi Arabia, Persian in Iran), which `Double(String)` and
/// `Int(String)` reject, so every digit is mapped to ASCII first, with the
/// Arabic decimal and thousands separators.
enum TypedNumber {
    static func latinDigits(_ text: String) -> String {
        var result = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            switch character {
            case "\u{066B}": result.append(".") // Arabic decimal separator
            case "\u{066C}": continue // Arabic thousands separator
            default:
                if character.isNumber, let digit = character.wholeNumberValue, (0...9).contains(digit),
                   character.unicodeScalars.count == 1,
                   character.unicodeScalars.first?.properties.numericType == .decimal {
                    result.append(Character(String(digit)))
                } else {
                    result.append(character)
                }
            }
        }
        return result
    }

    static func double(_ text: String) -> Double? { Double(latinDigits(text)) }

    static func int(_ text: String) -> Int? { Int(latinDigits(text)) }
}
