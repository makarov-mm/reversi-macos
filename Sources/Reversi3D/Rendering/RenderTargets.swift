import Metal

/// The textures the size of the window: the scene in high dynamic range with multisampling, its resolved image, the
/// reflections at half size with mip levels to blur them, and the levels of the bloom.
struct RenderTargets {
    static let hdrFormat = MTLPixelFormat.rgba16Float
    static let bloomFormat = MTLPixelFormat.rg11b10Float
    static let depthFormat = MTLPixelFormat.depth32Float
    static let bloomLevels = 6

    let width: Int
    let height: Int
    let sceneColor: MTLTexture
    let sceneDepth: MTLTexture
    let resolved: MTLTexture
    let reflectionColor: MTLTexture
    let reflectionDepth: MTLTexture
    let bloom: [MTLTexture]

    init(device: MTLDevice, width: Int, height: Int, samples: Int) throws {
        self.width = width
        self.height = height

        // The GPUs of Apple silicon keep the depth of a pass in their tile memory: it needs no texture of its own.
        let tiled = device.supportsFamily(.apple1)
        func make(_ format: MTLPixelFormat, _ width: Int, _ height: Int, levels: Int = 1, samples: Int = 1, memoryless: Bool = false,
                  _ label: String) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.mipmapLevelCount = levels
            if samples > 1 {
                descriptor.textureType = .type2DMultisample
                descriptor.sampleCount = samples
            }
            descriptor.usage = memoryless ? [.renderTarget] : [.renderTarget, .shaderRead]
            descriptor.storageMode = memoryless ? .memoryless : .private
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw RendererError.creationFailed("\(label) texture") }
            texture.label = label
            return texture
        }

        sceneColor = try make(Self.hdrFormat, width, height, samples: samples, "scene color")
        sceneDepth = try make(Self.depthFormat, width, height, samples: samples, memoryless: tiled, "scene depth")
        resolved = try make(Self.hdrFormat, width, height, "resolved scene")

        let reflectionWidth = max(1, width / 2)
        let reflectionHeight = max(1, height / 2)
        let reflectionLevels = min(5, Self.levels(for: max(reflectionWidth, reflectionHeight)))
        reflectionColor = try make(Self.hdrFormat, reflectionWidth, reflectionHeight, levels: reflectionLevels, "reflection color")
        reflectionDepth = try make(Self.depthFormat, reflectionWidth, reflectionHeight, memoryless: tiled, "reflection depth")

        bloom = try (0..<Self.bloomLevels).map { level in
            try make(Self.bloomFormat, max(1, width >> (level + 1)), max(1, height >> (level + 1)), "bloom \(level)")
        }
    }

    /// The mip levels of a full chain down to one texel.
    static func levels(for size: Int) -> Int {
        var levels = 1
        while size >> levels > 0 {
            levels += 1
        }
        return levels
    }
}
