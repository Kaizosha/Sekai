# Migrate from Sekai 1.x to 2.x

Sekai 2 replaces the atlas and generic layer engine with a focused native
Metal globe. This release is not source compatible with 1.x. Version 1.1.0
remains the choice for existing GIS, atlas, or watchOS integrations.

## Replace products and layer declarations

Link only `SekaiKit`. Remove `SekaiGeoJSON`, `SekaiLocation`, and
`SekaiInspector` dependencies and imports.

Before:

```swift
Sekai(camera: $camera, selection: $selection) {
    SekaiLayer.landParticles()
}
```

After:

```swift
Sekai(camera: $camera)
```

There is no content builder or `SekaiLayer` in 2.x. The bundled map is a small
land mask rather than the 1.x Natural Earth atlas. No runtime atlas download
or conversion replaces it.

## Move automatic rotation into activity

Before:

```swift
var interaction = SekaiInteractionOptions()
interaction.autoRotationSpeed = 0.08
Sekai(camera: $camera, interaction: interaction)
```

After:

```swift
Sekai(
    camera: $camera,
    activity: .active(rotationSpeed: 0.08),
    interaction: .rotationAndZoom
)
```

Use `.suspended` when covered. Use `.disabled` for decorative globes.
Reduce Motion and inactive scenes stop autonomous rotation.

## Replace annotations and routes

Replace `SekaiAnnotation` values with `SekaiMarker` values and pass them to
`markers`. Replace `SekaiRoute` values with `SekaiArc` values and pass them
to `arcs`. Retain stable IDs and coordinates.

```swift
Sekai(
    camera: $camera,
    markers: [.init(id: "tokyo", coordinate: tokyo)],
    arcs: [.init(id: "flight", from: chicago, to: tokyo)]
)
```

The 2.x arc is a raised great-circle path. Route progress, dash patterns,
rhumb paths, and route endpoint styling are not part of the new arc API.
COBE's quadratic Bézier routes are a rendering reference, not a claim of
identical route geometry.

## Replace styles and camera helpers

Start with `.automatic`, `.light`, or `.dark`. The style no longer contains
nested globe, particle, boundary, annotation, route, label, and environment
objects. Native Liquid Glass sphere materials, refraction controls, stars,
and day-night simulation were removed.

`SekaiCamera` retains quaternion orientation, zoom, and offsets. Use
`focus(on:)` or `focused(on:)` with a coordinate. Atlas feature fitting,
`SekaiCameraController`, and perspective projection were removed. The new
renderer uses orthographic projection only.

## Removed capabilities

The following 1.x APIs have no replacement in this focused globe package:

- Atlas feature lookup, search, localized country hierarchy, political
  worldviews, country filters, boundary geometry, and reverse region lookup.
- Selection and hover-selection bindings, atlas picking, and native labels.
- Polygons, polygon holes, polylines, geodesic circles, heatmaps, physical
  geography layers, and reserved texture layers.
- GeoJSON conversion, Core Location integration, the Inspector product, and
  code export helpers.
- Adaptive particle-prefix policies, `SekaiRenderMetrics`, and per-layer LOD.
- The old gesture inertia and sleeping camera-flight tasks. Native drag and pinch input update the bound camera directly.
- Annotation clustering and dragging settings that 1.x exposed without a
  working renderer implementation.
- watchOS Canvas rendering. The 2.x platform declarations cover native Metal
  destinations only.

Keep the last 1.x version if these features are required. Sekai 2 does not
silently ignore their inputs or fabricate geography.

## Update failure handling and verification

Observe `onStatusChange` if the host needs an explicit rendering failure.
Replace assumptions about atlas loading with the typed native render status.

Verify appearance, transparent composition, camera motion, pause and resume,
front and rear overlays, and host sheet transitions on physical devices.
The smaller resource and different draw model do not establish a measured
frame-time improvement on their own.
