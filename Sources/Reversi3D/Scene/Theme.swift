/// The look of the set: the board, the discs, the table and the studio light around them.
struct Theme: Sendable {
    var englishName: String
    var russianName: String

    // The board.
    var boardColor: SIMD3<Float>
    var boardRoughness: Float = 0.3
    var boardClearcoat: Float = 0
    var boardClearcoatRoughness: Float = 0.05
    /// 0 wood, 1 marble, 2 glass, 3 felt.
    var boardPattern: Float = 0
    var reflection: Float = 0.5
    var reflectionBlur: Float = 1.5
    var veinBrightness: Float = 0.5
    var gridColor: SIMD3<Float>
    /// Half the width of a line.
    var gridWidth: Float = 0.012
    var gridMetallic: Float = 0
    var gridRoughness: Float = 0.5
    var gridGlow: Float = 0
    var starRadius: Float = 0.05
    var frameColor: SIMD3<Float>
    var frameRoughness: Float = 0.35
    var frameMetallic: Float = 0
    var frameClearcoat: Float = 0
    /// 0 wood, 1 marble, 2 metal.
    var framePattern: Float = 0
    var inlayColor: SIMD3<Float>
    var inlayMetallic: Float = 1
    var inlayRoughness: Float = 0.3
    var inlayGlow: Float = 0

    var white: PieceLook
    var black: PieceLook

    var tableColor: SIMD3<Float>
    var tableRoughness: Float = 0.9
    /// 0 felt, 1 wood, 2 glowing grid, 3 stone.
    var tablePattern: Float = 0
    var tableSheen: Float = 0
    var tableGlow: Float = 0

    // The light.
    var keyDirection: SIMD3<Float>
    var keyRadiance: SIMD3<Float>
    /// The tangent of the light's angular radius.
    var keySoftness: Float = 0.04
    var ceiling: SIMD3<Float>
    var horizon: SIMD3<Float>
    var floor: SIMD3<Float>
    var diffuseLight: Float = 1
    var reflectedLight: Float = 1
    var background: Float = 0.6
    var fog: SIMD3<Float>
    var exposure: Float = 1
    var bloom: Float = 0.05
    var vignette: Float = 0.35

    /// Highlights and the interface.
    var accent: SIMD3<Float>
    /// The last move.
    var accentWarm: SIMD3<Float>

    /// The soft boxes and strips of the studio, up to eight.
    var panels: [StudioPanel] = []

    func name(in language: Language) -> String { language == .russian ? russianName : englishName }
}
