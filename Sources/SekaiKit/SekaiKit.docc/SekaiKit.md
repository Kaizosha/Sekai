# ``SekaiKit``

Present an offline SwiftUI globe with native Metal rendering.

## Overview

Sekai 2 contains a shaded globe, land dots, territory highlights, markers, arcs, and a quaternion
camera. The host retains its camera binding and controls whether the globe
is active or suspended.

```swift
@State private var camera = SekaiCamera.standard

Sekai(camera: $camera)
```

The package uses bundled land and territory masks. It does not require a network,
MapKit, a WebView, or location permission.

## Topics

### Start and migrate

- <doc:GettingStarted>
- <doc:Migration>

### Configure the globe

- <doc:CameraAndInteraction>
- <doc:Styling>
- <doc:Architecture>
- <doc:Performance>
- <doc:TestingAndRelease>

### Public values

- ``Sekai``
- ``SekaiCamera``
- ``SekaiCoordinate``
- ``SekaiQuaternion``
- ``SekaiStyle``
- ``SekaiActivity``
- ``SekaiInteraction``
- ``SekaiMarker``
- ``SekaiArc``
- ``SekaiRegionHighlight``
- ``SekaiRenderStatus``
- ``SekaiRenderError``
