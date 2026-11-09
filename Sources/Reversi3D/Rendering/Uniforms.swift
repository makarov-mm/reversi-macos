import simd

/// The uniforms of Common.metal, laid out the same way: only 4x4 matrices and four-component vectors, which both
/// languages align to 16 bytes, so neither side needs padding.
enum Uniforms {
    struct Frame {
        var viewProjection: float4x4
        var inverseViewProjection: float4x4
        var lightViewProjection: float4x4
        var cameraPosition: SIMD4<Float> // xyz; w: time in seconds
        var lightDirection: SIMD4<Float> // toward the light; w: world size of a shadow map texel
        var lightColor: SIMD4<Float> // radiance; w: tangent of the light's angular radius
        var shadowParams: SIMD4<Float> // x: depth range of the shadow map, y: depth bias
        var viewport: SIMD4<Float> // width, height, 1 / width, 1 / height
        var environment: SIMD4<Float> // diffuse light, reflected light, highest mip of the prefiltered map, background
        var accent: SIMD4<Float>
        var accentWarm: SIMD4<Float>
        var fog: SIMD4<Float> // rgb; w: density
    }

    struct Pass {
        var eye: SIMD4<Float> // xyz; w: 1 to leave out the shadows
        var mirror: SIMD4<Float> // x: height of the mirror plane, y: 1 to mirror
    }

    struct Disc {
        var model: float4x4
        var albedo: SIMD4<Float>
        var surface: SIMD4<Float> // roughness, metallic, clearcoat, clearcoat roughness
        var style: SIMD4<Float> // subsurface, pattern strength, pattern, height of the ground
        var glow: SIMD4<Float> // rgb, strength
        var trim: SIMD4<Float> // rgb, strength
        var dissolve: SIMD4<Float> // x: amount; yzw: edge color
        var detail: SIMD4<Float> // x: seed, y: mark of the last move, z: opacity
    }

    struct Surface {
        var boardColor: SIMD4<Float>
        var boardSurface: SIMD4<Float> // roughness, clearcoat, clearcoat roughness, pattern
        var boardReflection: SIMD4<Float> // reflection strength, reflection blur, vein brightness
        var gridColor: SIMD4<Float>
        var grid: SIMD4<Float> // half width of the lines, metallic, roughness, glow
        var frameColor: SIMD4<Float>
        var frameSurface: SIMD4<Float> // roughness, metallic, clearcoat, pattern
        var inlayColor: SIMD4<Float>
        var inlay: SIMD4<Float> // metallic, roughness, glow
        var tableColor: SIMD4<Float>
        var tableSurface: SIMD4<Float> // roughness, pattern, sheen, grid glow
        var extra: SIMD4<Float> // x: radius of the four dots round the middle
        var legalAndHover: SIMD4<UInt32> // bitboards as pairs of 32-bit words
        var lastMoveAndHint: SIMD4<UInt32>
        var counts: SIMD4<Int32> // x: kind (0 squares, 1 frame, 2 table), y: feet of the discs listed
    }

    struct Shadow {
        var model: float4x4
        var dissolve: SIMD4<Float> // x: amount, y: seed
    }

    struct Bloom {
        var source: SIMD4<Float> // xy: a texel of the source; z: 1 for the first step down
    }

    struct Composite {
        var settings: SIMD4<Float> // exposure, bloom strength, vignette, number of frosted panels
        var viewport: SIMD4<Float> // width, height, 1 / width, 1 / height
    }

    struct FrostedPanel {
        var bounds: SIMD4<Float> // center x, center y, half width, half height
        var style: SIMD4<Float> // x: corner radius, y: opacity
    }

    struct Environment {
        var ceiling: SIMD4<Float>
        var horizon: SIMD4<Float>
        var floor: SIMD4<Float>
        var counts: SIMD4<Int32> // x: number of studio panels
    }

    struct StudioPanel {
        var direction: SIMD4<Float> // xyz toward the panel, w: roll
        var shape: SIMD4<Float> // half width, half height (as tangents), corner, softness
        var color: SIMD4<Float> // rgb radiance, w: falloff from the center
    }

    /// The two 32-bit words of a bitboard, low first.
    static func words(_ bits: UInt64) -> SIMD2<UInt32> {
        SIMD2(UInt32(truncatingIfNeeded: bits), UInt32(truncatingIfNeeded: bits >> 32))
    }
}
