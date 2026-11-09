import Metal

/// Textures filled from pixels made on the CPU: font atlases, the coordinates of the board and the icon.
enum TextureUpload {
    /// One byte a pixel, the coverage of text or shapes.
    static func coverage(device: MTLDevice, queue: MTLCommandQueue, pixels: [UInt8], width: Int, height: Int, mipmapped: Bool,
                         label: String) throws -> MTLTexture {
        try make(device: device, queue: queue, format: .r8Unorm, bytes: pixels, bytesPerPixel: 1, width: width, height: height,
                 mipmapped: mipmapped, label: label)
    }

    /// Four bytes a pixel, red, green, blue and alpha.
    static func rgba(device: MTLDevice, queue: MTLCommandQueue, pixels: [UInt8], width: Int, height: Int, mipmapped: Bool,
                     label: String) throws -> MTLTexture {
        try make(device: device, queue: queue, format: .rgba8Unorm, bytes: pixels, bytesPerPixel: 4, width: width, height: height,
                 mipmapped: mipmapped, label: label)
    }

    private static func make(device: MTLDevice, queue: MTLCommandQueue, format: MTLPixelFormat, bytes: [UInt8], bytesPerPixel: Int,
                             width: Int, height: Int, mipmapped: Bool, label: String) throws -> MTLTexture {
        precondition(bytes.count == width * height * bytesPerPixel, "the pixels do not fill the texture")
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: mipmapped)
        descriptor.usage = mipmapped ? [.shaderRead, .renderTarget] : [.shaderRead]
        // Written by the CPU once; managed storage works on every Mac, and is shared memory on Apple silicon.
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RendererError.creationFailed("\(label) texture") }
        texture.label = label
        bytes.withUnsafeBytes { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: buffer.baseAddress!,
                            bytesPerRow: width * bytesPerPixel)
        }
        if mipmapped && texture.mipmapLevelCount > 1 {
            guard let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw RendererError.creationFailed("command buffer")
            }
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        return texture
    }
}
