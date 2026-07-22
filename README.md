# Sekai

Sekai is an offline-first, native globe package for SwiftUI. One bundled
Natural Earth atlas drives particles, boundaries, hierarchy, search, labels,
and filtering. Metal renders dense geographic content while SwiftUI provides
the native Liquid Glass sphere and interface.

Developed by [Kaizōsha](https://kaizosha.org) and created by
[Kaizō Konpaku](https://x.com/kaizookonpaku).

- Homepage: [kaizosha.org/sekai](https://kaizosha.org/sekai/)
- Organization: [@KaizoshaX](https://x.com/KaizoshaX)
- Author: [@kaizookonpaku](https://x.com/kaizookonpaku)

## Preview

<p align="center">
  <img src="Documentation/Media/SekaiDemo-iOS.gif" alt="Sekai on iPhone" width="320">
</p>

## Requirements

- Swift 6.2
- Xcode 26 or newer
- iOS/iPadOS 26, macOS 26, tvOS 26, watchOS 26, or visionOS 26

Sekai needs no network connection, account, API key, MapKit setup, JavaScript,
WebView, or location permission. `SekaiLocation` requests permission only when
the host explicitly uses it.

## Installation

Add `https://github.com/Kaizosha/Sekai.git` in Xcode, then link only the
products the app uses:

- `SekaiKit`: required globe, atlas, camera, styles, layers, and renderer
- `SekaiGeoJSON`: optional GeoJSON conversion
- `SekaiLocation`: optional Core Location bridge
- `SekaiInspector`: optional development inspector and demo

```swift
.package(url: "https://github.com/Kaizosha/Sekai.git", from: "1.0.0")
```

## Minimal Use

```swift
import SekaiKit
import SwiftUI

struct GlobeView: View {
    @State private var camera = SekaiCamera.standard

    var body: some View {
        Sekai(camera: $camera) {
            SekaiLayer.landParticles()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
```

The production default is a clear white native-glass sphere, adaptive black or
white particles, orthographic projection, automatic density, no labels, no
sample markers, and no sample routes.

## Compose A Map

Layers are ordered back to front and use one coordinate system.

```swift
let chicago = SekaiCoordinate(latitude: 41.8781, longitude: -87.6298)
let tokyo = SekaiCoordinate(latitude: 35.6762, longitude: 139.6503)

Sekai(camera: $camera, style: style, interaction: interaction) {
    SekaiLayer.landParticles(filter: .allLand)
    SekaiLayer.regionBoundaries(filter: .country("JPN"))
    SekaiLayer.routes(id: "flights", values: [
        SekaiRoute(id: "ord-hnd", from: chicago, to: tokyo)
    ])
    SekaiLayer.annotations(id: "cities", values: [
        SekaiAnnotation(id: "chicago", coordinate: chicago, title: "Chicago"),
        SekaiAnnotation(id: "tokyo", coordinate: tokyo, title: "Tokyo")
    ])
}
```

Built-in layer values cover particles, boundaries, physical features,
annotations, routes, polylines, polygons, circles, heat points, labels,
textures, and user location. Unsupported visual layers remain data values until
their renderer is enabled; this lets hosts persist one scene schema.

## Geography

`SekaiAtlas.bundled` is the only built-in geography source. It contains:

- Natural Earth 1:10m Admin 0 Map Units
- 1,048,576 deterministic equal-area land particles
- map-unit, country, sovereign, continent, region, and subregion hierarchy
- three vector levels of detail
- localized names, labels, bounds, and political worldview classifications

```swift
let atlas = SekaiAtlas.bundled
let india = atlas.search("India")
let available = atlas.availableParticleCount(for: .country("IND"))
```

Country filters intentionally include territories represented by Natural
Earth under that Admin 0 country. Use `.mapUnit("FRA")` when an application
needs one map unit rather than the aggregate `.country("FRA")`.

Density is explicit:

- `.automatic`: policy-selected interactive count
- `.count(n)`: exactly `n`, or all available when a region has fewer
- `.fraction(x)`: a deterministic fraction of the selected source
- `.maximum`: every available source point, with no hidden cap

All modes select deterministic prefixes from the same master hierarchy, so
changing density never changes the underlying map.

## Camera And Interaction

`SekaiCamera` uses a normalized quaternion, avoiding gimbal lock and inverted
vertical drag. Its state includes projection, zoom, and screen offset.

```swift
var interaction = SekaiInteractionOptions(
    allowsRotation: true,
    allowsZoom: true,
    autoRotationSpeed: 0.08,
    stopsAutoRotationOnInteraction: false
)
```

Touching the globe does not disable rotation unless
`stopsAutoRotationOnInteraction` is explicitly enabled. Automatic rotation,
particles, boundaries, routes, and markers share one GPU transform.

Projection modes are `.orthographic` and `.perspective(fieldOfViewDegrees:)`.
Camera zoom is constrained by `SekaiCameraBounds`.

## Styling

`SekaiStyle` is Codable, Equatable, and Sendable. It groups:

- `globe`: material, tint, opacity, lighting, darkness, rim, and glow
- `particles`: adaptive color, density, size, opacity, optical response, fade
- `boundaries`: fill/stroke colors, opacity, width, highlight, refraction
- `annotations`: color, size, elevation, halo, core, highlight
- `routes`: color, width, elevation, opacity, pattern, progress, endpoints
- `labels`: color, zoom threshold, count, collision padding
- `environment`: background, stars, atmosphere, sun, ambient light, terminator

```swift
var style = SekaiStyle.standard
style.particles.density = .maximum
style.particles.size = 0.55
style.environment.showsStars = true
style.environment.atmosphereIntensity = 0.4
```

SwiftUI cannot efficiently instantiate native Liquid Glass for hundreds of
thousands of individual views. Sekai therefore uses native Liquid Glass for the
sphere and controls, and a matching optical Metal material for dense particles,
routes, boundaries, and markers. This is the production path that preserves
appearance without view-count stalls.

## Performance Policy

- `.adaptive(minimumFramesPerSecond:)`: selects an interactive source count and
  can evolve render scale or LOD in documented releases
- `.exact`: honors requested source detail; `.maximum` remains maximum
- `.batterySaver`: uses a smaller automatic count and 30 FPS presentation

Explicit `.count`, `.fraction`, and `.maximum` density values are never silently
changed. Static globes pause `MTKView` and perform no continuous frame work.
watchOS uses a capped Canvas presentation while preserving the same atlas and
public scene model.

## Optional Modules

### GeoJSON

```swift
import SekaiGeoJSON

let group = try SekaiGeoJSON.decode(data, layerID: "earthquakes")
```

FeatureCollection, Feature, Point, MultiPoint, LineString, MultiLineString,
Polygon, and MultiPolygon are decoded with `JSONSerialization` into typed Sekai
layers.

### Location

```swift
import SekaiLocation

@State private var location = SekaiLocationProvider()
```

The host remains responsible for the appropriate Info.plist usage description.

### Inspector And Demo

```swift
import SekaiInspector

SekaiDemo()
```

`SekaiDemo` is the package's only reference UI. `SekaiInspector` can also be
embedded separately. `SekaiCodeExporter.minimalIntegration` provides a
copyable implementation snippet.

## Atlas Reproducibility

The checked-in runtime atlas is generated by `Tools/SekaiAtlasBuilder`. Sources
and SHA-256 checksums are pinned in `sources.json`.

```sh
python3 -m venv .venv
.venv/bin/pip install -r Tools/SekaiAtlasBuilder/requirements.txt
.venv/bin/python Tools/SekaiAtlasBuilder/build_atlas.py \
  --output Sources/SekaiKit/Resources/SekaiWorld.sekaiatlas
```

Do not edit the binary atlas manually. Change the manifest or builder, rebuild,
and commit both generator and artifact.

## Documentation

The DocC catalog covers integration, architecture, atlas format, layers,
interaction, styling, performance, optional modules, testing, and data
attribution. See `Sources/SekaiKit/SekaiKit.docc`.

## License

Sekai source is available under the repository license. Natural Earth data is
public domain; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
