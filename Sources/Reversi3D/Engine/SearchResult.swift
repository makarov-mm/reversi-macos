/// The move the engine chose and what it knows about it.
struct SearchResult: Sendable {
    var best: Square = Squares.pass
    /// For the side to move: the evaluation, or the final difference in discs when solved.
    var score = 0
    var depth = 0
    /// The score is exact.
    var solved = false
    var nodes: UInt64 = 0
}
