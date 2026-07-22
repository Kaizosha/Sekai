# Architecture

Sekai has four boundaries:

1. Value API: camera, style, features, filters, and layers are Codable Sendable
   values.
2. Atlas: one immutable memory-mapped file owns built-in coordinates and
   hierarchy.
3. Scene preparation: an actor filters deterministic atlas records, reuses
   lock-protected geometry caches, tessellates host geometry, and produces
   identity-preserving draw and pick batches.
4. Presentation: SwiftUI owns native glass, labels, and gestures; Metal owns
   dense geometry and applies one quaternion transform to every GPU layer.

Visual uniforms do not rebuild the master atlas geometry. Adaptive policy
changes submitted prefixes and prebuilt boundary LODs without changing source
identity. CPU projection, GPU projection, labels, and hit testing share the same
camera and rotation math.

There is no raster fallback and no second region sample source. Data adapters
produce `SekaiLayer` values and do not reach into rendering internals.

The products are deliberately separate. `SekaiKit` never links Core Location
or the inspector. `SekaiGeoJSON` and `SekaiLocation` depend only on the core.
`SekaiInspector` is development UI and is not required in production apps.
