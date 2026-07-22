# ``SekaiKit``

Build a layered, interactive, offline globe from one high-detail atlas.

## Overview

Sekai combines a SwiftUI-first API, native Liquid Glass presentation, a Metal
geography renderer, and a reproducible Natural Earth 1:10m atlas. The package
does not require MapKit, a network connection, or host assets.

```swift
@State private var camera = SekaiCamera.standard

Sekai(camera: $camera) {
    SekaiLayer.landParticles()
}
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Architecture>
- <doc:Atlas>
- <doc:Layers>

### Presentation

- <doc:CameraAndInteraction>
- <doc:Styling>
- <doc:Performance>

### Integration

- <doc:OptionalModules>
- <doc:TestingAndRelease>

### Core API

- ``Sekai``
- ``SekaiAtlas``
- ``SekaiCamera``
- ``SekaiStyle``
- ``SekaiLayer``
- ``SekaiFeature``
- ``SekaiCodeExporter``
