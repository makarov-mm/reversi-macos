import Foundation
import Metal
import QuartzCore
import simd

/// Draws the scene into the window: shadows, reflections, the lit scene in high dynamic range with multisampling,
/// then bloom and tone mapping. The interface is drawn on top, in the last pass, by the caller.
@MainActor
final class Renderer {
    private static let shadowSize = 2048
    private static let shadowRadius: Float = 7.6
    private static let shadowNear: Float = 4
    private static let shadowFar: Float = 36
    static let labelSize = 2048
    private static let maxContacts = 72
    private static let maxFrostedPanels = 4
    static let framesInFlight = 3

    let device: MTLDevice
    let queue: MTLCommandQueue
    private let samples: Int

    private let shadowPipeline: MTLRenderPipelineState
    private let discPipeline: MTLRenderPipelineState
    private let ghostPipeline: MTLRenderPipelineState
    private let reflectionPipeline: MTLRenderPipelineState
    private let surfacePipeline: MTLRenderPipelineState
    private let backgroundPipeline: MTLRenderPipelineState
    private let resolvePipeline: MTLRenderPipelineState
    private let bloomDownPipeline: MTLRenderPipelineState
    private let bloomUpPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let interfacePipeline: MTLRenderPipelineState
    private let depthWrite: MTLDepthStencilState
    private let depthTest: MTLDepthStencilState

    private let white: GPUMesh
    private let black: GPUMesh
    private let simpleWhite: GPUMesh
    private let simpleBlack: GPUMesh
    private let simpleDisc: GPUMesh
    private let squares: GPUMesh
    private let frame: GPUMesh
    private let table: GPUMesh

    private let shadowMap: MTLTexture
    private let labels: MTLTexture
    private let probes: LightProbes
    private var targets: RenderTargets?

    private var theme = Themes.all[0]
    private var lightViewProjection = Matrix.identity
    private let inFlight: DispatchSemaphore
    private var frameIndex = 0

    /// `labels` is the coverage of the coordinates inlaid in the frame, `labelSize` squared, from `BoardLabels`.
    init(device: MTLDevice, drawableFormat: MTLPixelFormat, discShapes: DiscModel.Shapes, labels coverage: [UInt8]) throws {
        self.device = device
        inFlight = DispatchSemaphore(value: Self.framesInFlight)
        guard let queue = device.makeCommandQueue() else { throw RendererError.creationFailed("command queue") }
        queue.label = "3D Reversi"
        self.queue = queue
        samples = device.supportsTextureSampleCount(4) ? 4 : 1

        let library = try ShaderLibrary(device: device)
        let hdr = RenderTargets.hdrFormat
        let depth = RenderTargets.depthFormat
        let discLayout = Self.vertexLayout([(.float3, 0), (.float3, 12), (.float, 24)], stride: MemoryLayout<DiscVertex>.stride)
        let surfaceLayout = Self.vertexLayout([(.float3, 0), (.float3, 12), (.float2, 24)], stride: MemoryLayout<SurfaceVertex>.stride)
        // The shadow pass reads only the positions, first in the vertices of the discs and of the board alike.
        precondition(MemoryLayout<DiscVertex>.stride == MemoryLayout<SurfaceVertex>.stride, "the shadow pass reads both kinds of vertex")
        let positionLayout = Self.vertexLayout([(.float3, 0)], stride: MemoryLayout<DiscVertex>.stride)
        let interfaceLayout = Self.vertexLayout([(.float2, 0), (.float2, 8), (.uchar4Normalized, 16), (.float4, 20)],
                                                stride: MemoryLayout<InterfaceVertex>.stride)

        func pipeline(_ label: String, _ vertex: String, _ fragment: String, layout: MTLVertexDescriptor? = nil, color: MTLPixelFormat?,
                      depth: MTLPixelFormat = .invalid, samples: Int = 1, blend: Blend = .none) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunction = try library.function(vertex)
            descriptor.fragmentFunction = try library.function(fragment)
            descriptor.vertexDescriptor = layout
            descriptor.rasterSampleCount = samples
            descriptor.depthAttachmentPixelFormat = depth
            if let color {
                let attachment: MTLRenderPipelineColorAttachmentDescriptor = descriptor.colorAttachments[0]
                attachment.pixelFormat = color
                blend.apply(to: attachment)
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        shadowPipeline = try pipeline("shadow", "shadowVertex", "shadowFragment", layout: positionLayout, color: nil, depth: depth)
        discPipeline = try pipeline("disc", "discVertex", "discFragment", layout: discLayout, color: hdr, depth: depth, samples: samples)
        ghostPipeline = try pipeline("ghost disc", "discVertex", "discFragment", layout: discLayout, color: hdr, depth: depth, samples: samples,
                                     blend: .alpha)
        reflectionPipeline = try pipeline("reflected disc", "discVertex", "discFragment", layout: discLayout, color: hdr, depth: depth)
        surfacePipeline = try pipeline("surface", "surfaceVertex", "surfaceFragment", layout: surfaceLayout, color: hdr, depth: depth, samples: samples)
        backgroundPipeline = try pipeline("background", "fullscreenVertex", "backgroundFragment", color: hdr, depth: depth, samples: samples)
        resolvePipeline = try pipeline("resolve", "fullscreenVertex", "resolveFragment", color: hdr)
        bloomDownPipeline = try pipeline("bloom down", "fullscreenVertex", "bloomDownFragment", color: RenderTargets.bloomFormat)
        bloomUpPipeline = try pipeline("bloom up", "fullscreenVertex", "bloomUpFragment", color: RenderTargets.bloomFormat, blend: .additive)
        compositePipeline = try pipeline("composite", "fullscreenVertex", "compositeFragment", color: drawableFormat)
        interfacePipeline = try pipeline("interface", "interfaceVertex", "interfaceFragment", layout: interfaceLayout, color: drawableFormat,
                                         blend: .alpha)
        depthWrite = try Self.depthState(device, .less, write: true)
        depthTest = try Self.depthState(device, .lessEqual, write: false)

        white = try GPUMesh(device: device, mesh: discShapes.white, label: "white half")
        black = try GPUMesh(device: device, mesh: discShapes.black, label: "black half")
        simpleWhite = try GPUMesh(device: device, mesh: discShapes.simpleWhite, label: "plain white half")
        simpleBlack = try GPUMesh(device: device, mesh: discShapes.simpleBlack, label: "plain black half")
        simpleDisc = try GPUMesh(device: device, mesh: discShapes.simple, label: "plain disc")
        squares = try GPUMesh(device: device, mesh: BoardGeometry.squares(), label: "squares")
        frame = try GPUMesh(device: device, mesh: BoardGeometry.frame(), label: "frame")
        table = try GPUMesh(device: device, mesh: BoardGeometry.table(radius: 40), label: "table")

        // The shadow map, read both with comparison (for filtering) and without (to find the casters).
        let shadowDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depth, width: Self.shadowSize, height: Self.shadowSize,
                                                                        mipmapped: false)
        shadowDescriptor.usage = [.renderTarget, .shaderRead]
        shadowDescriptor.storageMode = .private
        guard let shadowMap = device.makeTexture(descriptor: shadowDescriptor) else { throw RendererError.creationFailed("shadow map") }
        shadowMap.label = "shadow map"
        self.shadowMap = shadowMap

        probes = try LightProbes(device: device, library: library, queue: queue)
        labels = try TextureUpload.coverage(device: device, queue: queue, pixels: coverage, width: Self.labelSize, height: Self.labelSize,
                                            mipmapped: true, label: "board labels")
    }

    func setTheme(_ theme: Theme) throws {
        self.theme = theme
        let toLight = normalize(theme.keyDirection)
        let up: SIMD3<Float> = abs(toLight.y) > 0.99 ? [0, 0, 1] : [0, 1, 0]
        let center = SIMD3<Float>(0.5, 0, 0)
        let view = Matrix.lookAt(eye: center + toLight * 20, target: center, up: up)
        let projection = Matrix.orthographic(left: -Self.shadowRadius, right: Self.shadowRadius, bottom: -Self.shadowRadius, top: Self.shadowRadius,
                                             near: Self.shadowNear, far: Self.shadowFar)
        lightViewProjection = projection * view
        try probes.bake(theme, queue: queue)
    }

    /// Draws a frame into the drawable and presents it. `overlay` draws the interface over the finished image, in the
    /// last pass; it is given the index of the frame among those the GPU may still be drawing.
    func render(_ scene: RenderScene, to drawable: CAMetalDrawable, overlay: (MTLRenderCommandEncoder, Int) -> Void) {
        let width = drawable.texture.width
        let height = drawable.texture.height
        if targets?.width != width || targets?.height != height {
            targets = try? RenderTargets(device: device, width: width, height: height, samples: samples)
        }
        guard let targets else { return }

        inFlight.wait()
        frameIndex = (frameIndex + 1) % Self.framesInFlight
        guard let commandBuffer = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        commandBuffer.label = "frame"
        Self.signal(inFlight, when: commandBuffer)

        let uniforms = frameUniforms(scene, width: width, height: height)
        drawShadowMap(scene, uniforms: uniforms, commandBuffer: commandBuffer)
        drawReflections(scene, uniforms: uniforms, targets: targets, commandBuffer: commandBuffer)
        drawMainPass(scene, uniforms: uniforms, targets: targets, commandBuffer: commandBuffer)
        drawBloom(targets: targets, commandBuffer: commandBuffer)
        drawFinalImage(scene, targets: targets, drawable: drawable, commandBuffer: commandBuffer, overlay: overlay)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Passes

    private func frameUniforms(_ scene: RenderScene, width: Int, height: Int) -> Uniforms.Frame {
        let viewProjection = scene.projection * scene.view
        return Uniforms.Frame(
            viewProjection: viewProjection,
            inverseViewProjection: viewProjection.inverse,
            lightViewProjection: lightViewProjection,
            cameraPosition: SIMD4(scene.eye, scene.time),
            lightDirection: SIMD4(normalize(theme.keyDirection), 2 * Self.shadowRadius / Float(Self.shadowSize)),
            lightColor: SIMD4(theme.keyRadiance, theme.keySoftness),
            shadowParams: SIMD4(Self.shadowFar - Self.shadowNear, 0.00025, 0, 0),
            viewport: SIMD4(Float(width), Float(height), 1 / Float(width), 1 / Float(height)),
            environment: SIMD4(theme.diffuseLight, theme.reflectedLight, Float(LightProbes.prefilteredLevels - 1), theme.background),
            accent: SIMD4(theme.accent, 1),
            accentWarm: SIMD4(theme.accentWarm, 1),
            fog: SIMD4(theme.fog, 0.05))
    }

    private func drawShadowMap(_ scene: RenderScene, uniforms: Uniforms.Frame, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "shadow map"
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setDepthStencilState(depthWrite)
        encoder.setCullMode(.none)
        encoder.setDepthBias(3, slopeScale: 1.5, clamp: 0)
        encoder.setVertexValue(uniforms, index: 1)

        let board = Uniforms.Shadow(model: Matrix.identity, dissolve: .zero)
        encoder.setVertexValue(board, index: 3)
        encoder.setFragmentValue(board, index: 3)
        frame.draw(encoder)
        squares.draw(encoder)
        for disc in scene.discs {
            let caster = Uniforms.Shadow(model: disc.model, dissolve: SIMD4(disc.dissolve, disc.seed, 0, 0))
            encoder.setVertexValue(caster, index: 3)
            encoder.setFragmentValue(caster, index: 3)
            simpleDisc.draw(encoder)
        }
        encoder.endEncoding()
    }

    /// The discs turned upside down under the board, seen from the camera as if from below it, at half size, then
    /// blurred into the mip levels so that the polish of each theme can show a sharper or softer reflection.
    private func drawReflections(_ scene: RenderScene, uniforms: Uniforms.Frame, targets: RenderTargets, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.reflectionColor
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = targets.reflectionDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "reflections"
        encoder.setRenderPipelineState(reflectionPipeline)
        encoder.setDepthStencilState(depthWrite)
        // Mirroring turns the winding of the triangles round.
        encoder.setFrontFacing(.clockwise)
        encoder.setCullMode(.back)
        bindLighting(encoder, uniforms: uniforms, reflection: nil) // the reflection is being drawn
        let mirrored = Uniforms.Pass(eye: SIMD4(scene.eye.x, -scene.eye.y, scene.eye.z, 1), mirror: SIMD4(0, 1, 0, 0))
        encoder.setVertexValue(mirrored, index: 2)
        encoder.setFragmentValue(mirrored, index: 2)
        for disc in scene.discs {
            drawDisc(disc, encoder: encoder, white: simpleWhite, black: simpleBlack)
        }
        encoder.endEncoding()

        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.label = "reflection blur"
        blit.generateMipmaps(for: targets.reflectionColor)
        blit.endEncoding()
    }

    /// The table, the board and the discs, lit by the key light and the baked environment; the background is the
    /// environment itself, and the disc a click would place is blended over it all.
    private func drawMainPass(_ scene: RenderScene, uniforms: Uniforms.Frame, targets: RenderTargets, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.sceneColor
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(theme.fog.x), green: Double(theme.fog.y), blue: Double(theme.fog.z), alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = targets.sceneDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "scene"
        encoder.setDepthStencilState(depthWrite)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        bindLighting(encoder, uniforms: uniforms, reflection: targets.reflectionColor)
        let view = Uniforms.Pass(eye: SIMD4(scene.eye, 0), mirror: .zero)
        encoder.setVertexValue(view, index: 2)
        encoder.setFragmentValue(view, index: 2)

        encoder.setRenderPipelineState(surfacePipeline)
        let contacts = scene.contacts.prefix(Self.maxContacts).map { SIMD4($0.x, $0.z, $0.radius, $0.strength) }
        encoder.setFragmentArray(contacts, placeholder: SIMD4<Float>.zero, index: 4)
        for (kind, mesh) in [(2, table), (1, frame), (0, squares)] {
            encoder.setFragmentValue(surfaceUniforms(scene.marks, kind: kind, contactCount: contacts.count), index: 3)
            mesh.draw(encoder)
        }

        encoder.setRenderPipelineState(discPipeline)
        for disc in scene.discs {
            drawDisc(disc, encoder: encoder, white: white, black: black)
        }

        // Behind everything drawn, at the far plane; clamped there rather than clipped.
        encoder.setDepthStencilState(depthTest)
        encoder.setDepthClipMode(.clamp)
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setDepthClipMode(.clip)

        if let ghost = scene.ghost {
            encoder.setRenderPipelineState(ghostPipeline)
            drawDisc(ghost, encoder: encoder, white: white, black: black)
        }
        encoder.endEncoding()
    }

    /// The samples resolved, and the bright parts spread: halved six times, then added back up.
    private func drawBloom(targets: RenderTargets, commandBuffer: MTLCommandBuffer) {
        fullscreenPass(commandBuffer, into: targets.resolved, label: "resolve") { encoder in
            encoder.setRenderPipelineState(resolvePipeline)
            encoder.setFragmentTexture(targets.sceneColor, index: 0)
        }?.endEncoding()
        for level in 0..<RenderTargets.bloomLevels {
            let source = level == 0 ? targets.resolved : targets.bloom[level - 1]
            fullscreenPass(commandBuffer, into: targets.bloom[level], label: "bloom down") { encoder in
                encoder.setRenderPipelineState(bloomDownPipeline)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentValue(Uniforms.Bloom(source: Self.texelSize(source, first: level == 0)), index: 0)
            }?.endEncoding()
        }
        for level in stride(from: RenderTargets.bloomLevels - 2, through: 0, by: -1) {
            let source = targets.bloom[level + 1]
            fullscreenPass(commandBuffer, into: targets.bloom[level], load: true, label: "bloom up") { encoder in
                encoder.setRenderPipelineState(bloomUpPipeline)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentValue(Uniforms.Bloom(source: Self.texelSize(source, first: false)), index: 0)
            }?.endEncoding()
        }
    }

    /// Tone mapping, vignetting and the frosted glass behind the interface's panels, then the interface itself.
    private func drawFinalImage(_ scene: RenderScene, targets: RenderTargets, drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer,
                                overlay: (MTLRenderCommandEncoder, Int) -> Void) {
        let panels = scene.panels.prefix(Self.maxFrostedPanels).map { panel in
            Uniforms.FrostedPanel(bounds: SIMD4(panel.rect.x + panel.rect.width / 2, panel.rect.y + panel.rect.height / 2,
                                                panel.rect.width / 2, panel.rect.height / 2),
                                  style: SIMD4(panel.radius, panel.opacity, 0, 0))
        }
        let width = Float(targets.width)
        let height = Float(targets.height)
        let composite = Uniforms.Composite(settings: SIMD4(theme.exposure, theme.bloom, theme.vignette, Float(panels.count)),
                                           viewport: SIMD4(width, height, 1 / width, 1 / height))
        let encoder = fullscreenPass(commandBuffer, into: drawable.texture, label: "final image") { encoder in
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentValue(composite, index: 0)
            encoder.setFragmentArray(panels, placeholder: Uniforms.FrostedPanel(bounds: .zero, style: .zero), index: 1)
            encoder.setFragmentTexture(targets.resolved, index: 0)
            encoder.setFragmentTexture(targets.bloom[0], index: 1)
            encoder.setFragmentTexture(targets.bloom[2], index: 2)
        }
        guard let encoder else { return }
        encoder.setRenderPipelineState(interfacePipeline)
        overlay(encoder, frameIndex)
        encoder.endEncoding()
    }

    // MARK: - Helpers

    private func bindLighting(_ encoder: MTLRenderCommandEncoder, uniforms: Uniforms.Frame, reflection: MTLTexture?) {
        encoder.setVertexValue(uniforms, index: 1)
        encoder.setFragmentValue(uniforms, index: 1)
        encoder.setFragmentTexture(shadowMap, index: 0)
        encoder.setFragmentTexture(probes.irradiance, index: 1)
        encoder.setFragmentTexture(probes.prefiltered, index: 2)
        encoder.setFragmentTexture(probes.brdf, index: 3)
        encoder.setFragmentTexture(reflection, index: 4)
        encoder.setFragmentTexture(labels, index: 5)
    }

    /// The two halves of a disc, each in the look of its color.
    private func drawDisc(_ disc: DiscDraw, encoder: MTLRenderCommandEncoder, white: GPUMesh, black: GPUMesh) {
        for (look, mesh) in [(theme.white, white), (theme.black, black)] {
            let uniforms = Uniforms.Disc(
                model: disc.model,
                albedo: SIMD4(look.albedo, 0),
                surface: SIMD4(look.roughness, look.metallic, look.clearcoat, look.clearcoatRoughness),
                style: SIMD4(look.subsurface, look.patternStrength, look.pattern, disc.ground),
                glow: SIMD4(disc.glowColor, disc.glow),
                trim: SIMD4(look.trim, look.trimStrength),
                dissolve: SIMD4(disc.dissolve, theme.accent.x, theme.accent.y, theme.accent.z),
                detail: SIMD4(disc.seed, disc.mark, disc.opacity, 0))
            encoder.setVertexValue(uniforms, index: 3)
            encoder.setFragmentValue(uniforms, index: 3)
            mesh.draw(encoder)
        }
    }

    private func surfaceUniforms(_ marks: BoardMarks, kind: Int, contactCount: Int) -> Uniforms.Surface {
        let t = theme
        let legal = Uniforms.words(marks.legal)
        let hover = Uniforms.words(marks.hover)
        let lastMove = Uniforms.words(marks.lastMove)
        let hint = Uniforms.words(marks.hint)
        return Uniforms.Surface(
            boardColor: SIMD4(t.boardColor, 0),
            boardSurface: SIMD4(t.boardRoughness, t.boardClearcoat, t.boardClearcoatRoughness, t.boardPattern),
            boardReflection: SIMD4(t.reflection, t.reflectionBlur, t.veinBrightness, 0),
            gridColor: SIMD4(t.gridColor, 0),
            grid: SIMD4(t.gridWidth, t.gridMetallic, t.gridRoughness, t.gridGlow),
            frameColor: SIMD4(t.frameColor, 0),
            frameSurface: SIMD4(t.frameRoughness, t.frameMetallic, t.frameClearcoat, t.framePattern),
            inlayColor: SIMD4(t.inlayColor, 0),
            inlay: SIMD4(t.inlayMetallic, t.inlayRoughness, t.inlayGlow, 0),
            tableColor: SIMD4(t.tableColor, 0),
            tableSurface: SIMD4(t.tableRoughness, t.tablePattern, t.tableSheen, t.tableGlow),
            extra: SIMD4(t.starRadius, 0, 0, 0),
            legalAndHover: SIMD4(lowHalf: legal, highHalf: hover),
            lastMoveAndHint: SIMD4(lowHalf: lastMove, highHalf: hint),
            counts: SIMD4(Int32(kind), Int32(contactCount), 0, 0))
    }

    /// A pass that covers its target with one triangle, after `setUp` has set the pipeline and its inputs. The
    /// encoder is returned open, for more to be drawn over the triangle; the caller ends it.
    private func fullscreenPass(_ commandBuffer: MTLCommandBuffer, into target: MTLTexture, load: Bool = false, label: String,
                                _ setUp: (MTLRenderCommandEncoder) -> Void) -> MTLRenderCommandEncoder? {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = load ? .load : .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = label
        setUp(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        return encoder
    }

    private static func texelSize(_ texture: MTLTexture, first: Bool) -> SIMD4<Float> {
        SIMD4(1 / Float(texture.width), 1 / Float(texture.height), first ? 1 : 0, 0)
    }

    private static func vertexLayout(_ attributes: [(MTLVertexFormat, Int)], stride: Int) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        for (index, (format, offset)) in attributes.enumerated() {
            descriptor.attributes[index].format = format
            descriptor.attributes[index].offset = offset
            descriptor.attributes[index].bufferIndex = 0
        }
        descriptor.layouts[0].stride = stride
        return descriptor
    }

    private static func depthState(_ device: MTLDevice, _ compare: MTLCompareFunction, write: Bool) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = compare
        descriptor.isDepthWriteEnabled = write
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else { throw RendererError.creationFailed("depth state") }
        return state
    }

    /// Frees a frame's slot when the GPU has drawn it. Outside the main actor, so that the handler, which runs on a
    /// thread of Metal's, does not belong to it.
    private nonisolated static func signal(_ semaphore: DispatchSemaphore, when commandBuffer: MTLCommandBuffer) {
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
    }
}
