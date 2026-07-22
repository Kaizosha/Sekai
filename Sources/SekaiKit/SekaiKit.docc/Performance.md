# Performance

Sekai uploads contiguous point and overlay buffers once per scene change.
Camera, appearance, and optical changes update small uniforms. Automatic
rotation is shader-side. A static `MTKView` is paused and draws only after
state changes.

`.automatic` prepares up to 262,144 particles in adaptive mode, 32,768 in
battery-saver mode, and the source maximum in exact mode. Explicit count,
fraction, and maximum requests retain their logical meaning.

Use `.adaptive(minimumFramesPerSecond: 60)` for interactive apps. Use `.exact`
for captures, controlled hardware, or deliberate maximum-density presentation.
Use `.batterySaver` for ambient and low-power surfaces.

Adaptive mode measures rolling presentation rate. Two low-rate windows reduce
the submitted deterministic prefix and boundary detail; three healthy windows
restore quality. Hysteresis prevents oscillation. `SekaiRenderMetrics` reports
logical, submitted, policy-culled, frame-time, and LOD values. Exact mode never
adapts requested geometry.

Measure release builds on physical devices. Test static, rotation, drag, zoom,
all land, a small map unit, aggregate countries, boundaries, routes, markers,
light/dark appearance, Reduce Motion, low-power mode, and thermal pressure.
