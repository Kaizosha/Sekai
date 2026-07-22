# Layers

`SekaiLayer` is the complete scene vocabulary. Built-in geographic filters are
shared by particles, boundaries, labels, picking, and counts.

- Particle and boundary layers select `.allLand`, continent, sovereign,
  country, map unit, or an explicit feature set.
- Annotation and user-location layers place elevated points.
- Route layers support great-circle, rhumb, and custom curves.
- Polyline and polygon layers accept arbitrary host coordinates.
- Physical, circle, heatmap, label, and texture values reserve typed scene
  semantics without coupling source data to a renderer.

Layer order is stable. IDs must be unique within one scene. Per-layer styles
override aggregate `SekaiStyle` values where supported.

GeoJSON belongs in `SekaiGeoJSON`; location belongs in `SekaiLocation`. This
keeps the core deterministic and permission-free.
