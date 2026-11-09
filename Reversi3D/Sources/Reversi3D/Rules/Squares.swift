/// A square of the 8x8 board: 0 is a1, 1 b1 ... 7 h1, 8 a2 ... 63 h8. Row 1 is at the top of a diagram, as on a
/// printed board. `Squares.pass` stands for the move of a side that cannot place a disc.
typealias Square = Int

/// The squares, their bits and their names.
enum Squares {
    static let count = 64
    static let pass: Square = -1

    static func file(_ square: Square) -> Int { square & 7 }
    static func row(_ square: Square) -> Int { square >> 3 }

    /// The square at a file and a row, or -1 off the board.
    static func at(file: Int, row: Int) -> Square {
        (0..<8).contains(file) && (0..<8).contains(row) ? row * 8 + file : -1
    }

    static func bit(_ square: Square) -> UInt64 { 1 << UInt64(square) }

    /// "f5"; a pass is "pass".
    static func name(_ square: Square) -> String {
        guard (0..<count).contains(square) else { return "pass" }
        let file = Character(Unicode.Scalar(UInt8(ascii: "a") + UInt8(self.file(square))))
        let row = Character(Unicode.Scalar(UInt8(ascii: "1") + UInt8(self.row(square))))
        return String([file, row])
    }
}
