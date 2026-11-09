// The studio behind the table, and the steps after the scene: the samples resolved, the bloom, and the final image
// with tone mapping and the frosted glass behind the interface's panels. Compiled after Common.metal.

#include <metal_stdlib>
using namespace metal;

// The studio behind the table, out of focus, drawn at the far plane where nothing else was.
fragment float4 backgroundFragment(FullscreenVaryings in [[stage_in]],
                                   constant FrameUniforms& frame [[buffer(1)]],
                                   texturecube<float> prefiltered [[texture(2)]])
{
    constexpr sampler linearSampler(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_edge);
    float4 far = frame.inverseViewProjection * float4(in.ndc, 1.0, 1.0);
    float3 direction = normalize(far.xyz / far.w - frame.cameraPosition.xyz);
    float3 color = prefiltered.sample(linearSampler, direction, level(frame.environment.z * 0.6)).rgb * frame.environment.w;
    // Below the horizon the table fades into the fog.
    color = mix(color, frame.fog.rgb, 1.0 - smoothstep(-0.25, 0.02, direction.y));
    return float4(color, 1.0);
}

// Averages the samples of each pixel, weighting bright ones down so highlights keep smooth edges.
fragment float4 resolveFragment(FullscreenVaryings in [[stage_in]], texture2d_ms<float> source [[texture(0)]])
{
    uint2 pixel = uint2(in.position.xy);
    uint samples = source.get_num_samples();
    float3 sum = float3(0.0);
    float weights = 0.0;
    for (uint i = 0; i < samples; ++i) {
        float3 color = max(source.read(pixel, i).rgb, float3(0.0));
        float weight = 1.0 / (1.0 + Luminance(color));
        sum += color * weight;
        weights += weight;
    }
    return float4(sum / weights, 1.0);
}

float3 BloomSample(texture2d<float> source, float2 uv, float2 texel, float2 offset)
{
    constexpr sampler linearSampler(coord::normalized, filter::linear, address::clamp_to_edge);
    return max(source.sample(linearSampler, uv + offset * texel, level(0.0)).rgb, float3(0.0));
}

// Halves the image with a 13-tap filter; the first step weights bright samples down against flicker.
fragment float4 bloomDownFragment(FullscreenVaryings in [[stage_in]],
                                  constant BloomUniforms& bloom [[buffer(0)]],
                                  texture2d<float> source [[texture(0)]])
{
    float2 t = bloom.source.xy;
    float2 uv = in.uv;
    float3 a = BloomSample(source, uv, t, float2(-2.0, 2.0));
    float3 b = BloomSample(source, uv, t, float2(0.0, 2.0));
    float3 c = BloomSample(source, uv, t, float2(2.0, 2.0));
    float3 d = BloomSample(source, uv, t, float2(-2.0, 0.0));
    float3 e = BloomSample(source, uv, t, float2(0.0, 0.0));
    float3 f = BloomSample(source, uv, t, float2(2.0, 0.0));
    float3 g = BloomSample(source, uv, t, float2(-2.0, -2.0));
    float3 h = BloomSample(source, uv, t, float2(0.0, -2.0));
    float3 i = BloomSample(source, uv, t, float2(2.0, -2.0));
    float3 j = BloomSample(source, uv, t, float2(-1.0, 1.0));
    float3 k = BloomSample(source, uv, t, float2(1.0, 1.0));
    float3 l = BloomSample(source, uv, t, float2(-1.0, -1.0));
    float3 m = BloomSample(source, uv, t, float2(1.0, -1.0));

    float3 result;
    if (bloom.source.z > 0.5) {
        // Each group of four counts less the brighter it is, so lone bright pixels do not flicker.
        float3 groups[5] = {(j + k + l + m) * 0.25, (a + b + d + e) * 0.25, (b + c + e + f) * 0.25, (d + e + g + h) * 0.25, (e + f + h + i) * 0.25};
        float shares[5] = {0.5, 0.125, 0.125, 0.125, 0.125};
        float3 sum = float3(0.0);
        float weights = 0.0;
        for (int n = 0; n < 5; ++n) {
            float weight = shares[n] / (1.0 + Luminance(groups[n]));
            sum += groups[n] * weight;
            weights += weight;
        }
        result = sum / weights;
    }
    else {
        result = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
    }
    return float4(result, 1.0);
}

// Doubles the image with a tent filter; added onto the next larger level.
fragment float4 bloomUpFragment(FullscreenVaryings in [[stage_in]],
                                constant BloomUniforms& bloom [[buffer(0)]],
                                texture2d<float> source [[texture(0)]])
{
    float2 t = bloom.source.xy;
    float2 uv = in.uv;
    float3 sum = BloomSample(source, uv, t, float2(0.0, 0.0)) * 4.0;
    sum += (BloomSample(source, uv, t, float2(-1.0, 0.0)) + BloomSample(source, uv, t, float2(1.0, 0.0)) +
            BloomSample(source, uv, t, float2(0.0, -1.0)) + BloomSample(source, uv, t, float2(0.0, 1.0))) * 2.0;
    sum += BloomSample(source, uv, t, float2(-1.0, -1.0)) + BloomSample(source, uv, t, float2(1.0, -1.0)) +
           BloomSample(source, uv, t, float2(-1.0, 1.0)) + BloomSample(source, uv, t, float2(1.0, 1.0));
    return float4(sum / 16.0, 1.0);
}

// The final image: bloom, frosted glass behind the panels, exposure, filmic tone mapping, vignette, dither.
fragment float4 compositeFragment(FullscreenVaryings in [[stage_in]],
                                  constant CompositeUniforms& composite [[buffer(0)]],
                                  constant FrostedPanelUniforms* panels [[buffer(1)]],
                                  texture2d<float> scene [[texture(0)]],
                                  texture2d<float> bloom [[texture(1)]],
                                  texture2d<float> blur [[texture(2)]])
{
    constexpr sampler linearSampler(coord::normalized, filter::linear, address::clamp_to_edge);
    float3 color = scene.sample(linearSampler, in.uv, level(0.0)).rgb;
    float3 glow = bloom.sample(linearSampler, in.uv, level(0.0)).rgb / 6.0;
    color = mix(color, glow, composite.settings.y);

    // Pixels count from the top left, as the panels do.
    float2 pixel = in.position.xy;
    int panelCount = int(composite.settings.w);
    for (int i = 0; i < panelCount; ++i) {
        float d = RoundedBox(pixel - panels[i].bounds.xy, panels[i].bounds.zw, panels[i].style.x);
        float inside = 1.0 - smoothstep(-1.0, 1.0, d);
        float3 frosted = blur.sample(linearSampler, in.uv, level(0.0)).rgb / 4.0;
        color = mix(color, frosted * 0.45, inside * panels[i].style.y);
    }

    color = Aces(color * composite.settings.x);

    float2 centered = in.uv - 0.5;
    centered.x *= composite.viewport.x * composite.viewport.w;
    color *= 1.0 - composite.settings.z * smoothstep(0.25, 1.05, length(centered));

    color = EncodeSrgb(color);
    color += (InterleavedGradientNoise(in.position.xy) - 0.5) / 255.0;
    return float4(color, 1.0);
}
