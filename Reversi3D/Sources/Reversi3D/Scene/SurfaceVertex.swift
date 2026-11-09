/// A vertex of the board, its frame and the table, laid out as the shaders read it: 32 bytes.
struct SurfaceVertex {
    var px, py, pz: Float
    var nx, ny, nz: Float
    var u, v: Float

    init(_ position: SIMD3<Float>, _ normal: SIMD3<Float>, _ uv: SIMD2<Float>) {
        (px, py, pz) = (position.x, position.y, position.z)
        (nx, ny, nz) = (normal.x, normal.y, normal.z)
        (u, v) = (uv.x, uv.y)
    }

    var position: SIMD3<Float> { SIMD3(px, py, pz) }
    var normal: SIMD3<Float> { SIMD3(nx, ny, nz) }
}
