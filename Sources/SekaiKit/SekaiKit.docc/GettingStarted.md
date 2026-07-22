# Getting Started

Install `SekaiKit`, retain camera state in the host, and declare ordered layers.

```swift
import SekaiKit
import SwiftUI

struct ContentView: View {
    @State private var camera = SekaiCamera.standard
    @State private var selection: SekaiSelection?

    var body: some View {
        Sekai(camera: $camera, selection: $selection) {
            SekaiLayer.landParticles()
            SekaiLayer.labels(filter: .allLand)
        }
        .padding()
    }
}
```

The camera binding is required because interaction is state, not hidden view
state. The optional selection binding reports atlas regions, annotations,
routes, polygons, circles, and other custom features. Keep every annotation and
overlay identified with a stable ID.

Use ``SekaiCameraController`` when the host needs cancellable animated camera
transitions:

```swift
@State private var cameraController = SekaiCameraController()

Sekai(camera: $cameraController.camera) {
    SekaiLayer.landParticles()
}

Button("Show Japan") {
    if let japan = SekaiAtlas.bundled.search("Japan").first {
        cameraController.fit(japan)
    }
}
```

Styles, cameras, layers, and interaction options conform to `Codable` where
their values are suitable for persistence.

Required: `SekaiKit`, a camera binding, and at least one layer. Optional:
selection and hover bindings, custom style, interaction options, performance
policy, overlays, labels, network data, GeoJSON, and location.
