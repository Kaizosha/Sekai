# Camera And Interaction

`SekaiCamera.orientation` is a normalized quaternion. Horizontal drag applies
yaw; upward drag applies positive visual movement through pitch. Quaternion
composition prevents pole inversion and gimbal lock.

`SekaiInteractionOptions` independently controls rotation, zoom, selection,
annotation dragging, inertia, double-tap zoom, automatic rotation, and camera
bounds. Interaction does not stop automatic rotation by default.

Orthographic projection is the stable default. Perspective projection accepts
a 15-to-80-degree field of view. Zoom is clamped after magnification.

The renderer computes automatic rotation in the same vertex shader used by
particles, boundaries, markers, and routes. Do not animate overlay positions on
a separate clock.
