# Architecture

Sekai has four boundaries:

1. Value API: camera, style, features, filters, and layers are Codable Sendable
   values.
2. Atlas: one immutable memory-mapped file owns built-in coordinates and
   hierarchy.
3. Scene preparation: filters deterministic atlas records off the main actor
   and prepares contiguous GPU buffers.
4. Presentation: SwiftUI owns native glass and gestures; Metal owns dense
   geometry and applies one quaternion transform to every GPU layer.

There is no raster fallback and no second region sample source. Data adapters
produce `SekaiLayer` values and do not reach into rendering internals.

The products are deliberately separate. `SekaiKit` never links Core Location
or the inspector. `SekaiGeoJSON` and `SekaiLocation` depend only on the core.
`SekaiInspector` is development UI and is not required in production apps.
