import Foundation
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
}
