# Styling

`SekaiStyle` groups globe, particle, boundary, annotation, route, label, and
environment values. Values are not inspector metadata; rendering consumes them.

Adaptive colors resolve from system appearance. Particle brightness,
highlight, refraction, depth fade, opacity, and size are shader uniforms, so
editing them does not rebuild geography. Density and region filters do rebuild
the relevant prepared buffer.

Native Liquid Glass is used for the sphere and interface surfaces. Dense map
elements use a GPU optical material because a native view per point is not
viable at 1,048,576 points. This hybrid is intentional and should be described
accurately in product UI.

Environments can set background, stars, atmosphere, sun coordinates, ambient
light, and a day/night terminator. Visual environment settings require no
network. System environment behavior follows color scheme, Reduce Motion,
thermal state, and platform presentation conventions.
