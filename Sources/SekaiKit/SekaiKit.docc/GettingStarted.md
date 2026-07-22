# Getting Started

Install `SekaiKit`, retain camera state in the host, and declare ordered layers.

```swift
import SekaiKit
import SwiftUI

struct ContentView: View {
    @State private var camera = SekaiCamera.standard

    var body: some View {
        Sekai(camera: $camera) {
            SekaiLayer.landParticles()
        }
        .padding()
    }
}
```

The camera binding is required because interaction is state, not hidden view
state. Styles and layer values can be persisted with Codable. Keep annotations
and routes identified with stable IDs.

Required: `SekaiKit`, a camera binding, and at least one layer. Optional:
custom style, interaction options, performance policy, overlays, network data,
GeoJSON, and location.
