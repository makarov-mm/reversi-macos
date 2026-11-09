import Metal

/// Draws the interface: rounded panels, shadows, text and the program's icon, in pixels from the window's top left
/// corner. The shapes and the text of a frame are gathered, then drawn at once over the finished scene.
@MainActor
final class Painter {
    private let device: MTLDevice
    private var fonts: [FontAtlas] = []
    private let icon: MTLTexture
    private let hasIcon: Bool
    private var vertices: [InterfaceVertex] = []
    /// One vertex buffer for each frame the GPU may still be drawing.
    private var buffers: [MTLBuffer?]
    private var width: Float = 1
    private var height: Float = 1

    init(device: MTLDevice, queue: MTLCommandQueue, icon: IconImage?, framesInFlight: Int) throws {
        self.device = device
        if let icon {
            self.icon = try TextureUpload.rgba(device: device, queue: queue, pixels: icon.premultipliedPixels, width: icon.width,
                                               height: icon.height, mipmapped: true, label: "icon")
            hasIcon = true
        } else {
            self.icon = try TextureUpload.rgba(device: device, queue: queue, pixels: [0, 0, 0, 0], width: 1, height: 1, mipmapped: false,
                                               label: "no icon")
            hasIcon = false
        }
        buffers = Array(repeating: nil, count: framesInFlight)
    }

    /// The body, heading and display fonts, in the order of `FontId`.
    func setFonts(_ fonts: [FontAtlas]) {
        precondition(fonts.count == FontId.allCases.count, "a font for each FontId")
        self.fonts = fonts
    }

    func font(_ id: FontId) -> FontAtlas { fonts[id.rawValue] }

    func begin(width: Int, height: Int) {
        self.width = Float(max(width, 1))
        self.height = Float(max(height, 1))
        vertices.removeAll(keepingCapacity: true)
    }

    // MARK: - Shapes

    func fill(_ rect: ScreenRect, radius: Float, color: RGBA) {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        shape(rect, margin: 1, color: color, SIMD4(3, rect.width / 2, rect.height / 2, radius))
    }

    func outline(_ rect: ScreenRect, radius: Float, color: RGBA) {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        shape(rect, margin: 1, color: color, SIMD4(5, rect.width / 2, rect.height / 2, radius))
    }

    func shadow(_ rect: ScreenRect, blur: Float, color: RGBA) {
        shape(rect, margin: blur * 1.5, color: color, SIMD4(4, rect.width / 2, rect.height / 2, blur))
    }

    func disc(x: Float, y: Float, radius: Float, color: RGBA) {
        shape(ScreenRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2), margin: 1, color: color, SIMD4(7, radius, 0, 0))
    }

    func spinner(x: Float, y: Float, radius: Float, thickness: Float, angle: Float, color: RGBA) {
        shape(ScreenRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2), margin: thickness, color: color,
              SIMD4(6, radius, thickness, angle))
    }

    /// A small triangle pointing left (direction -1) or right (1).
    func arrow(x: Float, y: Float, halfWidth: Float, halfHeight: Float, direction: Float, color: RGBA) {
        shape(ScreenRect(x: x - halfWidth, y: y - halfHeight, width: halfWidth * 2, height: halfHeight * 2), margin: 1, color: color,
              SIMD4(8, halfWidth, halfHeight, direction))
    }

    func icon(_ rect: ScreenRect, opacity: Float = 1) {
        if hasIcon {
            quad(rect.x, rect.y, rect.right, rect.bottom, 0, 0, 1, 1, RGBA(255, 255, 255).faded(opacity), SIMD4(9, 0, 0, 0))
        }
    }

    // MARK: - Text

    /// Text whose line starts at the top left point; returns its width.
    @discardableResult
    func text(_ id: FontId, x: Float, y: Float, _ text: String, color: RGBA) -> Float {
        let font = self.font(id)
        let kind = Float(id.rawValue)
        var pen = x.rounded()
        let top = y.rounded()
        for scalar in text.unicodeScalars {
            let glyph = font.glyph(scalar)
            let left = (pen + glyph.left).rounded()
            let glyphTop = top + glyph.top
            if glyph.width > 0 {
                quad(left, glyphTop, left + glyph.width, glyphTop + glyph.height, glyph.u0, glyph.v0, glyph.u1, glyph.v1, color, SIMD4(kind, 0, 0, 0))
            }
            pen += glyph.advance
        }
        return pen - x.rounded()
    }

    func textCentered(_ id: FontId, in rect: ScreenRect, _ text: String, color: RGBA) {
        let width = measure(id, text)
        let height = font(id).ascent
        self.text(id, x: rect.x + (rect.width - width) / 2, y: rect.y + (rect.height - height) / 2 - height * 0.04, text, color: color)
    }

    func measure(_ id: FontId, _ text: String) -> Float { font(id).measure(text) }

    func lineHeight(_ id: FontId) -> Float { font(id).lineHeight }

    /// The text, cut short with an ellipsis where it is wider than `width`, after the last character that fits and is
    /// not a space or a separator.
    func elided(_ id: FontId, _ text: String, width: Float) -> String {
        let font = self.font(id)
        if font.measure(text) <= width {
            return text
        }
        let room = width - font.glyph("…").advance
        let scalars = text.unicodeScalars
        var used: Float = 0
        var kept = scalars.startIndex
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            index = scalars.index(after: index)
            used += font.glyph(scalar).advance
            if used > room {
                break
            }
            if scalar != " " && scalar != "·" {
                kept = index
            }
        }
        return String(scalars[..<kept]) + "…"
    }

    // MARK: - Drawing

    /// Draws what was gathered since `begin`, with the interface pipeline already set on the encoder.
    func encode(_ encoder: MTLRenderCommandEncoder, frameIndex: Int) {
        guard !vertices.isEmpty, fonts.count == FontId.allCases.count else { return }
        let length = vertices.count * MemoryLayout<InterfaceVertex>.stride
        if (buffers[frameIndex]?.length ?? 0) < length {
            // Room for more, so that the buffer is not made again for every few more letters.
            buffers[frameIndex] = device.makeBuffer(length: max(length * 2, 1 << 16), options: .storageModeShared)
            buffers[frameIndex]?.label = "interface vertices"
        }
        guard let buffer = buffers[frameIndex] else { return }
        vertices.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: length) }
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexValue(SIMD4<Float>(width, height, 0, 0), index: 1)
        for id in FontId.allCases {
            encoder.setFragmentTexture(font(id).texture, index: id.rawValue)
        }
        encoder.setFragmentTexture(icon, index: 3)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func quad(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ u0: Float, _ v0: Float, _ u1: Float, _ v1: Float, _ color: RGBA,
                      _ shape: SIMD4<Float>) {
        func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) -> InterfaceVertex {
            InterfaceVertex(x: x, y: y, u: u, v: v, color: color, kind: shape.x, p1: shape.y, p2: shape.z, p3: shape.w)
        }
        let a = vertex(x0, y0, u0, v0)
        let b = vertex(x1, y0, u1, v0)
        let c = vertex(x1, y1, u1, v1)
        let d = vertex(x0, y1, u0, v1)
        vertices += [a, b, c, a, c, d]
    }

    /// A quad round a rectangle, its texture coordinates the position from the rectangle's center, for the shapes
    /// drawn from their distance functions.
    private func shape(_ rect: ScreenRect, margin: Float, color: RGBA, _ shape: SIMD4<Float>) {
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2
        quad(rect.x - margin, rect.y - margin, rect.right + margin, rect.bottom + margin, -halfWidth - margin, -halfHeight - margin,
             halfWidth + margin, halfHeight + margin, color, shape)
    }
}
