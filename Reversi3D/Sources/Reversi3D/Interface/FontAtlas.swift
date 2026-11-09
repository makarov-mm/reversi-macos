import CoreText
import Metal

/// A font at one pixel size, its glyphs drawn into a texture: the Latin and Cyrillic letters and a few symbols, the
/// ones the typeface lacks taken from the fonts that fill in for it. Text is laid out from its metrics, a pixel grid
/// for every glyph.
@MainActor
struct FontAtlas {
    struct Glyph {
        // In the atlas.
        var u0: Float = 0
        var v0: Float = 0
        var u1: Float = 0
        var v1: Float = 0
        /// The quad, in pixels; none for a space.
        var width: Float = 0
        var height: Float = 0
        /// From the pen and the line's top to the quad.
        var left: Float = 0
        var top: Float = 0
        var advance: Float = 0
    }

    let texture: MTLTexture
    let lineHeight: Float
    let ascent: Float
    private let glyphs: [Unicode.Scalar: Glyph]
    private let fallback: Glyph

    /// The characters in the atlas.
    private static let scalars: [Unicode.Scalar] = {
        var values = Array(0x20..<0x7F) + Array(0x410...0x44F)
        values += [0x401, 0x451, 0x2014, 0x2013, 0x2026, 0x2022, 0x00B7, 0x2190, 0x2192, 0x2191, 0x2193, 0x00A0, 0x00A9, 0x00D7, 0x00BD,
                   0x00AB, 0x00BB, 0x2116, 0x2197, 0x21B6, 0x21B7, 0x25B2, 0x25BC, 0x25C0, 0x25B6]
        // The keys of a Mac: command, shift, control, option and delete.
        values += [0x2318, 0x21E7, 0x2303, 0x2325, 0x232B]
        return values.compactMap { Unicode.Scalar(UInt32($0)) }
    }()

    /// The interface's typeface with an em of `pixelHeight` pixels.
    init(device: MTLDevice, queue: MTLCommandQueue, pixelHeight: Float, semibold: Bool) throws {
        let font = GlyphRasterizer.interfaceFont(size: max(6, pixelHeight.rounded()), semibold: semibold)
        let ascent = Int(GlyphRasterizer.ascent(font).rounded(.up))
        let descent = Int(GlyphRasterizer.descent(font).rounded(.up))
        self.ascent = Float(ascent)
        lineHeight = Float(ascent + descent)

        var items: [(scalar: Unicode.Scalar, bitmap: GlyphBitmap)] = []
        for scalar in Self.scalars {
            if let found = GlyphRasterizer.glyph(for: scalar, in: font) {
                items.append((scalar, GlyphRasterizer.render(found.glyph, in: found.font)))
            }
        }

        // Shelves of glyphs, each with a pixel of room round it, so that filtering does not reach the next one.
        let pad = 1
        var places = [(x: Int, y: Int)](repeating: (0, 0), count: items.count)
        var atlasWidth = 128
        var atlasHeight = 1
        while true {
            var x = 0
            var y = 0
            var shelf = 0
            for (index, item) in items.enumerated() where !item.bitmap.isBlank {
                let cellWidth = item.bitmap.width + 2 * pad
                let cellHeight = item.bitmap.height + 2 * pad
                if x + cellWidth > atlasWidth {
                    x = 0
                    y += shelf
                    shelf = 0
                }
                places[index] = (x, y)
                x += cellWidth
                shelf = max(shelf, cellHeight)
            }
            atlasHeight = max(1, y + shelf)
            if atlasHeight <= atlasWidth {
                break
            }
            atlasWidth *= 2
        }

        var atlas = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        for (index, item) in items.enumerated() where !item.bitmap.isBlank {
            for row in 0..<item.bitmap.height {
                let from = row * item.bitmap.width
                let to = (places[index].y + pad + row) * atlasWidth + places[index].x + pad
                atlas.replaceSubrange(to..<(to + item.bitmap.width), with: item.bitmap.coverage[from..<(from + item.bitmap.width)])
            }
        }
        texture = try TextureUpload.coverage(device: device, queue: queue, pixels: atlas, width: atlasWidth, height: atlasHeight,
                                             mipmapped: false, label: semibold ? "semibold font" : "regular font")

        var glyphs: [Unicode.Scalar: Glyph] = [:]
        let w = Float(atlasWidth)
        let h = Float(atlasHeight)
        for (index, item) in items.enumerated() {
            var glyph = Glyph()
            glyph.advance = Float(item.bitmap.advance)
            if !item.bitmap.isBlank {
                let cellWidth = item.bitmap.width + 2 * pad
                let cellHeight = item.bitmap.height + 2 * pad
                glyph.u0 = Float(places[index].x) / w
                glyph.v0 = Float(places[index].y) / h
                glyph.u1 = Float(places[index].x + cellWidth) / w
                glyph.v1 = Float(places[index].y + cellHeight) / h
                glyph.width = Float(cellWidth)
                glyph.height = Float(cellHeight)
                glyph.left = Float(item.bitmap.left - pad)
                glyph.top = Float(ascent - item.bitmap.top - pad)
            }
            glyphs[item.scalar] = glyph
        }
        self.glyphs = glyphs
        fallback = glyphs["?"] ?? Glyph()
    }

    func glyph(_ scalar: Unicode.Scalar) -> Glyph { glyphs[scalar] ?? fallback }

    func measure(_ text: String) -> Float {
        text.unicodeScalars.reduce(0) { $0 + glyph($1).advance }
    }
}
