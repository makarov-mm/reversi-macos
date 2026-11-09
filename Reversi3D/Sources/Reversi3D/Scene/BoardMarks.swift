/// Squares marked on the board, as bitboards.
struct BoardMarks {
    /// Where the side to move can play.
    var legal: UInt64 = 0
    /// The legal square under the pointer.
    var hover: UInt64 = 0
    var lastMove: UInt64 = 0
    var hint: UInt64 = 0
}
