/// A vertex of a disc, laid out as the shaders read it: 32 bytes, as a surface vertex, so that one shadow pipeline
/// draws both.
struct DiscVertex {
    var px, py, pz: Float
    var nx, ny, nz: Float
    /// The light reaching into the groove.
    var occlusion: Float
    var padding: Float = 0

    init(_ position: SIMD3<Float>, _ normal: SIMD3<Float>, occlusion: Float) {
        (px, py, pz) = (position.x, position.y, position.z)
        (nx, ny, nz) = (normal.x, normal.y, normal.z)
        self.occlusion = occlusion
    }
}
