/// An alpha-beta searcher: iterative deepening, principal variation search and a transposition table in the middle
/// game, and an exact solver for the end, which orders its moves to leave the opponent the fewest replies.
///
/// An engine is used by one thread at a time.
final class Engine {
    /// A won game scores this, and then the discs it is won by.
    static let win = 30_000

    static func isWinScore(_ score: Int) -> Bool { score > win - 100 || score < -win + 100 }

    private static let infinity = 1 << 20
    /// More than the deepest line of a search: each move may be followed by a pass.
    private static let maxPly = 160

    private enum Bound: UInt8 {
        case none, upper, lower, exact
    }

    private struct Entry {
        var key: UInt64 = 0
        var score: Int32 = 0
        var depth: Int8 = 0
        var bound = Bound.none
        var move: Int8 = -1
        var solved = false // the score is the final difference in discs, not an evaluation
    }

    private struct RootMove {
        var square: Square
        var score = 0
    }

    private struct Candidate {
        var square: Square = 0
        var flips: UInt64 = 0
        var order = 0
    }

    private let clock = ContinuousClock()
    private let table: UnsafeMutablePointer<Entry>
    private let tableMask: Int
    /// The moves of each ply of the line being searched, 64 a ply.
    private let candidates: UnsafeMutablePointer<Candidate>
    private var nodes: UInt64 = 0
    private var deadline: ContinuousClock.Instant
    private var stop = StopFlag()
    private var aborted = false

    init(hashMegabytes: Int) {
        var entries = 1
        while entries * 2 * MemoryLayout<Entry>.stride <= hashMegabytes * 1024 * 1024 {
            entries *= 2
        }
        table = .allocate(capacity: entries)
        table.initialize(repeating: Entry(), count: entries)
        tableMask = entries - 1
        candidates = .allocate(capacity: 64 * Self.maxPly)
        candidates.initialize(repeating: Candidate(), count: 64 * Self.maxPly)
        deadline = clock.now
    }

    deinit {
        table.deallocate()
        candidates.deallocate()
    }

    func clear() {
        table.update(repeating: Entry(), count: tableMask + 1)
    }

    func search(_ root: Position, limits: SearchLimits, stop: StopFlag) -> SearchResult {
        let start = clock.now
        deadline = start + .milliseconds(limits.milliseconds)
        self.stop = stop
        aborted = false
        nodes = 0

        let player = root.player
        let opponent = root.opponent
        var moves: [RootMove] = []
        var bits = root.moves
        while bits != 0 {
            moves.append(RootMove(square: bits.trailingZeroBitCount))
            bits &= bits - 1
        }
        guard !moves.isEmpty else { return SearchResult() }
        // To begin with, the moves that leave the opponent the fewest replies first.
        for i in moves.indices {
            let square = moves[i].square
            let flips = Bitboard.flips(square: square, player: player, opponent: opponent)
            let replies = Bitboard.moves(player: opponent & ~flips, opponent: player | flips | Squares.bit(square))
            moves[i].score = 8 * Evaluation.squareValue[square] - 64 * replies.nonzeroBitCount
        }
        moves = Self.sortedByScore(moves)

        var result = SearchResult()
        result.best = moves[0].square
        if moves.count == 1 && limits.randomMargin == 0 {
            return result
        }

        // Before an exact solution of the end, a short search puts the likely best moves first for it.
        let solve = root.emptyCount <= limits.exactEmpties
        let budget = Duration.milliseconds(solve ? limits.milliseconds / 5 : limits.milliseconds)
        var middle = limits
        if solve {
            middle.maxDepth = min(middle.maxDepth, 10)
        }
        deadline = start + budget
        searchMiddle(root, moves: &moves, limits: middle, result: &result, start: start, budget: budget)
        if solve && !stop.isStopped {
            deadline = start + .milliseconds(limits.milliseconds)
            aborted = false
            solveRoot(root, moves: &moves, exactScores: limits.randomMargin > 0, result: &result)
        }

        if limits.randomMargin > 0 && result.depth > 0 {
            // The weaker levels pick among the good moves, the better ones more often. When the end is solved, the
            // margin is counted in discs.
            let margin = result.solved ? limits.randomMargin / 25 : limits.randomMargin
            var random = SplitMix64(seed: limits.seed ^ root.key)
            let bestScore = moves[0].score
            let candidates = moves.filter { $0.score >= bestScore - margin }
            let weights = candidates.map { 1.0 + Double(margin - (bestScore - $0.score)) / Double(max(1, margin)) * 3.0 }
            let chosen = candidates[Self.weightedIndex(weights, using: &random)]
            result.best = chosen.square
            result.score = chosen.score
        }
        result.nodes = nodes
        return result
    }

    // MARK: - Root

    /// Iterative deepening; false when cut short.
    @discardableResult
    private func searchMiddle(_ root: Position, moves: inout [RootMove], limits: SearchLimits, result: inout SearchResult,
                              start: ContinuousClock.Instant, budget: Duration) -> Bool {
        let player = root.player
        let opponent = root.opponent
        let exactScores = limits.randomMargin > 0
        let empties = root.emptyCount
        for depth in stride(from: 1, through: limits.maxDepth, by: 1) {
            // The scores of the last whole iteration, for the moves to keep if this one is cut short: scores of two
            // depths are not to be compared, as the random choice of the weaker levels would.
            let previous = moves
            var alpha = -Self.infinity
            var iterationBest = Squares.pass
            var iterationScore = -Self.infinity
            var complete = true
            for i in moves.indices {
                let square = moves[i].square
                let flips = Bitboard.flips(square: square, player: player, opponent: opponent)
                let nextPlayer = opponent & ~flips
                let nextOpponent = player | flips | Squares.bit(square)
                var score: Int
                if i == 0 || exactScores {
                    score = -negamax(nextPlayer, nextOpponent, depth: depth - 1, alpha: -Self.infinity,
                                     beta: exactScores ? Self.infinity : -alpha, passed: false, ply: 1)
                } else {
                    score = -negamax(nextPlayer, nextOpponent, depth: depth - 1, alpha: -alpha - 1, beta: -alpha, passed: false, ply: 1)
                    if !aborted && score > alpha {
                        score = -negamax(nextPlayer, nextOpponent, depth: depth - 1, alpha: -Self.infinity, beta: -alpha, passed: false, ply: 1)
                    }
                }
                if aborted {
                    complete = false
                    break
                }
                moves[i].score = score
                if score > iterationScore {
                    iterationScore = score
                    iterationBest = square
                }
                alpha = max(alpha, score)
            }

            // An unfinished iteration still counts when its first move, the best before, was searched: a move that
            // then came out best beat it.
            if iterationBest != Squares.pass {
                result.best = iterationBest
                result.score = iterationScore
            }
            if !complete {
                moves = previous
                return false
            }
            result.depth = depth
            moves = Self.sortedByScore(moves)
            if start.duration(to: clock.now) > budget / 2 || Self.isWinScore(iterationScore) || depth >= empties {
                break
            }
        }
        return true
    }

    /// The exact score of every move; false when cut short.
    @discardableResult
    private func solveRoot(_ root: Position, moves: inout [RootMove], exactScores: Bool, result: inout SearchResult) -> Bool {
        let player = root.player
        let opponent = root.opponent
        let empties = root.emptyCount
        var alpha = -Squares.count - 1
        let beta = Squares.count + 1
        var solved = moves
        for i in solved.indices {
            let square = solved[i].square
            let flips = Bitboard.flips(square: square, player: player, opponent: opponent)
            let nextPlayer = opponent & ~flips
            let nextOpponent = player | flips | Squares.bit(square)
            var score: Int
            if i == 0 || exactScores {
                score = -solve(nextPlayer, nextOpponent, alpha: -beta, beta: exactScores ? beta : -alpha, empties: empties - 1, passed: false, ply: 1)
            } else {
                score = -solve(nextPlayer, nextOpponent, alpha: -alpha - 1, beta: -alpha, empties: empties - 1, passed: false, ply: 1)
                if !aborted && score > alpha {
                    score = -solve(nextPlayer, nextOpponent, alpha: -beta, beta: -alpha, empties: empties - 1, passed: false, ply: 1)
                }
            }
            if aborted {
                return false
            }
            solved[i].score = score
            alpha = max(alpha, score)
        }
        moves = Self.sortedByScore(solved)
        result.best = moves[0].square
        result.score = moves[0].score
        result.solved = true
        result.depth = empties
        return true
    }

    // MARK: - Middle game

    private func negamax(_ player: UInt64, _ opponent: UInt64, depth: Int, alpha alphaIn: Int, beta: Int, passed: Bool, ply: Int) -> Int {
        nodes &+= 1
        if nodes & 4095 == 0 && shouldStop() {
            aborted = true
        }
        if aborted {
            return 0
        }

        let moves = Bitboard.moves(player: player, opponent: opponent)
        if moves == 0 {
            if passed {
                return Self.finalScore(player, opponent)
            }
            // A pass costs no depth.
            return -negamax(opponent, player, depth: depth, alpha: -beta, beta: -alphaIn, passed: true, ply: ply + 1)
        }
        if depth <= 0 {
            return Evaluation.evaluate(player: player, opponent: opponent, moves: moves)
        }

        let key = Hashing.key(player: player, opponent: opponent)
        let entry = table[slot(key)]
        var ttMove = -1
        if entry.key == key && !entry.solved {
            ttMove = Int(entry.move)
            if Int(entry.depth) >= depth {
                let score = Int(entry.score)
                if entry.bound == .exact || (entry.bound == .lower && score >= beta) || (entry.bound == .upper && score <= alphaIn) {
                    return score
                }
            }
        }

        // Best first: the move that was best here before, then those that leave the opponent the fewest replies.
        let list = candidates + ply * 64
        var count = 0
        var bits = moves
        while bits != 0 {
            let square = bits.trailingZeroBitCount
            bits &= bits - 1
            let flips = Bitboard.flips(square: square, player: player, opponent: opponent)
            var order = Evaluation.squareValue[square]
            if square == ttMove {
                order = Self.infinity
            } else if depth >= 2 {
                order = 8 * order - 64 * Bitboard.moves(player: opponent & ~flips, opponent: player | flips | Squares.bit(square)).nonzeroBitCount
            }
            list[count] = Candidate(square: square, flips: flips, order: order)
            count += 1
        }

        var alpha = alphaIn
        var best = -Self.infinity
        var bestMove = -1
        for i in 0..<count {
            Self.bringBestForward(list, from: i, count: count)
            let move = list[i]
            let nextPlayer = opponent & ~move.flips
            let nextOpponent = player | move.flips | Squares.bit(move.square)
            var score: Int
            if i == 0 {
                score = -negamax(nextPlayer, nextOpponent, depth: depth - 1, alpha: -beta, beta: -alpha, passed: false, ply: ply + 1)
            } else {
                score = -negamax(nextPlayer, nextOpponent, depth: depth - 1, alpha: -alpha - 1, beta: -alpha, passed: false, ply: ply + 1)
                if score > alpha && score < beta {
                    score = -negamax(nextPlayer, nextOpponent, depth: depth - 1, alpha: -beta, beta: -alpha, passed: false, ply: ply + 1)
                }
            }
            if aborted {
                return 0
            }
            if score > best {
                best = score
                bestMove = move.square
            }
            if score > alpha {
                alpha = score
                if alpha >= beta {
                    break
                }
            }
        }
        store(key, depth: depth, score: best, bound: best >= beta ? .lower : best > alphaIn ? .exact : .upper, move: bestMove, solved: false)
        return best
    }

    // MARK: - End game

    private func solve(_ player: UInt64, _ opponent: UInt64, alpha alphaIn: Int, beta betaIn: Int, empties: Int, passed: Bool, ply: Int) -> Int {
        if empties <= 6 {
            return solveSmall(player, opponent, alpha: alphaIn, beta: betaIn, empties: empties, passed: passed)
        }
        nodes &+= 1
        if nodes & 4095 == 0 && shouldStop() {
            aborted = true
        }
        if aborted {
            return 0
        }

        let moves = Bitboard.moves(player: player, opponent: opponent)
        if moves == 0 {
            if passed {
                return player.nonzeroBitCount - opponent.nonzeroBitCount
            }
            return -solve(opponent, player, alpha: -betaIn, beta: -alphaIn, empties: empties, passed: true, ply: ply + 1)
        }

        let key = Hashing.key(player: player, opponent: opponent)
        let entry = table[slot(key)]
        var alpha = alphaIn
        var beta = betaIn
        var ttMove = -1
        if entry.key == key && entry.solved {
            ttMove = Int(entry.move)
            let score = Int(entry.score)
            if entry.bound == .exact || (entry.bound == .lower && score >= beta) || (entry.bound == .upper && score <= alpha) {
                return score
            }
            if entry.bound == .lower {
                alpha = max(alpha, score)
            } else if entry.bound == .upper {
                beta = min(beta, score)
            }
        }

        // Fastest first: the moves that leave the opponent the fewest replies, corners and the odd quarters breaking ties.
        let odd = Self.oddQuarters(~(player | opponent))
        let list = candidates + ply * 64
        var count = 0
        var bits = moves
        while bits != 0 {
            let square = bits.trailingZeroBitCount
            bits &= bits - 1
            let bit = Squares.bit(square)
            let flips = Bitboard.flips(square: square, player: player, opponent: opponent)
            let nextPlayer = opponent & ~flips
            let nextOpponent = player | flips | bit
            var order: Int
            if empties >= 12 {
                let replies = Bitboard.moves(player: nextPlayer, opponent: nextOpponent)
                order = -Evaluation.evaluate(player: nextPlayer, opponent: nextOpponent, moves: replies) - 200 * replies.nonzeroBitCount
            } else {
                order = -16 * Bitboard.moves(player: nextPlayer, opponent: nextOpponent).nonzeroBitCount
                    + (bit & Evaluation.corners != 0 ? 12 : 0) + (bit & odd != 0 ? 3 : 0)
            }
            if square == ttMove {
                order = Self.infinity
            }
            list[count] = Candidate(square: square, flips: flips, order: order)
            count += 1
        }

        let alphaBefore = alpha
        var best = -Self.infinity
        var bestMove = -1
        for i in 0..<count {
            Self.bringBestForward(list, from: i, count: count)
            let move = list[i]
            let nextPlayer = opponent & ~move.flips
            let nextOpponent = player | move.flips | Squares.bit(move.square)
            var score: Int
            if i == 0 {
                score = -solve(nextPlayer, nextOpponent, alpha: -beta, beta: -alpha, empties: empties - 1, passed: false, ply: ply + 1)
            } else {
                score = -solve(nextPlayer, nextOpponent, alpha: -alpha - 1, beta: -alpha, empties: empties - 1, passed: false, ply: ply + 1)
                if score > alpha && score < beta {
                    score = -solve(nextPlayer, nextOpponent, alpha: -beta, beta: -alpha, empties: empties - 1, passed: false, ply: ply + 1)
                }
            }
            if aborted {
                return 0
            }
            if score > best {
                best = score
                bestMove = move.square
            }
            if score > alpha {
                alpha = score
                if alpha >= beta {
                    break
                }
            }
        }
        store(key, depth: empties, score: best, bound: best >= beta ? .lower : best > alphaBefore ? .exact : .upper, move: bestMove, solved: true)
        return best
    }

    /// The last few empty squares: no table and no sorting, only the quarters with an odd number of empty squares
    /// first; the empty squares are tried one by one rather than the moves generated.
    private func solveSmall(_ player: UInt64, _ opponent: UInt64, alpha alphaIn: Int, beta: Int, empties: Int, passed: Bool) -> Int {
        nodes &+= 1
        if empties == 1 {
            return Self.lastMove(player, opponent)
        }
        let empty = ~(player | opponent)
        let odd = Self.oddQuarters(empty)
        var alpha = alphaIn
        var best = -Self.infinity
        for group in 0..<2 {
            var bits = group == 0 ? empty & odd : empty & ~odd
            while bits != 0 {
                let square = bits.trailingZeroBitCount
                bits &= bits - 1
                if Evaluation.neighbourMasks[square] & opponent == 0 {
                    continue
                }
                let flips = Bitboard.flips(square: square, player: player, opponent: opponent)
                if flips == 0 {
                    continue
                }
                let score = -solveSmall(opponent & ~flips, player | flips | Squares.bit(square), alpha: -beta, beta: -alpha, empties: empties - 1, passed: false)
                if score > best {
                    best = score
                    if score > alpha {
                        alpha = score
                        if alpha >= beta {
                            return best
                        }
                    }
                }
            }
        }
        if best == -Self.infinity {
            // No move: a pass, or the end.
            if passed {
                return player.nonzeroBitCount - opponent.nonzeroBitCount
            }
            return -solveSmall(opponent, player, alpha: -beta, beta: -alpha, empties: empties, passed: true)
        }
        return best
    }

    // MARK: - Helpers

    private func shouldStop() -> Bool { stop.isStopped || clock.now >= deadline }

    private func slot(_ key: UInt64) -> Int { Int(truncatingIfNeeded: key) & tableMask }

    private func store(_ key: UInt64, depth: Int, score: Int, bound: Bound, move: Int, solved: Bool) {
        let index = slot(key)
        let entry = table[index]
        if entry.key == key && Int(entry.depth) > depth && entry.solved == solved && bound != .exact {
            return
        }
        table[index] = Entry(key: key, score: Int32(score), depth: Int8(min(max(depth, 0), 120)), bound: bound, move: Int8(move), solved: solved)
    }

    /// One step of a selection sort: the move of the highest order from `first` on is swapped to `first`.
    private static func bringBestForward(_ list: UnsafeMutablePointer<Candidate>, from first: Int, count: Int) {
        var top = first
        for j in first + 1 ..< count where list[j].order > list[top].order {
            top = j
        }
        if top != first {
            let moving = list[first]
            list[first] = list[top]
            list[top] = moving
        }
    }

    /// The quarters of the board with an odd number of the empty squares.
    private static func oddQuarters(_ empty: UInt64) -> UInt64 {
        var odd: UInt64 = 0
        for quarter in Evaluation.quarters where (empty & quarter).nonzeroBitCount & 1 == 1 {
            odd |= quarter
        }
        return odd
    }

    private static func finalScore(_ player: UInt64, _ opponent: UInt64) -> Int {
        let difference = player.nonzeroBitCount - opponent.nonzeroBitCount
        return difference > 0 ? win + difference : difference < 0 ? -win + difference : 0
    }

    /// The last empty square, filled by whichever side can: the final difference in discs.
    private static func lastMove(_ player: UInt64, _ opponent: UInt64) -> Int {
        let square = (~(player | opponent)).trailingZeroBitCount
        let before = 2 * player.nonzeroBitCount - 63
        let flips = Bitboard.flips(square: square, player: player, opponent: opponent)
        if flips != 0 {
            return before + 2 * flips.nonzeroBitCount + 1
        }
        let replies = Bitboard.flips(square: square, player: opponent, opponent: player)
        if replies != 0 {
            return before - 2 * replies.nonzeroBitCount - 1
        }
        return before
    }

    /// Sorted from the best score down; moves of equal score keep their order.
    private static func sortedByScore(_ moves: [RootMove]) -> [RootMove] {
        moves.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element)
    }

    /// An index drawn with the chances in proportion to the weights.
    private static func weightedIndex(_ weights: [Double], using random: inout SplitMix64) -> Int {
        let total = weights.reduce(0, +)
        var remaining = Double.random(in: 0..<total, using: &random)
        for (index, weight) in weights.enumerated() {
            remaining -= weight
            if remaining < 0 {
                return index
            }
        }
        return weights.count - 1
    }
}
