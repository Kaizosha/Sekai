# Migration from 1.x

Sekai 2 is a breaking revision. It replaces the atlas and generic layer API
with a focused native Metal globe, markers, arcs, and a camera binding.

Use `Sekai(camera: $camera)` without a layer builder. Pass marker values to
`markers` and raised great-circle arc values to `arcs`. Automatic rotation is
part of `SekaiActivity`. Use `.suspended` when the host covers the globe.

The atlas, country hierarchy and search, GIS geometry, selection and hover
bindings, native labels, GeoJSON conversion, location bridge, Inspector,
perspective camera, and watchOS Canvas implementation were removed.
Reserved texture, annotation clustering, and dragging controls were removed
rather than retained as no-op options.

The complete migration inventory and before-and-after examples are in the
[repository migration guide](https://github.com/Kaizosha/Sekai/blob/main/MIGRATION.md).
Version 1.1.0 remains available for clients that require the removed features.
