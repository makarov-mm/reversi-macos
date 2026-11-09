/// Move generation on bitboards: bit n is square n.
enum Bitboard {
    /// The opponent's discs that a run may pass through for the directions with a sideways step: away from the side
    /// edges, so that nothing wraps round from one side of the board to the other.
    private static let inner: UInt64 = 0x7E7E_7E7E_7E7E_7E7E

    /// The empty squares where `player` can place a disc.
    static func moves(player: UInt64, opponent: UInt64) -> UInt64 {
        let sideways = opponent & inner
        let reach = runs(from: player, inner: sideways, step: 1) | runs(from: player, inner: opponent, step: 8)
            | runs(from: player, inner: sideways, step: 7) | runs(from: player, inner: sideways, step: 9)
        return reach & ~(player | opponent)
    }

    /// The opponent's discs that a disc placed on `square` turns over.
    static func flips(square: Square, player: UInt64, opponent: UInt64) -> UInt64 {
        let start = Squares.bit(square)
        let sideways = opponent & inner
        return line(from: start, player: player, inner: sideways, step: 1) | line(from: start, player: player, inner: opponent, step: 8)
            | line(from: start, player: player, inner: sideways, step: 7) | line(from: start, player: player, inner: sideways, step: 9)
    }

    /// The squares just past runs of one to six of the opponent's discs that start next to the player's, along a
    /// direction and its opposite: the runs grow by doubling.
    @inline(__always)
    private static func runs(from: UInt64, inner: UInt64, step: UInt64) -> UInt64 {
        var forward = inner & (from &<< step)
        var backward = inner & (from &>> step)
        forward |= inner & (forward &<< step)
        backward |= inner & (backward &>> step)
        let pairsForward = inner & (inner &<< step)
        let pairsBackward = inner & (inner &>> step)
        forward |= pairsForward & (forward &<< (2 * step))
        backward |= pairsBackward & (backward &>> (2 * step))
        forward |= pairsForward & (forward &<< (2 * step))
        backward |= pairsBackward & (backward &>> (2 * step))
        return (forward &<< step) | (backward &>> step)
    }

    /// The opponent's discs between a new disc and the player's, along a direction and its opposite.
    @inline(__always)
    private static func line(from start: UInt64, player: UInt64, inner: UInt64, step: UInt64) -> UInt64 {
        var forward = inner & (start &<< step)
        var backward = inner & (start &>> step)
        for _ in 0..<5 {
            forward |= inner & (forward &<< step)
            backward |= inner & (backward &>> step)
        }
        var flips: UInt64 = 0
        if (forward &<< step) & player != 0 {
            flips |= forward
        }
        if (backward &>> step) & player != 0 {
            flips |= backward
        }
        return flips
    }
}
