/// The coordinates inlaid in the board's frame, as coverage over the square from -extent to extent in x and z: the
/// letters along the near and far sides, the digits along the left and right, each side's turned to face the player
/// sitting there. The rows count from the far side of the default view, as from the top of a printed board.
@MainActor
enum BoardLabels {
    static func render(size: Int, extent: Float, inner: Float) -> [UInt8] {
        var coverage = [UInt8](repeating: 0, count: size * size)
        let pixelsPerUnit = Float(size) / (2 * extent)
        let height = Float(Int(0.3 * pixelsPerUnit))
        let middle = (inner + extent) / 2 - 0.02
        func toPixel(_ world: Float) -> Int { Int(((world + extent) * pixelsPerUnit).rounded()) }

        let font = GlyphRasterizer.labelFont(size: height)
        // Half the height of the capitals, in world units, by which the characters are centered on their points.
        let capHeight = GlyphRasterizer.capHeight(font)
        let halfCap = (capHeight > 0 ? capHeight : 0.7 * height) * 0.5 / pixelsPerUnit

        func draw(_ character: Unicode.Scalar, x: Float, z: Float, fromNearSide: Bool) {
            guard let found = GlyphRasterizer.glyph(for: character, in: font) else { return }
            let bitmap = GlyphRasterizer.render(found.glyph, in: found.font)
            guard !bitmap.isBlank else { return }
            // Centered on the point: the baseline below it for the near side, above it for the far side, which sees it
            // turned half round about the middle of its baseline.
            let originX = toPixel(x)
            let baseline = toPixel(z + (fromNearSide ? halfCap : -halfCap))
            let left = originX - bitmap.advance / 2 + bitmap.left
            let top = baseline - bitmap.top
            for row in 0..<bitmap.height {
                for column in 0..<bitmap.width {
                    var px = left + column
                    var py = top + row
                    if !fromNearSide {
                        px = 2 * originX - 1 - px
                        py = 2 * baseline - 1 - py
                    }
                    guard (0..<size).contains(px), (0..<size).contains(py) else { continue }
                    let index = py * size + px
                    coverage[index] = max(coverage[index], bitmap.coverage[row * bitmap.width + column])
                }
            }
        }

        for i in 0..<8 {
            let offset = Float(i) - 3.5
            let letter = Unicode.Scalar(UInt8(ascii: "a") + UInt8(i))
            let digit = Unicode.Scalar(UInt8(ascii: "1") + UInt8(i))
            draw(letter, x: offset, z: middle, fromNearSide: true)
            draw(letter, x: offset, z: -middle, fromNearSide: false)
            draw(digit, x: -middle, z: offset, fromNearSide: true)
            draw(digit, x: middle, z: offset, fromNearSide: false)
        }
        return coverage
    }
}
