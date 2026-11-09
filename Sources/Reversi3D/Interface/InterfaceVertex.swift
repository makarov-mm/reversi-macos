/// A vertex of the interface, laid out as the interface shader reads it: 36 bytes.
struct InterfaceVertex {
    var x: Float
    var y: Float
    var u: Float
    var v: Float
    var color: RGBA
    /// What to draw, and three numbers that depend on it; see Interface.metal.
    var kind: Float
    var p1: Float
    var p2: Float
    var p3: Float
}
