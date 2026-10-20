# Performance

The globe's fragment shader reconstructs the sphere and finds nearby Fibonacci
samples. Its main cost depends on drawable pixels. Sample count is a uniform,
rather than the length of an uploaded point array.

Markers and arcs add GPU work when present. They retain their buffers across
camera and appearance changes. The package does not publish draw submissions
as measured displayed frames per second.

An active rotating globe uses native rendering cadence. A static globe draws
on demand. Suspension and inactive presentation stop autonomous drawing and
preserve the accumulated angle. Use `.suspended` when a host-owned sheet covers
the globe.

Measure a Release build on the intended physical device. Record drawable size,
render scale, appearance, sample count, overlay count, and target refresh rate.
Check actual present intervals, GPU duration, main-thread work, memory, and
thermal state. Verify output and failures during every comparison.

Include rotation, direct manipulation, resize, background and foreground,
Reduce Motion, repeated presentation, and a settled suspended interval. A
suspended interval must produce no autonomous submissions after in-flight work
finishes. A lower source size or vertex count alone is not a measured speedup.
