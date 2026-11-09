/// A rectangle of the window in pixels, from its top left corner.
struct ScreenRect {
    var x: Float
    var y: Float
    var width: Float
    var height: Float

    var right: Float { x + width }
    var bottom: Float { y + height }

    func contains(_ px: Float, _ py: Float) -> Bool { px >= x && px < x + width && py >= y && py < y + height }

    func inset(by d: Float) -> ScreenRect { ScreenRect(x: x + d, y: y + d, width: width - 2 * d, height: height - 2 * d) }
}
