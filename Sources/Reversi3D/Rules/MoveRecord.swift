/// A move as played: the square (or a pass), who played it and the discs it turned over.
struct MoveRecord: Equatable, Sendable {
    var square: Square = Squares.pass
    var side: Side = .black
    var flipped: UInt64 = 0

    var isPass: Bool { square == Squares.pass }
}
