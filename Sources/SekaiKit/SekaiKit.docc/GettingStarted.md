# Getting started

Add the `SekaiKit` product to a SwiftUI app, then bind a camera to the globe.

```swift
import SekaiKit
import SwiftUI

struct ContentView: View {
    @State private var camera = SekaiCamera.standard

    var body: some View {
        Sekai(camera: $camera)
            .padding()
    }
}
```

Set activity to rotate the globe or suspend it when covered.

```swift
Sekai(
    camera: $camera,
    activity: isVisible ? .active(rotationSpeed: 0.08) : .suspended,
    interaction: .disabled
)
```

Add identified values to `markers` and `arcs` when overlays are needed.
Every overlay shares the globe's camera transform. Keep navigation, sheets,
application preferences, and language choices in the host app.

The optional `onStatusChange` callback reports preparation, readiness, or a
typed failure. A rendering failure does not start a CPU animation fallback.
