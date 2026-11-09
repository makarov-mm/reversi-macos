import Foundation

/// The choices and the game in progress, kept between sessions in the user defaults. The window keeps its own frame.
struct Settings {
    var theme = 0
    var level = 3
    var mode = 0
    /// The squares where the side to move can play.
    var showMoves = true
    var sound = true
    var panel = true
    var language = Language.system
    /// See `GameRecord.serialized`.
    var game = ""

    private enum Key {
        static let theme = "Theme"
        static let level = "Level"
        static let mode = "Mode"
        static let showMoves = "ShowMoves"
        static let sound = "Sound"
        static let panel = "Panel"
        static let language = "Language"
        static let game = "Game"
    }

    static func load(themeCount: Int) -> Settings {
        let defaults = UserDefaults.standard
        func integer(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }
        var settings = Settings()
        settings.theme = min(max(integer(Key.theme, 0), 0), themeCount - 1)
        settings.level = min(max(integer(Key.level, 3), 1), 5)
        settings.mode = min(max(integer(Key.mode, 0), 0), 3)
        settings.showMoves = integer(Key.showMoves, 1) != 0
        settings.sound = integer(Key.sound, 1) != 0
        settings.panel = integer(Key.panel, 1) != 0
        settings.language = Language(rawValue: integer(Key.language, -1)) ?? Language.system
        settings.game = defaults.string(forKey: Key.game) ?? ""
        return settings
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(theme, forKey: Key.theme)
        defaults.set(level, forKey: Key.level)
        defaults.set(mode, forKey: Key.mode)
        defaults.set(showMoves ? 1 : 0, forKey: Key.showMoves)
        defaults.set(sound ? 1 : 0, forKey: Key.sound)
        defaults.set(panel ? 1 : 0, forKey: Key.panel)
        defaults.set(language.rawValue, forKey: Key.language)
        defaults.set(game, forKey: Key.game)
    }
}
