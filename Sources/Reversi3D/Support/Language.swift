import Foundation

/// The language of the interface.
enum Language: Int, Sendable {
    case english = 0
    case russian = 1

    /// Russian for the users of Russian, Ukrainian and Belarusian, English for the others.
    static var system: Language {
        let preferred = Locale.preferredLanguages.first ?? ""
        return ["ru", "uk", "be"].contains { preferred.hasPrefix($0) } ? .russian : .english
    }

    var other: Language { self == .english ? .russian : .english }
}
