// The light probes, baked when the theme changes: the studio environment, the light it casts on matte surfaces,
// its reflections blurred for each roughness, and the split-sum table, baked once. The cube maps are written face
// by face, through views of them as arrays of six layers. Compiled after Common.metal and Lighting.metal.

#include <metal_stdlib>
using namespace metal;

// The direction of the middle of a texel of a cube map face.
float3 CubeDirection(uint3 texel, float size)
{
    float2 st = (float2(texel.xy) + 0.5) / size * 2.0 - 1.0;
    switch (texel.z) {
    case 0: return normalize(float3(1.0, -st.y, -st.x));
    case 1: return normalize(float3(-1.0, -st.y, st.x));
    case 2: return normalize(float3(st.x, 1.0, st.y));
    case 3: return normalize(float3(st.x, -1.0, -st.y));
    case 4: return normalize(float3(st.x, -st.y, 1.0));
    default: return normalize(float3(-st.x, -st.y, -1.0));
    }
}

float2 Hammersley(uint i, uint count)
{
    return float2(float(i) / float(count), float(reverse_bits(i)) * 2.3283064365386963e-10);
}

float3x3 TangentFrame(float3 n)
{
    float3 up = abs(n.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    float3 tangent = normalize(cross(up, n));
    return float3x3(tangent, cross(n, tangent), n);
}

float3 ImportanceSampleGgx(float2 xi, float roughness)
{
    float a = roughness * roughness;
    float phi = 2.0 * PI * xi.x;
    float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    return float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
}

// The studio: a backdrop graded from the floor to the ceiling, and soft boxes and light strips round the board.
float3 StudioRadiance(float3 d, constant EnvironmentUniforms& studio, constant StudioPanelUniforms* panels)
{
    float3 color = d.y > 0.0 ? mix(studio.horizon.rgb, studio.ceiling.rgb, pow(d.y, 0.55)) : mix(studio.horizon.rgb, studio.floor.rgb, pow(-d.y, 0.35));
    for (int i = 0; i < studio.counts.x; ++i) {
        float3 center = normalize(panels[i].direction.xyz);
        float facing = dot(d, center);
        if (facing <= 0.05)
            continue;
        float3x3 frame = TangentFrame(center);
        float2 q = float2(dot(d, frame[0]), dot(d, frame[1])) / facing;
        float roll = panels[i].direction.w;
        q = float2x2(float2(cos(roll), sin(roll)), float2(-sin(roll), cos(roll))) * q;
        float4 shape = panels[i].shape;
        float sdf = RoundedBox(q, shape.xy, shape.z);
        float mask = 1.0 - smoothstep(-shape.w, shape.w, sdf);
        float falloff = 1.0 - panels[i].color.w * clamp(length(q / shape.xy) * 0.7, 0.0, 1.0);
        color += panels[i].color.rgb * mask * falloff;
    }
    return color;
}

kernel void environmentKernel(texture2d_array<float, access::write> output [[texture(0)]],
                              constant EnvironmentUniforms& studio [[buffer(0)]],
                              constant StudioPanelUniforms* panels [[buffer(1)]],
                              uint3 texel [[thread_position_in_grid]])
{
    uint size = output.get_width();
    if (texel.x >= size || texel.y >= size)
        return;
    output.write(float4(StudioRadiance(CubeDirection(texel, float(size)), studio, panels), 1.0), texel.xy, texel.z);
}

// The light falling on a matte surface facing each direction: the environment averaged over a cosine.
kernel void irradianceKernel(texturecube<float> environment [[texture(0)]],
                             texture2d_array<float, access::write> output [[texture(1)]],
                             constant float4& params [[buffer(0)]],  // x: the level of the environment to read
                             uint3 texel [[thread_position_in_grid]])
{
    constexpr sampler linearSampler(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_edge);
    uint size = output.get_width();
    if (texel.x >= size || texel.y >= size)
        return;
    float3 n = CubeDirection(texel, float(size));
    float3x3 frame = TangentFrame(n);
    const uint count = 1024;
    float3 sum = float3(0.0);
    for (uint i = 0; i < count; ++i) {
        float2 xi = Hammersley(i, count);
        float phi = 2.0 * PI * xi.x;
        float cosTheta = sqrt(1.0 - xi.y);
        float sinTheta = sqrt(xi.y);
        float3 direction = frame * float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
        sum += environment.sample(linearSampler, direction, level(params.x)).rgb;
    }
    output.write(float4(sum / float(count), 1.0), texel.xy, texel.z);
}

// The environment blurred for one roughness, by importance sampling the GGX lobe.
kernel void prefilterKernel(texturecube<float> environment [[texture(0)]],
                            texture2d_array<float, access::write> output [[texture(1)]],
                            constant float4& params [[buffer(0)]],  // x: roughness, y: the size of the environment
                            uint3 texel [[thread_position_in_grid]])
{
    constexpr sampler linearSampler(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_edge);
    uint size = output.get_width();
    if (texel.x >= size || texel.y >= size)
        return;
    float roughness = params.x;
    float3 n = CubeDirection(texel, float(size));
    if (roughness <= 0.0) {
        output.write(float4(environment.sample(linearSampler, n, level(0.0)).rgb, 1.0), texel.xy, texel.z);
        return;
    }

    float3x3 frame = TangentFrame(n);
    const uint count = 512;
    float texelSolidAngle = 4.0 * PI / (6.0 * params.y * params.y);
    float3 sum = float3(0.0);
    float weights = 0.0;
    for (uint i = 0; i < count; ++i) {
        float3 h = frame * ImportanceSampleGgx(Hammersley(i, count), roughness);
        float3 l = reflect(-n, h);
        float NoL = dot(n, l);
        if (NoL <= 0.0)
            continue;
        // Sparse samples read a blurrier level, so bright spots spread instead of sparkling.
        float NoH = max(dot(n, h), 0.0);
        float pdf = DistributionGgx(NoH, roughness) * 0.25 + 1e-4;
        float sampleSolidAngle = 1.0 / (float(count) * pdf);
        float lod = max(0.5 * log2(sampleSolidAngle / texelSolidAngle) + 1.0, 0.0);
        sum += environment.sample(linearSampler, l, level(lod)).rgb * NoL;
        weights += NoL;
    }
    output.write(float4(sum / max(weights, 1e-4), 1.0), texel.xy, texel.z);
}

float GeometrySchlickGgx(float NoX, float roughness)
{
    float k = roughness * roughness / 2.0;
    return NoX / (NoX * (1.0 - k) + k);
}

// The split-sum lookup table: the scale and bias that turn F0 into the reflected share of the environment.
kernel void brdfKernel(texture2d<float, access::write> output [[texture(0)]], uint2 texel [[thread_position_in_grid]])
{
    uint width = output.get_width();
    uint height = output.get_height();
    if (texel.x >= width || texel.y >= height)
        return;
    float NoV = max((float(texel.x) + 0.5) / float(width), 1e-3);
    float roughness = (float(texel.y) + 0.5) / float(height);
    float3 v = float3(sqrt(1.0 - NoV * NoV), 0.0, NoV);

    const uint count = 1024;
    float scale = 0.0;
    float bias = 0.0;
    for (uint i = 0; i < count; ++i) {
        float3 h = ImportanceSampleGgx(Hammersley(i, count), roughness);
        float3 l = normalize(2.0 * dot(v, h) * h - v);
        float NoL = max(l.z, 0.0);
        float NoH = max(h.z, 0.0);
        float VoH = max(dot(v, h), 0.0);
        if (NoL > 0.0) {
            float g = GeometrySchlickGgx(NoV, roughness) * GeometrySchlickGgx(NoL, roughness);
            float visibility = g * VoH / max(NoH * NoV, 1e-4);
            float fresnel = pow(1.0 - VoH, 5.0);
            scale += (1.0 - fresnel) * visibility;
            bias += fresnel * visibility;
        }
    }
    output.write(float4(scale / float(count), bias / float(count), 0.0, 0.0), texel);
}
