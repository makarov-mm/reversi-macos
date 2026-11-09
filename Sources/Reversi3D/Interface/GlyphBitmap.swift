/// A glyph drawn into eight-bit coverage, rows from the top.
struct GlyphBitmap {
    var width = 0
    var height = 0
    /// From the pen to the left edge, and up from the baseline to the top edge.
    var left = 0
    var top = 0
    var advance = 0
    var coverage: [UInt8] = []

    var isBlank: Bool { width == 0 || height == 0 }
}
