/// Whether the game goes on or how it ended, and the discs on the board.
struct GameStatus: Equatable, Sendable {
    enum Result: Sendable {
        case ongoing
        case blackWins
        case whiteWins
        case draw
    }

    var result: Result = .ongoing
    var black = 0
    var white = 0

    var isOver: Bool { result != .ongoing }
}
