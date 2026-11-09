/// The engine's judgement of a position for the side to move: mobility, frontier, corners and the squares next to
/// them, stable discs and the worth of the squares held. The weights were tuned in matches of the engine against
/// itself.
enum Evaluation {
    static let corners: UInt64 = 0x8100_0000_0000_0081

    /// The worth of holding each square, for the evaluation and for ordering the moves.
    static let squareValue: [Int] = [
        20, -3, 11, 8, 8, 11, -3, 20,
        -3, -7, -4, 1, 1, -4, -7, -3,
        11, -4, 2, 2, 2, 2, -4, 11,
        8, 1, 2, -3, -3, 2, 1, 8,
        8, 1, 2, -3, -3, 2, 1, 8,
        11, -4, 2, 2, 2, 2, -4, 11,
        -3, -7, -4, 1, 1, -4, -7, -3,
        20, -3, 11, 8, 8, 11, -3, 20,
    ]

    /// The quarters of the board: at the very end, a move into a quarter with an odd number of empty squares tends
    /// to get the last move there.
    static let quarters: [UInt64] = [0x0000_0000_0F0F_0F0F, 0x0000_0000_F0F0_F0F0, 0x0F0F_0F0F_0000_0000, 0xF0F0_F0F0_0000_0000]

    /// The squares next to each square.
    static let neighbourMasks: [UInt64] = (0..<Squares.count).map { square in
        var mask: UInt64 = 0
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let neighbour = Squares.at(file: Squares.file(square) + dx, row: Squares.row(square) + dy)
                if neighbour >= 0 {
                    mask |= Squares.bit(neighbour)
                }
            }
        }
        return mask
    }

    /// The side to move's score: the sum of the terms, divided by eight.
    static func evaluate(player: UInt64, opponent: UInt64, moves playerMoves: UInt64) -> Int {
        let empty = ~(player | opponent)
        var score = 0

        // Room to move, now and later: the moves each side has, and the discs each has next to empty squares, which
        // give the other side something to play against.
        score += Weight.mobility * share(playerMoves.nonzeroBitCount, Bitboard.moves(player: opponent, opponent: player).nonzeroBitCount)
        let frontier = neighbours(empty)
        score -= Weight.frontier * share((player & frontier).nonzeroBitCount, (opponent & frontier).nonzeroBitCount)

        // The corners, and the squares that give them away while they are empty.
        score += Weight.corner * ((player & corners).nonzeroBitCount - (opponent & corners).nonzeroBitCount)
        for area in cornerAreas where empty & area.corner != 0 {
            score -= Weight.xSquare * ((player & area.x).nonzeroBitCount - (opponent & area.x).nonzeroBitCount)
            score -= Weight.cSquare * ((player & area.c).nonzeroBitCount - (opponent & area.c).nonzeroBitCount)
        }

        // Discs that are there for good.
        let occupied = player | opponent
        score += Weight.stable * (stableDiscs(player, occupied: occupied).nonzeroBitCount - stableDiscs(opponent, occupied: occupied).nonzeroBitCount)

        // The discs themselves, and where they stand.
        score += Weight.discs * share(player.nonzeroBitCount, opponent.nonzeroBitCount)
        var squares = 0
        for value in valueMasks {
            squares += value.value * ((player & value.mask).nonzeroBitCount - (opponent & value.mask).nonzeroBitCount)
        }
        score += Weight.squares * squares
        return min(max(score / 8, -Engine.win + 1000), Engine.win - 1000)
    }

    static func evaluate(player: UInt64, opponent: UInt64) -> Int {
        evaluate(player: player, opponent: opponent, moves: Bitboard.moves(player: player, opponent: opponent))
    }

    /// The discs that can never be turned over: along each of the four lines through such a disc, the line is full,
    /// or the disc has the edge or another such disc of its color next to it.
    static func stableDiscs(_ own: UInt64, occupied: UInt64) -> UInt64 {
        // There are none without a corner, but in full lines along the edges, which are rare.
        guard own & corners != 0 else { return 0 }
        var fullRows: UInt64 = 0
        for row in 0..<8 where (occupied >> UInt64(8 * row)) & 0xFF == 0xFF {
            fullRows |= 0xFF << UInt64(8 * row)
        }
        var columns = occupied & (occupied >> 8)
        columns &= columns >> 16
        columns &= columns >> 32
        let fullColumns = (columns & 0xFF) &* fileA
        var fullDiagonals: UInt64 = 0
        var fullAntiDiagonals: UInt64 = 0
        for line in diagonals where occupied & line == line {
            fullDiagonals |= line
        }
        for line in antiDiagonals where occupied & line == line {
            fullAntiDiagonals |= line
        }

        var stable: UInt64 = 0
        while true {
            let across = fullRows | fileA | fileH | ((stable << 1) & notFileA) | ((stable >> 1) & notFileH)
            let down = fullColumns | row1 | row8 | (stable << 8) | (stable >> 8)
            let diagonal = fullDiagonals | edges | ((stable << 9) & notFileA) | ((stable >> 9) & notFileH)
            let antiDiagonal = fullAntiDiagonals | edges | ((stable << 7) & notFileH) | ((stable >> 7) & notFileA)
            let next = own & across & down & diagonal & antiDiagonal
            if next == stable {
                return stable
            }
            stable = next
        }
    }

    // MARK: - Terms

    /// The weights of the terms.
    private enum Weight {
        static let mobility = 237 // times the difference in moves as a share of all moves, -100 to 100
        static let frontier = 166 // the same for the discs next to empty squares, which count against
        static let corner = 8900 // for each corner
        static let xSquare = 3183 // against each disc diagonally next to an empty corner
        static let cSquare = 1415 // against each disc beside an empty corner on the edge
        static let stable = 1250 // for each disc that can no longer be turned
        static let discs = 15 // times the difference in discs as a share
        static let squares = 10 // times the worth of the squares held
    }

    private static let notFileA: UInt64 = 0xFEFE_FEFE_FEFE_FEFE
    private static let notFileH: UInt64 = 0x7F7F_7F7F_7F7F_7F7F
    private static let fileA: UInt64 = 0x0101_0101_0101_0101
    private static let fileH: UInt64 = 0x8080_8080_8080_8080
    private static let row1: UInt64 = 0x0000_0000_0000_00FF
    private static let row8: UInt64 = 0xFF00_0000_0000_0000
    private static let edges = fileA | fileH | row1 | row8

    /// A corner, the square diagonally next to it (the X-square) and the two beside it on the edges (the C-squares):
    /// taking those while the corner is empty usually hands the corner over.
    private static let cornerAreas: [(corner: UInt64, x: UInt64, c: UInt64)] = [
        (Squares.bit(0), Squares.bit(9), Squares.bit(1) | Squares.bit(8)),
        (Squares.bit(7), Squares.bit(14), Squares.bit(6) | Squares.bit(15)),
        (Squares.bit(56), Squares.bit(49), Squares.bit(57) | Squares.bit(48)),
        (Squares.bit(63), Squares.bit(54), Squares.bit(62) | Squares.bit(55)),
    ]

    /// The squares of each value, so that the position is scored a few masks at a time.
    private static let valueMasks: [(value: Int, mask: UInt64)] = {
        var masks: [(value: Int, mask: UInt64)] = []
        for (square, value) in squareValue.enumerated() {
            if let index = masks.firstIndex(where: { $0.value == value }) {
                masks[index].mask |= Squares.bit(square)
            } else {
                masks.append((value, Squares.bit(square)))
            }
        }
        return masks
    }()

    /// The diagonals in both directions, for finding the full ones.
    private static let diagonals: [UInt64] = lines { Squares.file($0) - Squares.row($0) + 7 }
    private static let antiDiagonals: [UInt64] = lines { Squares.file($0) + Squares.row($0) }

    private static func lines(_ index: (Square) -> Int) -> [UInt64] {
        var lines = [UInt64](repeating: 0, count: 15)
        for square in 0..<Squares.count {
            lines[index(square)] |= Squares.bit(square)
        }
        return lines
    }

    /// The squares next to any of the given ones.
    private static func neighbours(_ bits: UInt64) -> UInt64 {
        let sideways = ((bits << 1) & notFileA) | ((bits >> 1) & notFileH)
        let row = bits | sideways
        return sideways | (row << 8) | (row >> 8)
    }

    /// A difference as a share of a total, from -100 to 100.
    private static func share(_ own: Int, _ other: Int) -> Int {
        own + other > 0 ? 100 * (own - other) / (own + other) : 0
    }
}
