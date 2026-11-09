/// A key pressed, as the game reads it.
struct KeyPress {
    /// The key's place on the keyboard, a virtual key code of macOS.
    var code: UInt16
    /// The letter of the key for the shortcuts, from a to z, if it has one.
    var letter: Character?
    var command = false
    var shift = false
    var option = false
    var control = false
    var isRepeat = false

    /// The virtual key codes the game listens for, by their place on a US keyboard.
    enum Code {
        static let returnKey: UInt16 = 0x24
        static let tab: UInt16 = 0x30
        static let delete: UInt16 = 0x33
        static let escape: UInt16 = 0x35
        static let keypadEnter: UInt16 = 0x4C
        static let help: UInt16 = 0x72
        static let home: UInt16 = 0x73
        static let f1: UInt16 = 0x7A
        static let f11: UInt16 = 0x67
        static let leftArrow: UInt16 = 0x7B
        static let rightArrow: UInt16 = 0x7C
    }

    /// The letters of the letter keys, by their virtual key codes.
    private static let usLetters: [UInt16: Character] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l",
        0x2E: "m", 0x2D: "n", 0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t", 0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x",
        0x10: "y", 0x06: "z",
    ]

    /// The digit keys 1 to 5, on the main keys and on the keypad.
    private static let levelKeys: [UInt16: Int] = [0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4, 0x17: 5, 0x53: 1, 0x54: 2, 0x55: 3, 0x56: 4, 0x57: 5]

    /// The letter of a key for the shortcuts: by its label in Latin layouts (Z on a German keyboard is where it is
    /// marked), and by its place on a US keyboard in the others, such as the Russian one.
    static func shortcutLetter(characters: String?, code: UInt16) -> Character? {
        guard let scalar = characters?.lowercased().unicodeScalars.first else { return nil }
        if ("a"..."z").contains(scalar) {
            return Character(scalar)
        }
        return scalar.value >= 0x80 ? usLetters[code] : nil
    }

    /// The computer level of a digit key, by its place, so that it works in any layout; nil for the other keys.
    var level: Int? { Self.levelKeys[code] }
}
