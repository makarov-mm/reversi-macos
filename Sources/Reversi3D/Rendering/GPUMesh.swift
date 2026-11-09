import Metal

/// A mesh in GPU buffers, drawn as indexed triangles from vertex buffer 0.
struct GPUMesh {
    private let vertices: MTLBuffer
    private let indices: MTLBuffer
    private let indexCount: Int

    init<Vertex>(device: MTLDevice, mesh: Mesh<Vertex>, label: String) throws {
        guard !mesh.vertices.isEmpty, !mesh.indices.isEmpty,
              let vertices = mesh.vertices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
              let indices = mesh.indices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) })
        else {
            throw RendererError.creationFailed("\(label) mesh")
        }
        vertices.label = "\(label) vertices"
        indices.label = "\(label) indices"
        self.vertices = vertices
        self.indices = indices
        indexCount = mesh.indices.count
    }

    func draw(_ encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indices, indexBufferOffset: 0)
    }
}
