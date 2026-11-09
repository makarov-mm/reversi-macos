import AppKit
import CoreText

/// Fonts found by Core Text, and their glyphs drawn into coverage bitmaps with anti-aliasing and without the
/// thickening of macOS's font smoothing, so that the text looks the same on any background. Used on the
/// main thread, as the rest of the interface.
@MainActor
enum GlyphRasterizer {
    /// The interface's typeface, the system's: San Francisco, which has the Latin and Cyrillic letters.
    static func interfaceFont(size: Float, semibold: Bool) -> CTFont {
        NSFont.systemFont(ofSize: CGFloat(size), weight: semibold ? .semibold : .regular) as CTFont
    }

    /// The serif of the coordinates inlaid in the frame: Georgia, as in the Linux version, or another serif.
    static func labelFont(size: Float) -> CTFont {
        for name in ["Georgia-Bold", "TimesNewRomanPS-BoldMT", "Times-Bold"] {
            let font = CTFontCreateWithName(name as CFString, CGFloat(size), nil)
            if CTFontCopyPostScriptName(font) as String == name {
                return font
            }
        }
        return NSFont.boldSystemFont(ofSize: CGFloat(size)) as CTFont
    }

    /// The glyph of a character in the font, or in the system's font that fills in for it; nil when none has it.
    static func glyph(for scalar: Unicode.Scalar, in font: CTFont) -> (font: CTFont, glyph: CGGlyph)? {
        let units = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        if CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs[0] != 0 {
            return (font, glyphs[0])
        }
        let substitute = CTFontCreateForString(font, String(scalar) as CFString, CFRange(location: 0, length: units.count))
        if CTFontGetGlyphsForCharacters(substitute, units, &glyphs, units.count), glyphs[0] != 0 {
            return (substitute, glyphs[0])
        }
        return nil
    }

    static func ascent(_ font: CTFont) -> Float { Float(CTFontGetAscent(font)) }
    static func descent(_ font: CTFont) -> Float { Float(CTFontGetDescent(font)) }
    static func capHeight(_ font: CTFont) -> Float { Float(CTFontGetCapHeight(font)) }

    /// The glyph's coverage, in a bitmap a pixel wider on every side than its outline, so that nothing is cut off.
    static func render(_ glyph: CGGlyph, in font: CTFont) -> GlyphBitmap {
        var glyphs = [glyph]
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advance, 1)
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, &bounds, 1)

        var bitmap = GlyphBitmap()
        bitmap.advance = Int(advance.width.rounded())
        guard bounds.width > 0, bounds.height > 0 else { return bitmap }
        let left = Int(bounds.minX.rounded(.down)) - 1
        let bottom = Int(bounds.minY.rounded(.down)) - 1
        let right = Int(bounds.maxX.rounded(.up)) + 1
        let top = Int(bounds.maxY.rounded(.up)) + 1
        bitmap.left = left
        bitmap.top = top
        bitmap.width = right - left
        bitmap.height = top - bottom
        var coverage = [UInt8](repeating: 0, count: bitmap.width * bitmap.height)
        coverage.withUnsafeMutableBytes { pixels in
            guard let context = CGContext(data: pixels.baseAddress, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                                          bytesPerRow: bitmap.width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(false)
            context.setShouldSmoothFonts(false)
            context.setFillColor(gray: 1, alpha: 1)
            // The context counts up from its bottom row; the bitmap's rows are kept from the top.
            var position = [CGPoint(x: CGFloat(-left), y: CGFloat(-bottom))]
            CTFontDrawGlyphs(font, &glyphs, &position, 1, context)
        }
        bitmap.coverage = coverage
        return bitmap
    }
}
