# Sekai

A native SwiftUI globe rendered with Metal. Sekai 2 focuses on a shaded globe,
land dots, markers, and raised great-circle arcs.

```swift
import SekaiKit
import SwiftUI

struct GlobeView: View {
    @State private var camera = SekaiCamera.standard

    var body: some View {
        Sekai(camera: $camera)
            .aspectRatio(1, contentMode: .fit)
    }
}
```

Developed by [Kaizōsha](https://kaizosha.org). Created by
[Kaizō Konpaku](https://x.com/kaizookonpaku).

## Requirements

- Swift 6.2 and Xcode 26 or newer.
- iOS and iPadOS 26, macOS 26, tvOS 26, or visionOS 26.
- A Metal-capable device.

The globe runs offline with a bundled land mask. It requires no account,
API key, network request, MapKit setup, WebView, or location permission.

## Install

Add `https://github.com/Kaizosha/Sekai.git` as a Swift package dependency and
link the `SekaiKit` product.

```swift
.package(url: "https://github.com/Kaizosha/Sekai.git", from: "2.0.0")
```

Sekai 2 is a breaking API revision. Existing atlas and GIS clients can stay on
1.1.0. Read [the migration guide](MIGRATION.md) before upgrading.

## Add motion and overlays

```swift
Sekai(
    camera: $camera,
    style: .automatic,
    activity: .active(rotationSpeed: 0.08),
    interaction: .rotationAndZoom,
    markers: [
        .init(id: "chicago", coordinate: .init(latitude: 41.8781, longitude: -87.6298)),
        .init(id: "tokyo", coordinate: .init(latitude: 35.6762, longitude: 139.6503))
    ],
    arcs: [
        .init(
            id: "chicago-tokyo",
            from: .init(latitude: 41.8781, longitude: -87.6298),
            to: .init(latitude: 35.6762, longitude: 139.6503)
        )
    ]
)
```

Rotation speed is in radians per second. Markers and arcs use stable IDs and
share the globe's camera transform. Arcs follow raised great-circle paths.
They are not a GIS routing or navigation service.

The camera binding owns the requested orientation, zoom, and offset. Use
`camera.focus(on:)` to center a coordinate. Projection is orthographic.

## Control activity

Use `.suspended` when the globe is covered by another surface or is not needed.
The host owns that presentation decision.

```swift
Sekai(
    camera: $camera,
    activity: isGlobeVisible ? .active(rotationSpeed: 0.08) : .suspended,
    interaction: .disabled
)
```

Sekai also respects scene activity, Reduce Motion, and native view attachment.
An idle globe draws on demand. Suspension preserves its angle and stops
continuous rendering. A changed input can request a single redraw.

`SekaiStyle.automatic` follows system appearance. Explicit `.light` and `.dark`
styles are available for fixed artwork. The globe is shaded in Metal; it does
not add a second Liquid Glass background over its content.

## Handle rendering failure

The optional `onStatusChange` closure reports `SekaiRenderStatus`. The status
is `.preparing`, `.ready`, or `.failed` with a typed `SekaiRenderError`.
A failed globe uses a neutral fallback rather than starting an animated CPU
renderer. Use the callback for host-specific messaging.

## Rendering model

The globe uses inverse Fibonacci sampling in a fragment shader and one small
land-mask texture. Density changes a shader input rather than rebuilding a
point atlas. Markers and arcs use separate GPU batches only when present.

This design adapts [COBE's renderer](https://github.com/shuding/cobe), with
native Swift camera state, lifecycle management, and Metal shaders. REA was
used for development-time source analysis. Neither REA nor COBE's JavaScript
runtime is included in the app.

Rendering cost depends on drawable pixels, hardware, and overlay count.
Measure frame pacing and GPU time on the target device before making a
performance claim. See the [performance guide](Sources/SekaiKit/SekaiKit.docc/Performance.md).

## Example and documentation

Open `Examples/SekaiDemo/SekaiDemo.xcodeproj` for a native iPhone and iPad demo.
It links only `SekaiKit` and exposes rotation, appearance, overlays, and camera
reset. Select your own development team before installing it on a device.

The DocC catalog contains [getting started](Sources/SekaiKit/SekaiKit.docc/GettingStarted.md),
[architecture](Sources/SekaiKit/SekaiKit.docc/Architecture.md),
[camera and interaction](Sources/SekaiKit/SekaiKit.docc/CameraAndInteraction.md),
and [verification](Sources/SekaiKit/SekaiKit.docc/TestingAndRelease.md).

## License

Sekai is MIT licensed. The shader adaptation and land mask retain COBE's MIT
notice. See [LICENSE](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md).
