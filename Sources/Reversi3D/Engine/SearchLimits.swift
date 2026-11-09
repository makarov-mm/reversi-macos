/// How long and how deep the engine searches, and how much it may stray from its best move.
struct SearchLimits: Sendable {
    var maxDepth = 60
    /// Iterative deepening stops when this runs out.
    var milliseconds = 1000
    /// From this many empty squares the game is played out to the end, exactly.
    var exactEmpties = 0
    /// A random move among those this close to the best, for the weaker levels.
    var randomMargin = 0
    var seed: UInt64 = 0
}
