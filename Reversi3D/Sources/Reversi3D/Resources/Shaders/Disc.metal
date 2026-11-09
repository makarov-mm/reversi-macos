// A half of a disc: plastic, wood, stone, acrylic or metal, with a glowing ring for the neon set, a mark on the disc
// placed last, a glow when a move would turn it, and a dissolve. In the reflection pass it is mirrored in the board.
// Compiled after Common.metal and Lighting.metal.

#include <metal_stdlib>
using namespace metal;

struct DiscVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float occlusion [[attribute(2)]];
};

struct DiscVaryings {
    float4 position [[position]];
    float3 world;  // where the disc is, before the mirror
    float3 normal;
    float3 localPosition;  // on the disc, before it is placed
    float occlusion;
};

constant float DiscRadius = 0.42;
constant float DiscHalfHeight = 0.06;
constant float DiscRing = 0.335;

vertex DiscVaryings discVertex(DiscVertexIn in [[stage_in]],
                               constant FrameUniforms& frame [[buffer(1)]],
                               constant PassUniforms& pass [[buffer(2)]],
                               constant DiscUniforms& disc [[buffer(3)]])
{
    float4 world = disc.model * float4(in.position, 1.0);
    DiscVaryings out;
    out.world = world.xyz;
    out.normal = (disc.model * float4(in.normal, 0.0)).xyz;
    out.localPosition = in.position;
    out.occlusion = in.occlusion;
    if (pass.mirror.y > 0.5)
        world.y = 2.0 * pass.mirror.x - world.y;
    out.position = frame.viewProjection * world;
    return out;
}

fragment float4 discFragment(DiscVaryings in [[stage_in]],
                             bool frontFacing [[front_facing]],
                             constant FrameUniforms& frame [[buffer(1)]],
                             constant PassUniforms& pass [[buffer(2)]],
                             constant DiscUniforms& disc [[buffer(3)]],
                             depth2d<float> shadowMap [[texture(0)]],
                             texturecube<float> irradiance [[texture(1)]],
                             texturecube<float> prefiltered [[texture(2)]],
                             texture2d<float> brdf [[texture(3)]])
{
    // Measured before anything is discarded, while the neighbouring pixels still run.
    float3 N = normalize(in.normal);
    float spread = NormalSpread(N);
    float3 localPixel = fwidth(in.localPosition);
    float radiusPixel = max(fwidth(length(in.localPosition.xz)), 1e-5);
    float heightPixel = max(localPixel.y, 1e-5);

    // In the reflection only what stands above the board is mirrored.
    if (pass.mirror.y > 0.5 && in.world.y < pass.mirror.x)
        discard_fragment();

    float3 emissive = float3(0.0);
    if (disc.dissolve.x > 0.0) {
        float n = Fbm(in.localPosition * 7.0 + 3.0 + disc.detail.x * 5.0);
        float threshold = disc.dissolve.x * 1.2 - 0.1;
        if (n < threshold)
            discard_fragment();
        emissive += disc.dissolve.yzw * (1.0 - smoothstep(0.0, 0.06, n - threshold)) * 8.0;
    }

    if (!frontFacing)
        N = -N;
    float3 V = normalize(pass.eye.xyz - in.world);

    Material m = DefaultMaterial(disc.albedo.rgb, disc.surface.x);
    m.metallic = disc.surface.y;
    m.clearcoat = disc.surface.z;
    m.clearcoatRoughness = disc.surface.w;
    m.subsurface = disc.style.x;

    // Height above the seam and distance from the axis, the same for either half.
    float height = abs(in.localPosition.y);
    float radius = length(in.localPosition.xz);
    float angle = atan2(in.localPosition.z, in.localPosition.x);
    bool onFace = height > DiscHalfHeight - 0.01 && radius < DiscRadius - 0.02;
    int pattern = int(disc.style.z + 0.5);
    if (pattern == 1) {
        // Wood cut across the grain: straight lines over the face, rings on the side.
        float3 q = in.localPosition + float3(disc.detail.x * 3.1, 0.0, disc.detail.x * 1.7);
        float warp = Fbm(q * float3(2.0, 5.0, 5.0)) * 0.6;
        float rings = fract(length(q.yz + float2(0.9 + disc.detail.x, -0.7)) * 24.0 + warp);
        float late = smoothstep(0.0, 0.12, rings) * (1.0 - smoothstep(0.3, 0.65, rings));
        late = mix(late, 0.3, smoothstep(0.01, 0.03, length(localPixel)));
        float fibers = mix(Noise(float2(q.x * 30.0, length(q.yz) * 400.0)), 0.5, smoothstep(0.0015, 0.005, length(localPixel)));
        m.albedo *= 1.0 - disc.style.y * (0.24 * late + 0.1 * fibers);
    }
    else if (pattern == 2) {
        // Turned metal: fine circular marks on the face.
        float marks = mix(Noise(float2(radius * 900.0, angle * 3.0)), 0.5, smoothstep(0.0005, 0.0015, length(localPixel.xz)));
        m.roughness = clamp(m.roughness + (marks - 0.5) * 0.12 * disc.style.y, 0.03, 1.0);
    }
    else if (pattern == 3) {
        // Veined stone.
        float3 q = in.localPosition + disc.detail.x * 7.0;
        float warp = Fbm(q * 3.5 + 11.0);
        float veins = abs(sin((q.x * 2.0 + q.y * 3.0 + q.z + warp * 3.0) * 4.0));
        float vein = 1.0 - smoothstep(0.0, 0.08, veins);
        m.albedo = mix(m.albedo, m.albedo * 0.55 + float3(0.12), vein * disc.style.y);
        m.albedo *= 0.94 + 0.12 * Fbm(q * 22.0);
    }

    // The disc placed last carries a small mark in the middle of its face.
    if (disc.detail.y > 0.0 && onFace) {
        float mark = 1.0 - smoothstep(0.055 - 0.7 * radiusPixel, 0.055 + 0.7 * radiusPixel, radius);
        m.albedo = mix(m.albedo, frame.accentWarm.rgb * 0.6, mark * disc.detail.y);
        m.metallic *= 1.0 - mark * disc.detail.y;
        emissive += frame.accentWarm.rgb * mark * disc.detail.y * 0.35;
    }

    // The ground darkens what faces it, near the bottom most.
    float above = in.world.y - disc.style.w;
    float ground = mix(0.45, 1.0, smoothstep(0.0, 0.25, above));
    m.occlusion = in.occlusion * mix(1.0, ground, saturate(0.65 - N.y * 0.65));

    // Neon in the groove round the face and along the seam.
    float faceRing = LineCoverage(abs(radius - DiscRing), 0.006, radiusPixel) * step(DiscHalfHeight - 0.015, height);
    float seamRing = LineCoverage(height, 0.007, heightPixel) * step(DiscRadius - 0.03, radius);
    m.emissive = emissive + disc.trim.rgb * disc.trim.a * (faceRing + seamRing);

    m.roughness = WidenRoughness(m.roughness, spread);
    m.clearcoatRoughness = WidenRoughness(m.clearcoatRoughness, spread);
    float shadow = pass.eye.w > 0.5 ? 1.0 : Shadow(in.world, N, in.position.xy, frame, shadowMap);
    float3 color = Shade(m, in.world, N, V, shadow, frame, irradiance, prefiltered, brdf);

    // The glow of a disc that a move would turn: a halo at the silhouette and some light all over.
    float NoV = saturate(dot(N, V));
    color += disc.glow.rgb * disc.glow.a * (0.22 + 1.6 * pow(1.0 - NoV, 3.0));

    return float4(ApplyFog(color, in.world, frame), disc.detail.z);
}
