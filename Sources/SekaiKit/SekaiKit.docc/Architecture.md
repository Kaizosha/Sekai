# Architecture

Sekai 2 has one production product and one rendering path.

The SwiftUI `Sekai` view receives immutable style, activity, interaction, marker,
arc, and territory-material values. A binding supplies the requested camera. The package does not
own application navigation or persist host preferences.

One native Metal view coordinator owns the device, command queue, pipelines,
land and territory textures, overlay buffers, and render clock. The globe uses analytical
inverse Fibonacci sampling in a fullscreen fragment pass. Markers and arcs
use GPU batches with the same camera transform.

Camera and base color changes update uniforms. Territory material changes update
a compact palette. Density changes recompute territory sample coverage only when
needed for small-territory anchors. Overlay buffers change when their values change. There is no point-atlas preparation actor, scene
cache, vector geometry tree, or per-frame SwiftUI timeline.

The bundled integer territory mask uses the same nearest Fibonacci coordinate
as the land mask. Its texels are never interpolated. Selecting a territory changes only its existing land-dot material, preserving
the original land coverage and ocean. The renderer loads that map once and releases its texture on stop.

The renderer controls cadence from activity, scene state, motion accessibility,
and attachment. Dismantling stops drawing and releases its owned callbacks and
resources. Typed failures are visible to the host through `onStatusChange`.

The shader and local mask are adapted from COBE under its MIT license. REA
was used for source analysis during development. Neither tool introduces a
runtime JavaScript or network dependency.
