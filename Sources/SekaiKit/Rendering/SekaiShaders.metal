// Analytic Fibonacci sampling adapted from COBE, copyright 2021 Shu Ding, MIT.
// The complete license is bundled in Resources/COBE-LICENSE.txt.
#include <metal_stdlib>
using namespace metal;

struct SekaiUniforms {
    float4 orientation;
    float4 viewport;
    float4 camera;
    float4 ocean;
    float4 land;
    float4 glow;
    float4 options;
    float4 markerColor;
    float4 arcColor;
};
struct Marker { float4 positionSize; float4 color; };
struct Arc { float4 fromHeight; float4 toWidth; float4 color; };
struct GlobeOut { float4 position [[position]]; };
struct OverlayOut {
    float4 position [[position]];
    float2 coordinate;
    float3 world;
    float4 color;
};

float3 rotate(float3 value, float4 q) {
    return value + 2.0 * cross(q.xyz, cross(q.xyz, value) + q.w * value);
}
float4 project(float3 world, constant SekaiUniforms &u) {
    float2 plane = world.xy * (0.8 * u.viewport.w) + u.camera.xy;
    float2 clip = plane * min(u.viewport.x, u.viewport.y) / u.viewport.xy;
    return float4(clip, 0, 1);
}
float3 nearestFibonacci(float3 source, float count, thread float &distance) {
    float3 p = source.xzy;
    constexpr float phi = 1.61803398875;
    constexpr float tau = 6.28318530718;
    float k = max(2.0, floor(log2(max(2.2360679775 * count * M_PI_F * (1.0 - p.z * p.z), 0.000001)) * 0.720210045));
    float2 f = floor(pow(phi, k) / 2.2360679775 * float2(1, phi) + 0.5);
    float2 b1 = fract((f + 1) * (phi - 1)) * tau - 3.88322207745;
    float2 b2 = -2 * f;
    float2 sp = float2(atan2(p.y, p.x), p.z - 1);
    float denominator = b1.x * b2.y - b2.x * b1.y;
    float2 cell = floor(float2(b2.y * sp.x - b1.y * (sp.y * count + 1),
                             -b2.x * sp.x + b1.x * (sp.y * count + 1)) / denominator);
    float3 nearest = p;
    distance = 10;
    for (uint candidate = 0; candidate < 4; candidate++) {
        float index = dot(f, cell + float2(candidate & 1, candidate >> 1));
        if (index < 0 || index >= count) continue;
        uint rank = uint(index);
        float turn = float(rank * 0x9e3779b9u) * (1.0 / 4294967296.0);
        float angle = turn * tau;
        float z = clamp(1.0 - 2.0 * index / count, -1.0, 1.0);
        float radius = sqrt(max(0.0, 1.0 - z * z));
        float3 sample = float3(cos(angle) * radius, sin(angle) * radius, z);
        float d = length(p - sample);
        if (d < distance) { distance = d; nearest = sample; }
    }
    return nearest.xzy;
}
vertex GlobeOut sekaiGlobeVertex(uint id [[vertex_id]]) {
    const float2 corners[] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    return {float4(corners[id], 0, 1)};
}
fragment float4 sekaiGlobeFragment(GlobeOut input [[stage_in]], constant SekaiUniforms &u [[buffer(0)]], texture2d<float> mask [[texture(0)]], texture2d<uint> regions [[texture(1)]], constant float4 *regionColors [[buffer(2)]]) {
    float shortest = max(min(u.viewport.x, u.viewport.y), 1.0);
    float2 plane = float2(input.position.x * 2 - u.viewport.x, u.viewport.y - input.position.y * 2) / shortest;
    plane = (plane - u.camera.xy) / u.viewport.w;
    float radial = length(plane);
    float aa = 2.0 / (shortest * u.viewport.w);
    float sphereAlpha = 1 - smoothstep(0.8 - aa, 0.8 + aa, radial);
    float outsideGlow = exp(-max(radial - 0.8, 0.0) * 45) * u.options.w;
    if (max(sphereAlpha, outsideGlow) * u.options.z < 0.0001) return float4(0);
    float4 color = float4(u.glow.rgb * outsideGlow, outsideGlow);
    if (sphereAlpha > 0) {
        float3 normal = normalize(float3(plane, sqrt(max(0.0, 0.64 - dot(plane, plane)))));
        float4 inverse = float4(-u.orientation.xyz, u.orientation.w);
        float3 world = rotate(normal, inverse);
        float distance;
        float3 sample = nearestFibonacci(world, u.camera.z, distance);
        float2 uv = float2(atan2(sample.x, sample.z) / (2 * M_PI_F) + 0.5,
                          0.5 - asin(clamp(sample.y, -1.0, 1.0)) / M_PI_F);
        constexpr sampler mapSampler(coord::normalized, address::repeat, filter::nearest);
        uint2 regionPixel = uint2(uint(fract(uv.x) * regions.get_width()),
                                  min(regions.get_height() - 1, uint(clamp(uv.y, 0.0, 1.0) * regions.get_height())));
        uint regionID = regions.read(regionPixel).r;
        float4 regionColor = regionColors[regionID];
        float4 landColor = regionColor.a < 0 ? u.land : regionColor;
        float land = mask.sample(mapSampler, uv).r;
        float coverageAA = max(fwidth(distance), 0.00002);
        float dots = land * (1 - smoothstep(max(0.0, u.camera.w - coverageAA), u.camera.w + coverageAA, distance));
        float lighting = 0.4 + 0.6 * pow(max(normal.z, 0.0), u.options.y);
        float materialAlpha = mix(u.ocean.a, landColor.a, dots);
        float surfaceAlpha = materialAlpha * sphereAlpha;
        float3 surface = mix(u.ocean.rgb * u.ocean.a,
                             landColor.rgb * landColor.a * u.options.x, dots) * lighting;
        surface += pow(1 - max(normal.z, 0.0), 4.0) * u.glow.rgb * u.options.w * materialAlpha;
        color = float4(surface * sphereAlpha, surfaceAlpha) + color * (1 - surfaceAlpha);
    }
    return color * u.options.z;
}
vertex OverlayOut sekaiMarkerVertex(uint vertexID [[vertex_id]], uint instance [[instance_id]], constant Marker *markers [[buffer(0)]], constant SekaiUniforms &u [[buffer(1)]]) {
    const float2 corners[] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
    Marker marker = markers[instance];
    float3 world = rotate(marker.positionSize.xyz * 1.005, u.orientation);
    float4 position = project(world, u);
    position.xy += corners[vertexID] * marker.positionSize.w * u.viewport.z / u.viewport.xy;
    return {position, corners[vertexID], world, marker.color.a < 0 ? u.markerColor : marker.color};
}
float3 arcPoint(Arc arc, float t) {
    float3 a = arc.fromHeight.xyz;
    float3 b = arc.toWidth.xyz;
    float cosine = clamp(dot(a,b), -1.0, 1.0);
    float angle = acos(cosine);
    float3 direction;
    if (cosine > 0.99999) direction = normalize(mix(a,b,t));
    else if (cosine < -0.99999) {
        float3 reference = abs(a.y) < 0.9 ? float3(0,1,0) : float3(1,0,0);
        direction = a * cos(M_PI_F*t) + normalize(cross(a,reference)) * sin(M_PI_F*t);
    } else direction = (a*sin((1-t)*angle) + b*sin(t*angle)) / sin(angle);
    return direction * (1.005 + sin(M_PI_F*t) * arc.fromHeight.w);
}
vertex OverlayOut sekaiArcVertex(uint vertexID [[vertex_id]], uint instance [[instance_id]], constant Arc *arcs [[buffer(0)]], constant SekaiUniforms &u [[buffer(1)]]) {
    Arc arc = arcs[instance];
    float t = float(vertexID / 2) / 64.0;
    float3 world = rotate(arcPoint(arc,t),u.orientation);
    float4 position = project(world,u);
    float dt = t < 1 ? 0.001 : -0.001;
    float4 next = project(rotate(arcPoint(arc,t+dt),u.orientation),u);
    float2 direction = (next.xy-position.xy) * u.viewport.xy * sign(dt);
    float lengthSquared = dot(direction,direction);
    float2 tangent = lengthSquared > 0.000001 ? direction * rsqrt(lengthSquared) : float2(1,0);
    float side = vertexID % 2 == 0 ? -1.0 : 1.0;
    position.xy += float2(-tangent.y,tangent.x) * side * arc.toWidth.w * u.viewport.z / u.viewport.xy;
    return {position,float2(side,t),world,arc.color.a < 0 ? u.arcColor : arc.color};
}
bool occluded(float3 world) {
    float radial = dot(world.xy,world.xy);
    return radial < 1 && world.z < sqrt(max(0.0, 1-radial)) - 0.0001;
}
fragment float4 sekaiMarkerFragment(OverlayOut input [[stage_in]], constant SekaiUniforms &u [[buffer(0)]]) {
    if (occluded(input.world)) discard_fragment();
    float radius = length(input.coordinate);
    float alpha = (1-smoothstep(1-max(fwidth(radius),0.001),1.0,radius)) * input.color.a * u.options.z;
    return float4(input.color.rgb*alpha,alpha);
}
fragment float4 sekaiArcFragment(OverlayOut input [[stage_in]], constant SekaiUniforms &u [[buffer(0)]]) {
    if (occluded(input.world)) discard_fragment();
    float alpha = input.color.a * u.options.z;
    return float4(input.color.rgb*alpha,alpha);
}
