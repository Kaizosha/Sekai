# Changelog

## 1.1.0

- Added atlas, annotation, route, polygon, circle, heat-point, and hover hit
  testing through stable `SekaiSelection` bindings.
- Added inertial quaternion dragging and a pause-safe shared rotation clock.
- Added feature and antimeridian-aware camera fitting, camera interpolation,
  and cancellable `SekaiCameraController` flights.
- Added measured adaptive particle submission with hysteresis, three boundary
  LODs, and accurate logical-versus-submitted render metrics.
- Added independent per-layer Metal batches and optical materials.
- Completed route progress, dash patterns, elevated arcs, widths, and endpoint
  rendering.
- Added collision-managed native-glass labels, concave polygon fills, polygon
  holes, geodesic circles, heat points, and physical boundary lines.
- Added GeoJSON marker, line, and polygon style conversion.
- Expanded the Demo inspector and behavioral test suite.

## 1.0.0

- Added a SwiftUI-first globe for all current Apple platforms.
- Added one reproducible Natural Earth 1:10m atlas with 1,048,576 deterministic
  land particles, map-unit geometry, hierarchy, localization, and worldviews.
- Added quaternion drag, zoom, orthographic and perspective cameras, and
  shader-synchronized automatic rotation.
- Added composable particles, boundaries, annotations, routes, polylines,
  polygons, circles, heatmap, labels, texture, physical, and user-location
  layer values.
- Added native Liquid Glass globe presentation and a Metal optical material for
  dense particles and overlays.
- Added explicit adaptive, exact, and battery-saver policies without silently
  changing explicit density requests.
- Added separate GeoJSON, Core Location, and Inspector products.
- Added one Demo, copyable integration output, Swift Testing coverage, DocC,
  atlas generation tools, provenance, and release documentation.
