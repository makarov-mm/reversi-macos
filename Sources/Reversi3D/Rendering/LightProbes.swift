import Metal

/// The studio's light baked into textures: the environment itself, the light it casts on matte surfaces, its
/// reflections blurred for each roughness, and the split-sum table of the reflected share. The environment is
/// baked again when the theme changes, the table once.
struct LightProbes {
    static let environmentSize = 512
    static let irradianceSize = 32
    static let prefilteredSize = 256
    static let prefilteredLevels = 6
    static let brdfSize = 128

    let environment: MTLTexture
    let irradiance: MTLTexture
    let prefiltered: MTLTexture
    let brdf: MTLTexture

    // The cube maps as arrays of six layers, one view a level, for the kernels to write.
    private let environmentLayers: MTLTexture
    private let irradianceLayers: MTLTexture
    private let prefilteredLayers: [MTLTexture]

    private let environmentKernel: MTLComputePipelineState
    private let irradianceKernel: MTLComputePipelineState
    private let prefilterKernel: MTLComputePipelineState

    init(device: MTLDevice, library: ShaderLibrary, queue: MTLCommandQueue) throws {
        environment = try Self.cube(device, size: Self.environmentSize, levels: RenderTargets.levels(for: Self.environmentSize), "environment")
        irradiance = try Self.cube(device, size: Self.irradianceSize, levels: 1, "irradiance")
        // A local constant, so that the closure below does not capture self before it is whole.
        let prefiltered = try Self.cube(device, size: Self.prefilteredSize, levels: Self.prefilteredLevels, "prefiltered environment")
        self.prefiltered = prefiltered
        environmentLayers = try Self.layers(of: environment, level: 0)
        irradianceLayers = try Self.layers(of: irradiance, level: 0)
        prefilteredLayers = try (0..<Self.prefilteredLevels).map { try Self.layers(of: prefiltered, level: $0) }

        environmentKernel = try device.makeComputePipelineState(function: library.function("environmentKernel"))
        irradianceKernel = try device.makeComputePipelineState(function: library.function("irradianceKernel"))
        prefilterKernel = try device.makeComputePipelineState(function: library.function("prefilterKernel"))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Float, width: Self.brdfSize, height: Self.brdfSize, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let brdf = device.makeTexture(descriptor: descriptor) else { throw RendererError.creationFailed("BRDF table") }
        brdf.label = "BRDF table"
        self.brdf = brdf
        let brdfKernel = try device.makeComputePipelineState(function: library.function("brdfKernel"))
        try Self.run(queue) { encoder in
            encoder.setComputePipelineState(brdfKernel)
            encoder.setTexture(brdf, index: 0)
            encoder.dispatch(size: Self.brdfSize, layers: 1)
        }
    }

    /// Bakes the studio of a theme into the environment and the maps made from it, and waits for the GPU, so that
    /// what is drawn next sees them whole.
    func bake(_ theme: Theme, queue: MTLCommandQueue) throws {
        let studio = Uniforms.Environment(ceiling: SIMD4(theme.ceiling, 0), horizon: SIMD4(theme.horizon, 0), floor: SIMD4(theme.floor, 0),
                                          counts: SIMD4(Int32(min(theme.panels.count, 8)), 0, 0, 0))
        let panels = theme.panels.prefix(8).map { panel in
            Uniforms.StudioPanel(direction: SIMD4(panel.direction, panel.roll),
                                 shape: SIMD4(panel.halfSize.x, panel.halfSize.y, panel.corner, panel.softness),
                                 color: SIMD4(panel.radiance, panel.falloff))
        }
        let placeholder = Uniforms.StudioPanel(direction: .zero, shape: .zero, color: .zero)
        try Self.run(queue) { encoder in
            encoder.setComputePipelineState(environmentKernel)
            encoder.setTexture(environmentLayers, index: 0)
            encoder.setValue(studio, index: 0)
            encoder.setArray(panels, placeholder: placeholder, index: 1)
            encoder.dispatch(size: Self.environmentSize, layers: 6)
        }

        guard let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw RendererError.creationFailed("command buffer")
        }
        blit.generateMipmaps(for: environment)
        blit.endEncoding()
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw RendererError.creationFailed("compute encoder") }
        encoder.setComputePipelineState(irradianceKernel)
        encoder.setTexture(environment, index: 0)
        encoder.setTexture(irradianceLayers, index: 1)
        encoder.setValue(SIMD4<Float>(4, 0, 0, 0), index: 0) // a blurred level: the cosine lobe is wide
        encoder.dispatch(size: Self.irradianceSize, layers: 6)
        encoder.setComputePipelineState(prefilterKernel)
        for level in 0..<Self.prefilteredLevels {
            let roughness = Float(level) / Float(Self.prefilteredLevels - 1)
            encoder.setTexture(prefilteredLayers[level], index: 1)
            encoder.setValue(SIMD4<Float>(roughness, Float(Self.environmentSize), 0, 0), index: 0)
            encoder.dispatch(size: Self.prefilteredSize >> level, layers: 6)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private static func cube(_ device: MTLDevice, size: Int, levels: Int, _ label: String) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float, size: size, mipmapped: levels > 1)
        descriptor.mipmapLevelCount = levels
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget, .pixelFormatView]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RendererError.creationFailed("\(label) texture") }
        texture.label = label
        return texture
    }

    private static func layers(of cube: MTLTexture, level: Int) throws -> MTLTexture {
        guard let view = cube.makeTextureView(pixelFormat: cube.pixelFormat, textureType: .type2DArray, levels: level..<(level + 1), slices: 0..<6) else {
            throw RendererError.creationFailed("cube map view")
        }
        return view
    }

    /// Encodes compute work in a command buffer of its own and waits for it.
    private static func run(_ queue: MTLCommandQueue, _ encode: (MTLComputeCommandEncoder) -> Void) throws {
        guard let commandBuffer = queue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RendererError.creationFailed("command buffer")
        }
        encode(encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
