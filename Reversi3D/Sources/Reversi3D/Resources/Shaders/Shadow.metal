// The depth of the discs and the board as the key light sees them; a dissolving disc casts its remaining part.
// Compiled after Common.metal.

#include <metal_stdlib>
using namespace metal;

struct ShadowVertexIn {
    float3 position [[attribute(0)]];
};

struct ShadowVaryings {
    float4 position [[position]];
    float3 localPosition;
};

vertex ShadowVaryings shadowVertex(ShadowVertexIn in [[stage_in]],
                                   constant FrameUniforms& frame [[buffer(1)]],
                                   constant ShadowUniforms& caster [[buffer(3)]])
{
    ShadowVaryings out;
    out.localPosition = in.position;
    out.position = frame.lightViewProjection * caster.model * float4(in.position, 1.0);
    return out;
}

fragment void shadowFragment(ShadowVaryings in [[stage_in]], constant ShadowUniforms& caster [[buffer(3)]])
{
    float dissolve = caster.dissolve.x;
    if (dissolve > 0.0 && Fbm(in.localPosition * 7.0 + 3.0 + caster.dissolve.y * 5.0) < dissolve * 1.2 - 0.1)
        discard_fragment();
}
