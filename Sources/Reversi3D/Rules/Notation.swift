/// The characters of positions and transcripts, read byte by byte: only ASCII has a meaning in them.
enum Notation {
    static func isSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\n")
    }

    static func isLetter(_ byte: UInt8) -> Bool { (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte | 0x20) }

    static func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }

    /// A square of a board diagram: X, O, * or an empty mark.
    static func isBoardMark(_ byte: UInt8) -> Bool { "XxOo*-._".utf8.contains(byte) }

    /// The mark of the side to move after a diagram.
    static func isSideMark(_ byte: UInt8) -> Bool { "XxOoBbWw*".utf8.contains(byte) }
}
