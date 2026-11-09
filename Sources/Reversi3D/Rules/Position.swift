/// The discs on the board and the side to move.
struct Position: Equatable, Sendable {
    private(set) var black: UInt64 = 0
    private(set) var white: UInt64 = 0
    private(set) var sideToMove: Side = .black

    /// d4 and e5 white, d5 and e4 black; Black moves first.
    static let start = Position(
        black: Squares.bit(Squares.at(file: 4, row: 3)) | Squares.bit(Squares.at(file: 3, row: 4)),
        white: Squares.bit(Squares.at(file: 3, row: 3)) | Squares.bit(Squares.at(file: 4, row: 4)),
        sideToMove: .black)

    /// 64 squares from a1 to h8, X (or *) for Black, O for White, - (or . or _) for empty, then X or O (B or W) for the
    /// side to move. White space is passed over.
    static func parse(_ text: some StringProtocol) -> Position? {
        var position = Position()
        var square = 0
        var bytes = text.utf8.makeIterator()
        var next = bytes.next()
        while let byte = next, square < Squares.count {
            next = bytes.next()
            switch byte {
            case _ where Notation.isSpace(byte):
                continue
            case UInt8(ascii: "X"), UInt8(ascii: "x"), UInt8(ascii: "*"):
                position.black |= Squares.bit(square)
            case UInt8(ascii: "O"), UInt8(ascii: "o"):
                position.white |= Squares.bit(square)
            case UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"):
                break
            default:
                return nil
            }
            square += 1
        }
        guard square == Squares.count else { return nil }
        while let byte = next, Notation.isSpace(byte) {
            next = bytes.next()
        }
        if let side = next {
            switch side {
            case UInt8(ascii: "X"), UInt8(ascii: "x"), UInt8(ascii: "*"), UInt8(ascii: "B"), UInt8(ascii: "b"):
                break
            case UInt8(ascii: "O"), UInt8(ascii: "o"), UInt8(ascii: "W"), UInt8(ascii: "w"):
                position.sideToMove = .white
            default:
                return nil
            }
        }
        return position
    }

    var text: String {
        var characters = (0..<Squares.count).map { square -> Character in
            black & Squares.bit(square) != 0 ? "X" : white & Squares.bit(square) != 0 ? "O" : "-"
        }
        characters.append(" ")
        characters.append(sideToMove == .black ? "X" : "O")
        return String(characters)
    }

    func discs(_ side: Side) -> UInt64 { side == .black ? black : white }
    var player: UInt64 { discs(sideToMove) }
    var opponent: UInt64 { discs(sideToMove.opposite) }
    var empty: UInt64 { ~(black | white) }
    func count(_ side: Side) -> Int { discs(side).nonzeroBitCount }
    var emptyCount: Int { empty.nonzeroBitCount }

    func occupant(_ square: Square) -> Side? {
        if black & Squares.bit(square) != 0 { return .black }
        if white & Squares.bit(square) != 0 { return .white }
        return nil
    }

    /// Where the side to move can place a disc, and what a disc there turns over.
    var moves: UInt64 { Bitboard.moves(player: player, opponent: opponent) }
    func isLegal(_ square: Square) -> Bool { (0..<Squares.count).contains(square) && moves & Squares.bit(square) != 0 }
    func flips(_ square: Square) -> UInt64 { Bitboard.flips(square: square, player: player, opponent: opponent) }

    /// The side to move has nowhere to go, but the other side has.
    var mustPass: Bool { moves == 0 && Bitboard.moves(player: opponent, opponent: player) != 0 }
    /// Neither side can move: the game is over.
    var isOver: Bool { moves == 0 && Bitboard.moves(player: opponent, opponent: player) == 0 }

    /// The position after a legal move, or after a pass.
    func after(_ square: Square) -> Position {
        var next = self
        if square >= 0 {
            let turned = flips(square)
            if sideToMove == .black {
                next.black |= turned | Squares.bit(square)
                next.white &= ~turned
            } else {
                next.white |= turned | Squares.bit(square)
                next.black &= ~turned
            }
        }
        next.sideToMove = sideToMove.opposite
        return next
    }

    var key: UInt64 { Hashing.key(player: black, opponent: white) ^ (sideToMove == .white ? 0x2545_F491_4F6C_DD1D : 0) }
}
