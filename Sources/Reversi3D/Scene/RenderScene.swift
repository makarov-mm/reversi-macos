import simd

/// Everything the renderer draws in a frame, but the interface.
struct RenderScene {
    var view = Matrix.identity
    var projection = Matrix.identity
    var eye = SIMD3<Float>(repeating: 0)
    var time: Float = 0
    var discs: [DiscDraw] = []
    /// The disc that a click would place, seen through.
    var ghost: DiscDraw?
    var contacts: [ContactShadow] = []
    var marks = BoardMarks()
    var panels: [FrostedPanel] = []
}
