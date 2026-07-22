# Layers

`SekaiLayer` is the complete scene vocabulary. Built-in geographic filters are
shared by particles, boundaries, labels, picking, and counts.

- Particle and boundary layers select `.allLand`, continent, sovereign,
  country, map unit, or an explicit feature set.
- Annotation and user-location layers place elevated points.
- Route layers support great-circle, rhumb, and custom curves.
- Polyline and polygon layers accept arbitrary host coordinates. Polygon fills
  use local ear-clipping tessellation and support interior rings.
- Circles are generated geodesically, heat points use weighted optical fields,
  and labels use zoom thresholds plus screen-space collision management.
- Physical coastline and administrative boundary requests use atlas vectors.
- Texture values reserve typed scene semantics for a future raster product.

Layer order is stable. IDs must be unique within one scene. Particle, boundary,
annotation, route, polyline, polygon, circle, label, and imported GeoJSON styles
retain independent GPU material batches.

GeoJSON belongs in `SekaiGeoJSON`; location belongs in `SekaiLocation`. This
keeps the core deterministic and permission-free.
