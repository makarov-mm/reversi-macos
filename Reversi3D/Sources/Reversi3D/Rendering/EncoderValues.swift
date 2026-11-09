import Metal

/// Small values and arrays copied into the command stream, for the uniforms that change from draw to draw.
extension MTLRenderCommandEncoder {
    func setVertexValue<T>(_ value: T, index: Int) {
        withUnsafeBytes(of: value) { setVertexBytes($0.baseAddress!, length: $0.count, index: index) }
    }

    func setFragmentValue<T>(_ value: T, index: Int) {
        withUnsafeBytes(of: value) { setFragmentBytes($0.baseAddress!, length: $0.count, index: index) }
    }

    /// An empty array is bound as one element, `placeholder`, which the shader is told to skip.
    func setFragmentArray<T>(_ values: [T], placeholder: T, index: Int) {
        let bound = values.isEmpty ? [placeholder] : values
        bound.withUnsafeBytes { setFragmentBytes($0.baseAddress!, length: $0.count, index: index) }
    }
}

extension MTLComputeCommandEncoder {
    func setValue<T>(_ value: T, index: Int) {
        withUnsafeBytes(of: value) { setBytes($0.baseAddress!, length: $0.count, index: index) }
    }

    /// An empty array is bound as one element, `placeholder`, which the kernel is told to skip.
    func setArray<T>(_ values: [T], placeholder: T, index: Int) {
        let bound = values.isEmpty ? [placeholder] : values
        bound.withUnsafeBytes { setBytes($0.baseAddress!, length: $0.count, index: index) }
    }

    /// Runs a kernel over a square of `size` texels on `layers` layers, eight by eight.
    func dispatch(size: Int, layers: Int) {
        dispatchThreadgroups(MTLSize(width: (size + 7) / 8, height: (size + 7) / 8, depth: layers),
                             threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }
}
