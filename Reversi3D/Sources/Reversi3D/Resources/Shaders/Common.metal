// Shared by all the shaders: the uniforms as the renderer fills them, noise, display transforms and shapes. The
// shader files are compiled together, in the order ShaderLibrary lists them, this one first.

#include <metal_stdlib>
using namespace metal;

constant float PI = 3.14159265359;

// Uniforms -------------------------------------------------------------------------------------------
// Laid out as the structs of Uniforms.swift: only 4x4 matrices and four-component vectors, so that both
// sides agree without padding.

struct FrameUniforms {
    float4x4 viewProjection;
    float4x4 inverseViewProjection;
    float4x4 lightViewProjection;
    float4 cameraPosition;  // xyz; w: time in seconds
    float4 lightDirection;  // toward the light; w: world size of a shadow map texel
    float4 lightColor;      // radiance; w: tangent of the light's angular radius, for soft shadows
    float4 shadowParams;    // x: depth range of the shadow map, y: depth bias
    float4 viewport;        // width, height, 1 / width, 1 / height
    float4 environment;     // x: diffuse light, y: reflected light, z: highest mip of the prefiltered map, w: background
    float4 accent;          // highlights
    float4 accentWarm;      // the last move
    float4 fog;             // rgb; w: density
};

// Per pass: where the shading looks from, and the mirror for the reflections.
struct PassUniforms {
    float4 eye;     // xyz; w: 1 to leave out the shadows
    float4 mirror;  // x: height of the mirror plane, y: 1 to mirror
};

struct DiscUniforms {
    float4x4 model;
    float4 albedo;    // rgb
    float4 surface;   // roughness, metallic, clearcoat, clearcoat roughness
    float4 style;     // x: subsurface, y: pattern strength, z: pattern (0 none, 1 wood, 2 turned metal, 3 stone), w: height of the ground
    float4 glow;      // rgb, strength
    float4 trim;      // rgb, strength: a glowing ring in the groove on the face and along the seam
    float4 dissolve;  // x: 0 solid to 1 gone, yzw: edge color
    float4 detail;    // x: a seed for the grain, y: the mark of the last move, z: opacity
};

struct SurfaceUniforms {
    float4 boardColor;       // rgb
    float4 boardSurface;     // roughness, clearcoat, clearcoat roughness, pattern (0 wood, 1 marble, 2 glass, 3 felt)
    float4 boardReflection;  // x: reflection strength, y: reflection blur, z: vein color brightness
    float4 gridColor;        // rgb
    float4 grid;             // x: half the width of the lines, y: metallic, z: roughness, w: glow
    float4 frameColor;       // rgb
    float4 frameSurface;     // roughness, metallic, clearcoat, pattern (0 wood, 1 marble, 2 metal)
    float4 inlayColor;       // rgb
    float4 inlay;            // x: metallic, y: roughness, z: glow
    float4 tableColor;       // rgb
    float4 tableSurface;     // roughness, pattern (0 felt, 1 wood, 2 neon grid, 3 stone), sheen, grid glow
    float4 extra;            // x: radius of the four dots where the lines cross round the middle
    uint4 legalAndHover;     // the squares as bits: where the side to move can play, and the legal square under the pointer
    uint4 lastMoveAndHint;
    int4 counts;             // x: kind (0 squares, 1 frame, 2 table), y: the feet of the discs listed
};

struct ShadowUniforms {
    float4x4 model;
    float4 dissolve;  // x: 0 solid to 1 gone, y: seed
};

struct BloomUniforms {
    float4 source;  // xy: the size of a texel of the source; z: 1 for the first step down
};

struct CompositeUniforms {
    float4 settings;  // x: exposure, y: bloom strength, z: vignette, w: number of frosted panels
    float4 viewport;  // width, height, 1 / width, 1 / height
};

struct FrostedPanelUniforms {
    float4 bounds;  // center x, center y, half width, half height, in pixels from the top left
    float4 style;   // x: corner radius, y: opacity
};

struct EnvironmentUniforms {
    float4 ceiling;
    float4 horizon;
    float4 floor;
    int4 counts;  // x: number of studio panels
};

struct StudioPanelUniforms {
    float4 direction;  // xyz toward the panel, w: roll
    float4 shape;      // half width, half height (as tangents), corner, softness
    float4 color;      // rgb radiance, w: falloff from the center
};

// A triangle that covers the screen ---------------------------------------------------------------

struct FullscreenVaryings {
    float4 position [[position]];
    float2 uv;   // texture coordinates, from the top left
    float2 ndc;  // normalized device coordinates, y up
};

vertex FullscreenVaryings fullscreenVertex(uint vertexId [[vertex_id]])
{
    float2 p = float2(float((vertexId << 1) & 2), float(vertexId & 2));
    FullscreenVaryings out;
    out.ndc = p * 2.0 - 1.0;
    out.uv = float2(p.x, 1.0 - p.y);
    // At the far plane, for the background drawn behind the scene.
    out.position = float4(out.ndc, 1.0, 1.0);
    return out;
}

// Helpers -----------------------------------------------------------------------------------------

float Luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// GLSL's mod: the remainder takes the sign of the divisor.
float Mod(float x, float y) { return x - y * floor(x / y); }

float RoundedBox(float2 p, float2 halfSize, float radius)
{
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

// Display -----------------------------------------------------------------------------------------

float3 RrtAndOdtFit(float3 v)
{
    float3 a = v * (v + 0.0245786) - 0.000090537;
    float3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}

// The ACES filmic curve, after Stephen Hill's fit.
float3 Aces(float3 color)
{
    const float3x3 inputMatrix = float3x3(float3(0.59719, 0.07600, 0.02840), float3(0.35458, 0.90834, 0.13383), float3(0.04823, 0.01566, 0.83777));
    const float3x3 outputMatrix = float3x3(float3(1.60475, -0.10208, -0.00327), float3(-0.53108, 1.10813, -0.07276), float3(-0.07367, -0.00605, 1.07602));
    return saturate(outputMatrix * RrtAndOdtFit(inputMatrix * color));
}

float3 EncodeSrgb(float3 c)
{
    return mix(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, 12.92 * c, step(c, float3(0.0031308)));
}

// Noise -------------------------------------------------------------------------------------------

float Hash12(float2 p)
{
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float Hash13(float3 p3)
{
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

float Noise(float2 p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(Hash12(i), Hash12(i + float2(1.0, 0.0)), u.x), mix(Hash12(i + float2(0.0, 1.0)), Hash12(i + float2(1.0, 1.0)), u.x), u.y);
}

float Noise(float3 p)
{
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(Hash13(i), Hash13(i + float3(1.0, 0.0, 0.0)), u.x), mix(Hash13(i + float3(0.0, 1.0, 0.0)), Hash13(i + float3(1.0, 1.0, 0.0)), u.x), u.y);
    float b = mix(mix(Hash13(i + float3(0.0, 0.0, 1.0)), Hash13(i + float3(1.0, 0.0, 1.0)), u.x), mix(Hash13(i + float3(0.0, 1.0, 1.0)), Hash13(i + float3(1.0, 1.0, 1.0)), u.x), u.y);
    return mix(a, b, u.z);
}

float Fbm(float2 p)
{
    const float2x2 turn = float2x2(float2(1.6, 1.2), float2(-1.2, 1.6));
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; ++i) {
        sum += amplitude * Noise(p);
        p = turn * p + 7.13;
        amplitude *= 0.5;
    }
    return sum;
}

float Fbm(float3 p)
{
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amplitude * Noise(p);
        p = p * 2.03 + float3(5.1, 1.7, 9.2);
        amplitude *= 0.5;
    }
    return sum;
}

// Anti-aliasing ----------------------------------------------------------------------------------

// The share of a pixel that a line covers: the pixel is `pixel` wide with its middle `d` from the line's middle,
// and the line reaches `halfWidth` to either side. Thin lines fade instead of breaking up.
float LineCoverage(float d, float halfWidth, float pixel)
{
    return saturate((min(d + 0.5 * pixel, halfWidth) - max(d - 0.5 * pixel, -halfWidth)) / pixel);
}

// Per-pixel noise for dithering and for rotating sample patterns.
float InterleavedGradientNoise(float2 pixel)
{
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}
