/// Triangles as indices into a list of vertices.
struct Mesh<Vertex> {
    var vertices: [Vertex] = []
    var indices: [UInt32] = []
}
