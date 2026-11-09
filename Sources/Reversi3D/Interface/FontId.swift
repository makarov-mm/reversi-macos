/// The interface's three fonts; the raw value is the font's slot in the interface shader.
enum FontId: Int, CaseIterable {
    case body = 0
    case heading = 1
    case display = 2

    /// The height of the em in pixels at the scale 1, and the weight.
    var size: Float {
        switch self {
        case .body: 15
        case .heading: 19
        case .display: 31
        }
    }

    var isSemibold: Bool { self != .body }
}
