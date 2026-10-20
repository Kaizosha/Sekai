# Architecture

Sekai 2 has one production product and one rendering path.

The SwiftUI `Sekai` view receives immutable style, activity, interaction, marker,
and arc values. A binding supplies the requested camera. The package does not
own application navigation or persist host preferences.

One native Metal view coordinator owns the device, command queue, pipelines,
mask texture, overlay buffers, and render clock. The globe uses analytical
inverse Fibonacci sampling in a fullscreen fragment pass. Markers and arcs
use GPU batches with the same camera transform.

Camera, color, and density changes update uniforms. Overlay buffers change
when their values change. There is no point-atlas preparation actor, scene
cache, country lookup index, or per-frame SwiftUI timeline.

The renderer controls cadence from activity, scene state, motion accessibility,
and attachment. Dismantling stops drawing and releases its owned callbacks and
resources. Typed failures are visible to the host through `onStatusChange`.

The shader and local mask are adapted from COBE under its MIT license. REA
was used for source analysis during development. Neither tool introduces a
runtime JavaScript or network dependency.
