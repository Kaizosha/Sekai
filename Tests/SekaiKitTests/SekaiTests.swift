import Foundation
import SekaiGeoJSON
import Testing
@testable import SekaiKit

struct SekaiTests {
    @Test func bundledAtlasIsCompleteAndSelfDescribing() {
        let atlas = SekaiAtlas.bundled
        #expect(atlas.information.particleCount == SekaiAtlas.maximumParticleCount)
        #expect(atlas.information.mapUnitCount == atlas.features.count)
        #expect(atlas.information.source.contains("Natural Earth"))
        #expect(atlas.features.count > 290)
        #expect(atlas.countries.count > 250)
        #expect(atlas.continents.contains("Asia"))
    }

    @Test func oneSourceProvidesGlobalAndRegionalParticles() throws {
        let atlas = SekaiAtlas.bundled
        let india = try #require(atlas.search("India").first { $0.countryID?.rawValue == "IND" })
        let exact = atlas.particles(matching: .country("IND"), density: .count(2_000))
        let maximum = atlas.particles(matching: .country("IND"), density: .maximum)
        #expect(exact.count == min(2_000, maximum.count))
        #expect(maximum.count == atlas.availableParticleCount(for: .country("IND")))
        #expect(maximum.allSatisfy { atlas.feature(id: $0.featureID)?.countryID == india.countryID })
        #expect(Array(maximum.prefix(exact.count)) == exact)
    }

    @Test func franceIncludesItsNaturalEarthMapUnitsWithoutInventedGeometry() {
        let atlas = SekaiAtlas.bundled
        let frenchUnits = atlas.features.filter { $0.countryID?.rawValue == "FRA" }
        #expect(frenchUnits.contains { $0.name.localizedCaseInsensitiveContains("France") })
        #expect(frenchUnits.count > 1)
        #expect(atlas.availableParticleCount(for: .country("FRA")) > 0)
    }

    @Test func densityNeverExceedsOrSilentlyCapsRequestedValues() {
        let atlas = SekaiAtlas.bundled
        let available = atlas.availableParticleCount(for: .continent("Europe"))
        #expect(atlas.particles(matching: .continent("Europe"), density: .count(777)).count == min(777, available))
        #expect(atlas.particles(matching: .continent("Europe"), density: .maximum).count == available)
    }

    @Test func lowDensityPrefixRemainsGloballyDistributed() {
        let values = SekaiAtlas.bundled.particles(density: .count(2_000))
        #expect(values.filter { $0.coordinate.latitude > 0 }.count > 500)
        #expect(values.filter { $0.coordinate.latitude < 0 }.count > 250)
        #expect(values.filter { $0.coordinate.longitude > 0 }.count > 500)
        #expect(values.filter { $0.coordinate.longitude < 0 }.count > 500)
    }

    @Test func coordinateAndAntimeridianBoundsNormalizeCorrectly() {
        #expect(SekaiCoordinate(latitude: 120, longitude: 540) == SekaiCoordinate(latitude: 90, longitude: 180))
        let bounds = SekaiCoordinateBounds(south: -20, west: 170, north: 20, east: -170)
        #expect(bounds.contains(.init(latitude: 0, longitude: 179)))
        #expect(bounds.contains(.init(latitude: 0, longitude: -179)))
        #expect(!bounds.contains(.init(latitude: 0, longitude: 0)))
    }

    @Test func quaternionCameraRemainsNormalizedAfterRepeatedRotations() {
        var orientation = SekaiQuaternion.identity
        for _ in 0..<10_000 {
            orientation = SekaiQuaternion.axisAngle(x: 0.2, y: 1, z: 0, radians: 0.001) * orientation
        }
        let length = sqrt(orientation.x * orientation.x + orientation.y * orientation.y
                          + orientation.z * orientation.z + orientation.w * orientation.w)
        #expect(abs(length - 1) < 0.000_001)
    }

    @Test func upwardDragPitchMovesTheFrontSurfaceUp() {
        let upwardDrag = SekaiQuaternion.axisAngle(x: 1, y: 0, z: 0, radians: -0.2)
        let moved = SekaiVector3(SekaiCoordinate(latitude: 0, longitude: 0)).rotated(by: upwardDrag)
        #expect(moved.y > 0)
    }

    @Test func cameraAndStylesRoundTripThroughCodable() throws {
        var camera = SekaiCamera.standard
        camera.zoom = 3.25
        camera.projection = .perspective(fieldOfViewDegrees: 42)
        var style = SekaiStyle.standard
        style.particles.density = .maximum
        style.environment.showsStars = true
        let cameraData = try JSONEncoder().encode(camera)
        let styleData = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(SekaiCamera.self, from: cameraData) == camera)
        #expect(try JSONDecoder().decode(SekaiStyle.self, from: styleData) == style)
    }

    @Test func contentBuilderPreservesLayerOrder() {
        let content = SekaiLayerGroup([
            .landParticles(),
            .regionBoundaries(filter: .country("JPN")),
            .annotations(id: "places", values: [.init(id: "tokyo", coordinate: .init(latitude: 35.6762, longitude: 139.6503))])
        ])
        #expect(content.sekaiLayers.map(\.id) == ["sekai.land.particles", "sekai.regions.boundaries", "places"])
    }

    @Test func preparedScenePreservesRendererLayerOrder() {
        var particleStyle = SekaiParticleStyle.standard
        particleStyle.density = .count(8)
        let layers: [SekaiLayer] = [
            .landParticles(id: "land", style: particleStyle),
            .annotations(id: "places", values: [
                .init(id: "origin", coordinate: .init(latitude: 0, longitude: 0))
            ]),
            .routes(id: "routes", values: [
                .init(
                    id: "east",
                    from: .init(latitude: 0, longitude: 0),
                    to: .init(latitude: 0, longitude: 20)
                )
            ]),
            .polygons(id: "areas", values: [
                .init(id: "box", rings: [[
                    .init(latitude: 1, longitude: 1),
                    .init(latitude: 1, longitude: 2),
                    .init(latitude: 2, longitude: 2),
                    .init(latitude: 2, longitude: 1)
                ]])
            ])
        ]
        let key = SekaiSceneKey(
            sourceLayers: layers,
            particleLayers: [.init(id: "land", filter: .allLand, density: .count(8))],
            defaultAnnotationElevation: SekaiStyle.standard.annotations.elevation,
            defaultRouteElevation: SekaiStyle.standard.routes.elevation,
            defaultRouteProgress: SekaiStyle.standard.routes.progress,
            defaultRoutePattern: SekaiStyle.standard.routes.pattern,
            defaultRouteEndpointSize: 0,
            automaticParticleLimit: 8
        )
        let scene = SekaiPreparedScene.prepare(key: key, defaultStyle: .standard)
        let order = scene.drawOrder.map { reference in
            switch reference {
            case let .particles(index): "particles:\(index)"
            case let .surface(index): "surface:\(index)"
            case let .line(index): "line:\(index)"
            case let .points(index): "points:\(index)"
            }
        }
        #expect(order == ["particles:0", "points:0", "line:0", "points:1", "surface:0"])
    }

    @Test func quaternionSlerpUsesTheShortestNormalizedPath() {
        let destination = SekaiQuaternion.axisAngle(x: 0, y: 1, z: 0, radians: .pi)
        let halfway = SekaiQuaternion.slerp(.identity, destination, progress: 0.5)
        let vector = SekaiVector3(SekaiCoordinate(latitude: 0, longitude: 0)).rotated(by: halfway)
        #expect(abs(vector.x - 1) < 0.000_001)
        #expect(abs(vector.z) < 0.000_001)
    }

    @Test func vectorSlerpHandlesAntipodalCoordinatesDeterministically() {
        let start = SekaiVector3(SekaiCoordinate(latitude: 0, longitude: 0))
        let end = SekaiVector3(SekaiCoordinate(latitude: 0, longitude: 180))
        let halfway = SekaiVector3.slerp(start, end, progress: 0.5)
        #expect(abs(halfway.length - 1) < 0.000_001)
        #expect(halfway.x.isFinite && halfway.y.isFinite && halfway.z.isFinite)
        #expect(abs(halfway.dot(start)) < 0.000_001)
    }

    @Test func cameraFitHandlesDatelineBoundsAndRespectsLimits() {
        var camera = SekaiCamera.standard
        let limits = SekaiCameraBounds(minimumZoom: 0.75, maximumZoom: 4)
        camera.fit(
            SekaiCoordinateBounds(south: -10, west: 170, north: 20, east: -165),
            padding: 0.1,
            limits: limits
        )
        #expect((limits.minimumZoom...limits.maximumZoom).contains(camera.zoom))
        let center = SekaiVector3(SekaiCoordinate(latitude: 5, longitude: -177.5)).rotated(by: camera.orientation)
        #expect(center.z > 0.99)
    }

    @Test func projectionRoundTripsOrthographicAndPerspectiveCoordinates() throws {
        let coordinate = SekaiCoordinate(latitude: 12, longitude: 18)
        for projection in [SekaiProjectionMode.orthographic, .perspective(fieldOfViewDegrees: 42)] {
            let camera = SekaiCamera(orientation: .identity, zoom: 1.3, projection: projection)
            let context = SekaiProjectionContext(
                size: CGSize(width: 320, height: 320),
                camera: camera,
                spinAngle: 0.2
            )
            let point = try #require(context.project(coordinate)?.point)
            let result = try #require(context.unproject(point))
            #expect(abs(result.latitude - coordinate.latitude) < 0.000_1)
            #expect(abs(SekaiCoordinate.normalizedLongitude(result.longitude - coordinate.longitude)) < 0.000_1)
        }
    }

    @Test func atlasReverseLookupUsesTheSameGeographySource() throws {
        let atlas = SekaiAtlas.bundled
        let chicago = SekaiCoordinate(latitude: 41.8781, longitude: -87.6298)
        let usaFeatures = Set(atlas.features(matching: .country("USA")).map(\.id))
        let feature = try #require(atlas.feature(
            nearest: chicago,
            among: usaFeatures,
            maximumDistanceDegrees: 1
        ))
        #expect(feature.countryID?.rawValue == "USA")
        let japanFeatures = Set(atlas.features(matching: .country("JPN")).map(\.id))
        #expect(atlas.feature(nearest: chicago, among: japanFeatures, maximumDistanceDegrees: 1) == nil)
    }

    @Test func preparedSceneCompletesRoutesPolygonsLabelsAndPicking() throws {
        var routeStyle = SekaiRouteStyle.standard
        routeStyle.progress = 0.5
        routeStyle.pattern = .dashed(length: 0.05, gap: 0.03)
        routeStyle.endpointSize = 0.08
        let marker = SekaiCoordinate(latitude: 0, longitude: 0)
        let polygon = SekaiPolygon(
            id: "concave",
            rings: [[
                .init(latitude: 0, longitude: 0),
                .init(latitude: 0, longitude: 8),
                .init(latitude: 4, longitude: 4),
                .init(latitude: 8, longitude: 8),
                .init(latitude: 8, longitude: 0)
            ]]
        )
        let layers: [SekaiLayer] = [
            .annotations(id: "markers", values: [.init(id: "origin", coordinate: marker)]),
            .routes(id: "routes", values: [
                .init(
                    id: "half",
                    from: marker,
                    to: .init(latitude: 0, longitude: 90),
                    style: routeStyle
                )
            ]),
            .polygons(id: "areas", values: [polygon]),
            .labels(id: "labels", filter: .country("JPN"), style: nil)
        ]
        let key = SekaiSceneKey(
            sourceLayers: layers,
            particleLayers: [],
            defaultAnnotationElevation: SekaiStyle.standard.annotations.elevation,
            defaultRouteElevation: SekaiStyle.standard.routes.elevation,
            defaultRouteProgress: SekaiStyle.standard.routes.progress,
            defaultRoutePattern: SekaiStyle.standard.routes.pattern,
            defaultRouteEndpointSize: SekaiStyle.standard.routes.endpointSize,
            automaticParticleLimit: 2_000
        )
        let scene = SekaiPreparedScene.prepare(key: key, defaultStyle: .standard)
        #expect(scene.lineBatches.first?.vertices.isEmpty == false)
        #expect(scene.lineBatches.first?.vertices.count ?? 0 < 128)
        if let routeHead = scene.lineBatches.first?.vertices.last?.position {
            let radius = sqrt(
                routeHead.x * routeHead.x
                + routeHead.y * routeHead.y
                + routeHead.z * routeHead.z
            )
            #expect(radius > 1.1)
        } else {
            Issue.record("Expected a progressive route head")
        }
        #expect(scene.surfaceBatches.first?.fillVerticesByLevelOfDetail[0].count ?? 0 >= 9)
        #expect(scene.pointBatches.reduce(0) { $0 + $1.vertices.count } == 3)
        #expect(!scene.labels.isEmpty)

        let result = scene.pick(
            at: CGPoint(x: 100, y: 100),
            context: SekaiProjectionContext(
                size: CGSize(width: 200, height: 200),
                camera: .init(orientation: .identity),
                spinAngle: 0
            )
        )
        #expect(result?.selection == .annotation("origin"))
    }

    @Test func rhumbRouteInterpolatesInMercatorSpace() throws {
        var routeStyle = SekaiRouteStyle.standard
        routeStyle.elevation = 0
        routeStyle.endpointSize = 0
        let layers: [SekaiLayer] = [
            .routes(id: "rhumb", values: [
                .init(
                    id: "north",
                    from: .init(latitude: 0, longitude: 0),
                    to: .init(latitude: 60, longitude: 0),
                    curve: .rhumb,
                    style: routeStyle
                )
            ])
        ]
        let key = SekaiSceneKey(
            sourceLayers: layers,
            particleLayers: [],
            defaultAnnotationElevation: SekaiStyle.standard.annotations.elevation,
            defaultRouteElevation: SekaiStyle.standard.routes.elevation,
            defaultRouteProgress: SekaiStyle.standard.routes.progress,
            defaultRoutePattern: SekaiStyle.standard.routes.pattern,
            defaultRouteEndpointSize: SekaiStyle.standard.routes.endpointSize,
            automaticParticleLimit: 1
        )
        let scene = SekaiPreparedScene.prepare(key: key, defaultStyle: .standard)
        let midpoint = try #require(scene.lineBatches.first?.vertices[128].position)
        let coordinate = SekaiVector3(
            x: Double(midpoint.x),
            y: Double(midpoint.y),
            z: Double(midpoint.z)
        ).coordinate
        #expect(abs(coordinate.latitude - 35.264_39) < 0.001)
    }

    @Test func geoJSONStylesBecomeNativeLayerStyles() throws {
        let data = Data("""
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "id": 7,
              "properties": {
                "name": "Zone",
                "fill": "#3366CC",
                "fill-opacity": 0.4,
                "stroke": "#FF0000",
                "stroke-width": 2
              },
              "geometry": {
                "type": "Polygon",
                "coordinates": [[[0,0],[5,0],[5,5],[0,5],[0,0]]]
              }
            },
            {
              "type": "Feature",
              "id": "place",
              "properties": {
                "marker-color": "#00FF00",
                "marker-size": "large"
              },
              "geometry": {
                "type": "Point",
                "coordinates": [1, 1]
              }
            }
          ]
        }
        """.utf8)
        let group = try SekaiGeoJSON.decode(data)
        guard case let .polygons(_, polygons) = try #require(group.sekaiLayers.first) else {
            Issue.record("Expected a polygon layer")
            return
        }
        let style = try #require(polygons.first?.style)
        #expect(style.fillOpacity == 0.4)
        #expect(style.strokeWidth == 2)
        guard case let .fixed(stroke) = style.strokeColor else {
            Issue.record("Expected a fixed stroke color")
            return
        }
        #expect(stroke.red == 1)
        #expect(stroke.green == 0)
        #expect(stroke.blue == 0)
        guard case let .annotations(_, annotations) = try #require(group.sekaiLayers.last) else {
            Issue.record("Expected an annotation layer")
            return
        }
        #expect(annotations.first?.style?.size == 1.5)
        #expect(annotations.first?.style?.color.green == 1)
    }

    @Test func polygonTessellationPreservesInteriorHoles() {
        let triangles = SekaiPolygonTessellator.triangles(for: [
            [
                .init(latitude: 0, longitude: 0),
                .init(latitude: 0, longitude: 10),
                .init(latitude: 10, longitude: 10),
                .init(latitude: 10, longitude: 0)
            ],
            [
                .init(latitude: 3, longitude: 3),
                .init(latitude: 7, longitude: 3),
                .init(latitude: 7, longitude: 7),
                .init(latitude: 3, longitude: 7)
            ]
        ])
        #expect(!triangles.isEmpty)
        #expect(triangles.count.isMultiple(of: 3))
        let coordinates = triangles.map {
            SekaiVector3(
                x: Double($0.position.x),
                y: Double($0.position.y),
                z: Double($0.position.z)
            ).coordinate
        }
        let area = stride(from: 0, to: coordinates.count, by: 3).reduce(into: 0.0) { total, index in
            let first = coordinates[index]
            let second = coordinates[index + 1]
            let third = coordinates[index + 2]
            total += abs(
                first.longitude * (second.latitude - third.latitude)
                + second.longitude * (third.latitude - first.latitude)
                + third.longitude * (first.latitude - second.latitude)
            ) * 0.5
        }
        #expect(abs(area - 84) < 2)
    }
}
