# Camera And Interaction

`SekaiCamera.orientation` is a normalized quaternion. Horizontal drag applies
yaw; upward drag applies positive visual movement through pitch. Quaternion
composition prevents pole inversion and gimbal lock.

`SekaiInteractionOptions` independently controls rotation, zoom, selection,
inertia, double-tap zoom, automatic rotation, and camera bounds. Interaction
does not stop automatic rotation by default. Tap and pointer picking use the
same CPU projection as the Metal shader and return stable `SekaiSelection`
values.

Orthographic projection is the stable default. Perspective projection accepts
a 15-to-80-degree field of view. Zoom is clamped after magnification.

Use `SekaiCamera.fit` to frame atlas features or bounds. Use
`SekaiCameraController` for cancellable, eased transitions based on quaternion
slerp and logarithmic zoom interpolation.

The renderer, labels, selection indicator, and hit testing share one pause-safe
rotation clock. Markers and routes therefore remain anchored during automatic
rotation and after pauses.
