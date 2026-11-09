/// The material of one color of the discs.
struct PieceLook: Sendable {
    var albedo: SIMD3<Float>
    var roughness: Float = 0.3
    var metallic: Float = 0
    var clearcoat: Float = 0
    var clearcoatRoughness: Float = 0.05
    var subsurface: Float = 0
    /// 0 none, 1 wood, 2 turned metal, 3 stone.
    var pattern: Float = 0
    var patternStrength: Float = 0
    /// A glowing ring on the face and along the seam.
    var trim = SIMD3<Float>(repeating: 0)
    var trimStrength: Float = 0
}
