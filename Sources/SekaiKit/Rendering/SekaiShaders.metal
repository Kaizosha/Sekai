#include <metal_stdlib>
using namespace metal;

struct SekaiParticle {
    float3 position;
    uint rank;
};

struct SekaiUniforms {
    float4 quaternion;
    float4 color;
    float2 viewport;
    float2 offset;
    float zoom;
    float pointSize;
    float spinAngle;
    float reserved;
    uint projection;
    float projectionScale;
    float4 optical;
    float4 material;
    float4 environment;
};

struct SekaiPointOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float depth;
    float4 optical;
    float4 material;
    float illumination;
};

float3 rotateQuaternion(float3 value, float4 quaternion) {
    return value + 2.0 * cross(quaternion.xyz, cross(quaternion.xyz, value) + quaternion.w * value);
}

vertex SekaiPointOut sekaiUnifiedParticleVertex(
    uint vertexID [[vertex_id]],
    constant SekaiParticle *particles [[buffer(0)]],
    constant SekaiUniforms &uniforms [[buffer(1)]]) {
    SekaiPointOut output;
    float4 spin = float4(0.0, sin(uniforms.spinAngle * 0.5), 0.0, cos(uniforms.spinAngle * 0.5));
    float3 worldPosition = rotateQuaternion(particles[vertexID].position, spin);
    float3 position = rotateQuaternion(worldPosition, uniforms.quaternion);
    float aspect = max(uniforms.viewport.x / max(uniforms.viewport.y, 1.0), 0.001);
    float scale = uniforms.zoom;
    if (uniforms.projection != 0) {
        scale *= uniforms.projectionScale / max(0.35, 3.0 - position.z);
    }
    output.position = float4(position.x * scale / aspect + uniforms.offset.x,
                             position.y * scale + uniforms.offset.y,
                             1.0 - clamp(position.z, -1.0, 1.0), 1.0);
    bool visible = position.z > 0.0 && abs(output.position.x) <= 1.05 && abs(output.position.y) <= 1.05;
    output.pointSize = visible ? max(0.5, uniforms.pointSize * uniforms.zoom) : 0.0;
    output.color = uniforms.color;
    output.depth = position.z;
    output.optical = uniforms.optical;
    output.material = uniforms.material;
    float daylight = smoothstep(-0.18, 0.18, dot(normalize(worldPosition), uniforms.environment.xyz));
    output.illumination = uniforms.environment.w < 0.0
        ? 1.0
        : mix(saturate(uniforms.environment.w), 1.0, daylight);
    return output;
}

fragment float4 sekaiUnifiedParticleFragment(SekaiPointOut input [[stage_in]], float2 coordinate [[point_coord]]) {
    float2 centered = coordinate * 2.0 - 1.0;
    float radius = length(centered);
    if (radius > 1.0) discard_fragment();
    float coreRadius = mix(0.22, 0.72, saturate(input.material.x));
    float core = 1.0 - smoothstep(coreRadius, 1.0, radius);
    float halo = (1.0 - smoothstep(0.08, 1.0, radius)) * saturate(input.material.y);
    float edge = max(core, halo * 0.58);
    float refraction = input.optical.z * 0.34 * saturate(radius);
    float highlight = pow(max(0.0, 1.0 - length(centered - float2(-0.34, -0.34))), 6.0) * input.optical.y;
    float depthFade = mix(1.0 - saturate(input.optical.w) * 0.45, 1.0, saturate(input.depth));
    float3 spectral = float3(1.0 + refraction * 0.08, 1.0, 1.0 - refraction * 0.08);
    float3 glassColor = input.color.rgb * spectral * input.optical.x * (0.88 + highlight * 0.55) * input.illumination;
    return float4(glassColor, input.color.a * edge * depthFade);
}

fragment float4 sekaiUnifiedLineFragment(SekaiPointOut input [[stage_in]]) {
    float depthFade = mix(0.35, 1.0, saturate(input.depth));
    float highlight = 1.0 + input.optical.y * 0.12;
    return float4(input.color.rgb * highlight * input.illumination, input.color.a * depthFade);
}
