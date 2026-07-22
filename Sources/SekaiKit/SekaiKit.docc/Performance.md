# Performance

Sekai uploads contiguous point and overlay buffers once per scene change.
Camera, appearance, and optical changes update small uniforms. Automatic
rotation is shader-side. A static `MTKView` is paused and draws only after
state changes.

`.automatic` density resolves to 65,536 particles in adaptive mode, 16,384 in
battery-saver mode, and the source maximum in exact mode. Explicit count,
fraction, and maximum requests retain their meaning.

Use `.adaptive(minimumFramesPerSecond: 60)` for interactive apps. Use `.exact`
for captures, controlled hardware, or deliberate maximum-density presentation.
Use `.batterySaver` for ambient and low-power surfaces.

Measure release builds on physical devices. Test static, rotation, drag, zoom,
all land, a small map unit, aggregate countries, boundaries, routes, markers,
light/dark appearance, Reduce Motion, low-power mode, and thermal pressure.
