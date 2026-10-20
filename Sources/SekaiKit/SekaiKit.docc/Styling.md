# Styling

`SekaiStyle.automatic` follows the host's color scheme. Use `.light` or `.dark`
for a fixed appearance.

```swift
Sekai(camera: $camera, style: .automatic)
```

The style controls the shaded globe and land-dot appearance. Marker and arc
values can override their colors. Appearance changes update render inputs,
without creating a new point atlas.

The globe is a Metal drawing. It does not create a native Liquid Glass sphere
or one SwiftUI view per dot. Hosts can use native glass for surrounding buttons
and toolbars without layering another material over the globe.

Compose the globe over the host background and inspect transparent edges in
Light and Dark appearances. Do not assume one palette is legible on every
custom background.
