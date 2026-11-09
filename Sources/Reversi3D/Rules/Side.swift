/// The color of a player's discs. Black moves first.
enum Side: Sendable {
    case black
    case white

    var opposite: Side { self == .black ? .white : .black }
}
