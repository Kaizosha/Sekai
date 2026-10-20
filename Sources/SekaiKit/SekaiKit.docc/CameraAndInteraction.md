# Camera and interaction

`SekaiCamera` is the host's requested camera state. It contains quaternion
orientation, zoom, and horizontal and vertical offsets. Projection is
orthographic.

```swift
camera.focus(on: SekaiCoordinate(latitude: 35.6762, longitude: 139.6503))
```

`SekaiInteraction.rotationAndZoom` enables native input. Use `.disabled` for
decorative globes. Automatic rotation belongs to `SekaiActivity`, independently
of whether direct interaction is enabled.

```swift
Sekai(
    camera: $camera,
    activity: .active(rotationSpeed: 0.08),
    interaction: .rotationAndZoom
)
```

The renderer uses one monotonic rotation clock. Suspension preserves the angle
and excludes time spent inactive. Markers and great-circle arcs use the same
combined camera transform as the land mask.

Coordinates use latitude and longitude in degrees. The geographic origin is
at positive Z, north is positive Y, and longitude increases toward positive X.

Beginning a native drag commits the currently displayed automatic spin into the
bound camera once, then pauses autonomous spin until the drag ends. A host's
new requested orientation starts from that absolute orientation; changing zoom,
style or offsets preserves the accumulated spin. Zoom is constrained to 0.5
through 4. There is no detached inertia task after a gesture ends.
