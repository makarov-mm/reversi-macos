// The board's squares with their grid lines and highlights, the frame with the coordinates, and the table: static
// geometry in world space. Compiled after Common.metal and Lighting.metal.

#include <metal_stdlib>
using namespace metal;

struct SurfaceVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
};

struct SurfaceVaryings {
    float4 position [[position]];
    float3 world;
    float3 normal;
};

constant float FrameOuter = 4.62;

vertex SurfaceVaryings surfaceVertex(SurfaceVertexIn in [[stage_in]], constant FrameUniforms& frame [[buffer(1)]])
{
    SurfaceVaryings out;
    out.world = in.position;
    out.normal = in.normal;
    out.position = frame.viewProjection * float4(in.position, 1.0);
    return out;
}

bool Bit(uint2 mask, int square)
{
    uint word = square < 32 ? mask.x : mask.y;
    return ((word >> uint(square & 31)) & 1u) != 0u;
}

// Wood with its grain along x: growth lines of uneven spacing and strength, fine fibres and a soft figure. Detail
// finer than the footprint, the size of a pixel in p, fades to its average instead of flickering.
float3 Wood(float2 p, float3 color, float seed, float footprint)
{
    p += float2(seed * 31.7, seed * 17.3);
    // The growth lines: their spacing drifts across the grain, and they wander a little along it.
    float t = p.y * 7.0 + 2.5 * Fbm(float2(p.y * 0.8, seed * 5.0)) + 0.8 * Fbm(float2(p.x * 0.3, p.y * 1.2)) + 0.2 * sin(p.x * 1.1 + seed * 6.0);
    float ring = floor(t);
    float phase = t - ring;
    float width = 0.2 + 0.3 * Hash12(float2(ring, seed));
    float late = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(width, width + 0.25, phase));
    late *= 0.35 + 0.9 * Hash12(float2(ring, seed + 7.0));
    late = mix(late, 0.3, smoothstep(0.04, 0.12, footprint));
    float fibers = 0.5 * Noise(float2(p.x * 3.0, p.y * 260.0)) + 0.5 * Noise(float2(p.x * 7.0, p.y * 600.0));
    fibers = mix(fibers, 0.5, smoothstep(0.001, 0.004, footprint));
    float figure = Noise(p * float2(0.8, 2.2) + seed * 9.0);
    return color * (1.0 - 0.2 * late) * (0.9 + 0.16 * fibers) * (0.9 + 0.2 * figure);
}

float3 Marble(float2 p, float3 color, float3 veinColor, float seed)
{
    p += seed * 10.0;
    float warp = Fbm(p * 1.3) * 4.5;
    float wave = abs(sin((p.x * 1.4 + p.y * 0.9 + warp) * 2.6));
    float vein = pow(1.0 - wave, 14.0) + 0.35 * pow(1.0 - abs(sin((p.x * 3.1 - p.y * 2.2 + warp * 1.7) * 3.0)), 30.0);
    float3 c = color * (0.9 + 0.2 * Fbm(p * 2.7 + 5.0));
    return mix(c, veinColor, saturate(vein) * 0.75);
}

// Felt: fine fibres and a soft mottling, fading to their average where they are finer than a pixel.
float3 Felt(float2 p, float3 color, float footprint)
{
    float fine = mix(Noise(p * 260.0), 0.5, smoothstep(0.002, 0.006, footprint));
    float coarse = mix(Noise(p * 90.0 + 3.0), 0.5, smoothstep(0.006, 0.018, footprint));
    return color * (0.84 + 0.3 * (0.6 * fine + 0.4 * coarse)) * (0.92 + 0.16 * Fbm(p * 0.9));
}

// One square of the board at a point of it (in files and rows): its wood, marble, glass or felt. The edges between
// the squares lie under the grid lines.
float3 SquareAlbedo(int2 cell, float2 board, float3 world, float footprint, int pattern, constant SurfaceUniforms& surface)
{
    int square = cell.y * 8 + cell.x;
    float seed = Hash12(float2(float(square), 3.7));
    float2 cellOffset = board - float2(cell) - 0.5;
    float3 color = surface.boardColor.rgb;
    if (pattern == 0) {
        // Each square cut from its own board, the grain turning from square to square like parquet.
        bool across = ((cell.x + cell.y) & 1) == 1;
        float2 grain = across ? float2(cellOffset.y, -cellOffset.x) : cellOffset;
        return Wood(grain + float2(0.0, seed * 3.0), color * (0.92 + 0.16 * seed), seed, footprint);
    }
    if (pattern == 1)
        return Marble(world.xz * 0.3, color, mix(color, float3(0.85), surface.boardReflection.z), 4.0);
    if (pattern == 3)
        return Felt(world.xz, color, footprint);
    return color * (0.9 + 0.2 * Noise(world.xz * 6.0));
}

float ContactShadow(float2 xz, constant float4* contacts, int count)
{
    float shade = 1.0;
    for (int i = 0; i < count; ++i) {
        float4 disc = contacts[i];
        float d = length(xz - disc.xy);
        shade *= 1.0 - disc.w * (1.0 - smoothstep(disc.z * 0.55, disc.z * 1.9, d));
    }
    return shade;
}

fragment float4 surfaceFragment(SurfaceVaryings in [[stage_in]],
                                constant FrameUniforms& frame [[buffer(1)]],
                                constant PassUniforms& pass [[buffer(2)]],
                                constant SurfaceUniforms& surface [[buffer(3)]],
                                constant float4* contacts [[buffer(4)]],
                                depth2d<float> shadowMap [[texture(0)]],
                                texturecube<float> irradiance [[texture(1)]],
                                texturecube<float> prefiltered [[texture(2)]],
                                texture2d<float> brdf [[texture(3)]],
                                texture2d<float> reflection [[texture(4)]],
                                texture2d<float> labels [[texture(5)]])
{
    constexpr sampler reflectionSampler(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler labelSampler(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(8));

    float3 N = normalize(in.normal);
    float3 V = normalize(pass.eye.xyz - in.world);
    float time = frame.cameraPosition.w;
    int kind = surface.counts.x;
    int contactCount = surface.counts.y;
    Material m = DefaultMaterial(float3(0.5), 0.5);
    float3 glow = float3(0.0);
    float4 planar = float4(0.0);

    if (kind == 0) {
        float2 board = in.world.xz + 4.0;                  // files and rows
        float2 pixel = max(fwidth(board), float2(1e-5));  // the size of a pixel on the board
        float footprint = length(pixel);
        float pulse = 0.5 + 0.5 * sin(time * 3.5);
        int pattern = int(surface.boardSurface.w + 0.5);
        int2 cell = int2(clamp(floor(board), float2(0.0), float2(7.0)));
        int square = cell.y * 8 + cell.x;
        float d = length(board - float2(cell) - 0.5);
        float soft = max(0.01, 0.75 * footprint);  // sharp edges softened to a pixel when the board is far
        m.albedo = SquareAlbedo(cell, board, in.world, footprint, pattern, surface);
        m.roughness = surface.boardSurface.x;
        m.clearcoat = surface.boardSurface.y;
        m.clearcoatRoughness = surface.boardSurface.z;

        // The highlights.
        if (Bit(surface.lastMoveAndHint.xy, square))
            m.albedo = mix(m.albedo, frame.accentWarm.rgb * 0.5, 0.14);
        if (Bit(surface.legalAndHover.xy, square)) {
            float mark = 1.0 - smoothstep(0.075 - soft, 0.075 + soft, d);
            glow += frame.accent.rgb * (mark * 1.6 + 0.08 * (1.0 - smoothstep(0.0, 0.3, d)));
        }
        if (Bit(surface.legalAndHover.zw, square)) {
            float ring = 1.0 - smoothstep(0.018 - soft, 0.018 + soft, abs(d - 0.45));
            glow += frame.accent.rgb * ring * 1.2;
        }
        if (Bit(surface.lastMoveAndHint.zw, square)) {
            float ring = 1.0 - smoothstep(0.022 - soft, 0.022 + soft, abs(d - 0.3 - 0.03 * pulse));
            glow += frame.accent.rgb * (ring * 2.2 + 0.25 * (1.0 - smoothstep(0.0, 0.45, d))) * (0.7 + 0.3 * pulse);
        }

        // The grid lines, and the four dots where they cross round the middle, averaged over the pixel.
        float2 offset = board - round(board);
        float gridLine = max(LineCoverage(abs(offset.x), surface.grid.x, pixel.x), LineCoverage(abs(offset.y), surface.grid.x, pixel.y));
        float2 star = board - (step(float2(4.0), board) * 4.0 + 2.0);
        float starRadius = surface.extra.x;
        float starDot = 1.0 - smoothstep(starRadius - 0.6 * footprint, starRadius + 0.6 * footprint, length(star));
        float inlay = max(gridLine, starDot);
        m.albedo = mix(m.albedo, surface.gridColor.rgb, inlay);
        m.metallic = mix(m.metallic, surface.grid.y, inlay);
        m.roughness = mix(m.roughness, surface.grid.z, inlay);
        glow += surface.gridColor.rgb * surface.grid.w * inlay;

        // The discs mirrored in the polish, added over the shading below. Pixels and texture coordinates both count
        // from the top left.
        float2 screen = in.position.xy * frame.viewport.zw + N.xz * 0.012;
        planar = reflection.sample(reflectionSampler, screen, level(surface.boardReflection.y));
        m.occlusion = ContactShadow(in.world.xz, contacts, contactCount);
        if (pattern == 3) {
            // The sheen of cloth at grazing angles.
            m.emissive += m.albedo * pow(1.0 - saturate(dot(N, V)), 4.0) * 0.6;
        }
    }
    else if (kind == 1) {
        int pattern = int(surface.frameSurface.w + 0.5);
        bool alongX = abs(in.world.z) > abs(in.world.x);
        float2 grain = alongX ? float2(in.world.x, in.world.z + in.world.y) : float2(in.world.z, in.world.x + in.world.y);
        float footprint = length(fwidth(grain));
        float3 color = surface.frameColor.rgb;
        if (pattern == 0) {
            m.albedo = Wood(grain * float2(0.35, 1.2), color, 0.37, footprint * 1.2);
        }
        else if (pattern == 1) {
            m.albedo = Marble(in.world.xz * 0.5 + in.world.y, color, color * 3.0 + 0.08, 2.0);
        }
        else {
            float lines = mix(Noise(grain * float2(2.0, 300.0)), 0.5, smoothstep(0.002, 0.006, footprint));
            m.albedo = color * (0.94 + 0.12 * lines);
        }
        m.roughness = surface.frameSurface.x;
        m.metallic = surface.frameSurface.y;
        m.clearcoat = surface.frameSurface.z;
        m.clearcoatRoughness = 0.06;

        // The inlaid coordinates and lines, on the top.
        float label = labels.sample(labelSampler, (in.world.xz + FrameOuter) / (2.0 * FrameOuter)).r;
        float ring = max(abs(in.world.x), abs(in.world.z));
        float ringPixel = max(fwidth(ring), 1e-5);
        if (N.y > 0.9) {
            float lines = LineCoverage(abs(ring - 4.1), 0.0085, ringPixel) + LineCoverage(abs(ring - 4.52), 0.006, ringPixel);
            float inlay = saturate(max(label, lines));
            m.albedo = mix(m.albedo, surface.inlayColor.rgb, inlay);
            m.metallic = mix(m.metallic, surface.inlay.x, inlay);
            m.roughness = mix(m.roughness, surface.inlay.y, inlay);
            glow += surface.inlayColor.rgb * inlay * surface.inlay.z;
        }
        m.occlusion = ContactShadow(in.world.xz, contacts, contactCount) * mix(0.65, 1.0, smoothstep(-0.32, -0.12, in.world.y));
    }
    else {
        int pattern = int(surface.tableSurface.y + 0.5);
        float2 p = in.world.xz;
        float distance = length(p);
        float footprint = length(fwidth(p));
        float3 color = surface.tableColor.rgb;
        if (pattern == 0) {
            m.albedo = Felt(p, color, footprint);
        }
        else if (pattern == 1) {
            m.albedo = Wood(p * float2(0.25, 0.9), color, 0.81, footprint * 0.9);
        }
        else if (pattern == 2) {
            // The glowing grid of the first version of the game.
            m.albedo = color;
            float2 grid = abs(fract(p - 0.5) - 0.5) / fwidth(p);
            float minorLine = 1.0 - saturate(min(grid.x, grid.y) - 0.5);
            float2 majorGrid = abs(fract(p * 0.2 - 0.5) - 0.5) / fwidth(p * 0.2);
            float majorLine = 1.0 - saturate(min(majorGrid.x, majorGrid.y) - 0.8);
            float fade = exp(-distance * 0.16);
            glow += frame.accent.rgb * (minorLine * 0.35 + majorLine * 1.1) * fade * surface.tableSurface.w;
        }
        else {
            m.albedo = Marble(p * 0.22, color, color * 1.7, 6.0);
        }
        m.roughness = surface.tableSurface.x;
        // The light falls on the board; the table darkens away from it.
        m.albedo *= mix(1.0, 0.18, smoothstep(5.5, 15.0, distance));
        m.occlusion = ContactShadow(p, contacts, contactCount);
        // Darker under and around the board.
        float board = max(abs(p.x), abs(p.y));
        m.occlusion *= mix(0.35, 1.0, smoothstep(FrameOuter - 0.05, FrameOuter + 1.1, board));
        if (surface.tableSurface.z > 0.0) {
            // The sheen of cloth at grazing angles.
            m.emissive += color * surface.tableSurface.z * pow(1.0 - saturate(dot(N, V)), 4.0) * 0.5;
        }
    }

    float spread = NormalSpread(N);
    m.roughness = WidenRoughness(m.roughness, spread);
    m.clearcoatRoughness = WidenRoughness(m.clearcoatRoughness, spread);
    float shadow = Shadow(in.world, N, in.position.xy, frame, shadowMap);
    float3 color = Shade(m, in.world, N, V, shadow, frame, irradiance, prefiltered, brdf) + glow;
    if (kind == 0) {
        float fresnel = mix(0.1, 1.0, pow(1.0 - saturate(dot(N, V)), 5.0));
        color = mix(color, planar.rgb, planar.a * fresnel * surface.boardReflection.x);
    }
    return float4(ApplyFog(color, in.world, frame), 1.0);
}
