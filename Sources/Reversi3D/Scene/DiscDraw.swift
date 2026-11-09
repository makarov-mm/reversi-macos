import simd

/// A disc to draw: its two halves, each in the look of its color.
struct DiscDraw {
    var model = Matrix.identity
    /// The height of what it stands on.
    var ground: Float = 0
    var glowColor = SIMD3<Float>(repeating: 0)
    var glow: Float = 0
    var dissolve: Float = 0
    /// Where the grain falls.
    var seed: Float = 0
    /// The disc placed last.
    var mark: Float = 0
    var opacity: Float = 1
}
