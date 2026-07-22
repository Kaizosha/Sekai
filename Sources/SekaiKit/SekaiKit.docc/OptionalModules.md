# Optional Modules

`SekaiGeoJSON.decode` converts RFC 7946 coordinate order (longitude, latitude)
into typed Sekai layers. Invalid coordinate nesting throws instead of guessing.
It also maps the common Simple Style properties for marker color, size, and
opacity; line stroke, width, and opacity; and polygon fill and stroke. Supply a
`SekaiGeoJSONDefaults` value when data omits those properties.

```swift
let content = try SekaiGeoJSON.decode(data, defaults: .standard)
```

`SekaiLocationProvider` is MainActor observable state around
`CLLocationManager`. The host requests authorization, owns Info.plist usage
strings, starts and stops updates, and decides whether to add its annotation.

`SekaiInspector` contains reusable development controls. `SekaiDemo` is the one
reference UI and can be excluded from production by omitting that product.

`SekaiCodeExporter` emits a minimal SwiftUI integration or a filtered density
example. Generated snippets are convenience output, not a persistence format;
persist Codable values instead.
