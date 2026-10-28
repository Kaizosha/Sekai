import Foundation
@preconcurrency import MetalKit
import Testing
@testable import SekaiKit

extension SekaiMetalTests {
  @Test func territoryMaterialChangesOnlyItsOwnDots() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.style = .init(dotSize: 0.06, diffuse: 0, glow: 0,
      landColor: .init(red: 1, green: 0, blue: 0),
      oceanColor: .init(red: 0, green: 0, blue: 1))
    input.regions = [.init(regionCode: "JP", color: .init(red: 0, green: 1, blue: 0))]
    let center = (128 * 256 + 128) * 4
    for (latitude, longitude, selected) in [
      (36.0, 138.0, true), (37.5, 127.0, false), (35.0, 105.0, false)
    ] {
      input.camera.focus(on: .init(latitude: latitude, longitude: longitude))
      let values = try pixels(renderer, input: input)
      #expect(values[center + (selected ? 1 : 2)] > 230)
      #expect(values[center + (selected ? 2 : 1)] < 20)
    }
    input.camera.focus(on: .init(latitude: 36, longitude: 138))
    let selectedJapan = try pixels(renderer, input: input)
    input.regions = []
    let unselectedJapan = try pixels(renderer, input: input)
    #expect(selectedJapan != unselectedJapan)
    #expect(stride(from: 0, to: selectedJapan.count, by: 4).allSatisfy {
      selectedJapan[$0] == unselectedJapan[$0] && selectedJapan[$0 + 3] == unselectedJapan[$0 + 3]
    })
    input.regions = [.init(regionCode: "JP", color: .init(red: 0, green: 1, blue: 0))]
    input.camera.focus(on: .init(latitude: 0, longitude: -140))
    let highlightedOcean = try pixels(renderer, input: input)
    input.regions = []
    let clearOcean = try pixels(renderer, input: input)
    #expect(Array(clearOcean[center..<center + 4]) == Array(highlightedOcean[center..<center + 4]))
    for code in ["ZZ", "419", "EU", "EZ", "UN"] {
      input.regions = [.init(regionCode: code, color: .init(red: 0, green: 1, blue: 0),
        fallbackCoordinate: .init(latitude: 0, longitude: -140))]
      #expect(try pixels(renderer, input: input) == clearOcean)
    }
  }

  @Test func multipleTerritoriesAndDisconnectedLandUseExactRegionIDs() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.style = .init(dotSize: 0.06, diffuse: 0, glow: 0,
      landColor: .init(red: 1, green: 0, blue: 0))
    input.regions = [
      .init(regionCode: "US", color: .init(red: 0, green: 1, blue: 0)),
      .init(regionCode: "RU", color: .init(red: 0, green: 1, blue: 0))
    ]
    for coordinate in [SekaiCoordinate(latitude: 39, longitude: -98),
      .init(latitude: 64, longitude: -151), .init(latitude: 67, longitude: 179),
      .init(latitude: 67, longitude: -179)] {
      input.camera.focus(on: coordinate)
      let values = try pixels(renderer, input: input)
      let center = (128 * 256 + 128) * 4
      #expect(values[center + 1] > 230 && values[center + 2] < 20)
    }
  }

  @Test(arguments: [(22.3, 114.2, "HK"), (35.0, 33.0, "CY")])
  func regionFallbackIsOnlyUsedWhenNoDotExistsAndDuplicateRegionUsesLastMaterial(
    latitude: Double, longitude: Double, code: String
  ) throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.style = .init(sampleCount: 14_000, diffuse: 0, glow: 0,
      landColor: .init(red: 0.5, green: 0.5, blue: 0.5))
    let smallTerritory = SekaiCoordinate(latitude: latitude, longitude: longitude)
    input.camera.focus(on: smallTerritory)
    input.regions = [.init(regionCode: code, color: .init(red: 0, green: 1, blue: 0))]
    let withoutAnchor = try pixels(renderer, input: input)
    input.regions[0].fallbackCoordinate = smallTerritory
    let withAnchor = try pixels(renderer, input: input)
    #expect(withAnchor != withoutAnchor)
    let center = (128 * 256 + 128) * 4
    #expect(withAnchor[center + 1] > 230)
    input.regions.append(.init(regionCode: code, color: .init(red: 1, green: 0, blue: 0),
      fallbackCoordinate: smallTerritory))
    let duplicate = try pixels(renderer, input: input)
    #expect(duplicate[center + 2] > 230 && duplicate[center + 1] < 20)

    let japan = SekaiCoordinate(latitude: 36, longitude: 138)
    input.camera.focus(on: japan)
    input.regions = [.init(regionCode: "JP", color: .init(red: 0, green: 1, blue: 0))]
    let region = try pixels(renderer, input: input)
    input.regions[0].fallbackCoordinate = japan
    #expect(try pixels(renderer, input: input) == region)
  }

  @Test func cameraAndAppearanceKeepTheRegionPaletteStable() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.style.sampleCount = 14_000
    input.regions = [.init(regionCode: "JP", color: .init(red: 0.4, green: 0.5, blue: 0.25))]
    input.camera.focus(on: .init(latitude: 36, longitude: 138))
    let light = try pixels(renderer, input: input)
    #expect(renderer.regionUploads == 1)
    let overlays = renderer.markerUploads
    input.camera.zoom = 1.2
    input.dark = true
    let dark = try pixels(renderer, input: input)
    #expect(renderer.regionUploads == 1 && renderer.markerUploads == overlays)
    #expect(light != dark)
    try save(light, name: "Sekai-Region-Japan-Light.png")
    try save(dark, name: "Sekai-Region-Japan-Dark.png")
    input.regions[0].color = .init(red: 0.7, green: 0.55, blue: 0.3)
    _ = try pixels(renderer, input: input)
    #expect(renderer.regionUploads == 2)
    input.regions = []
    _ = try pixels(renderer, input: input)
    #expect(renderer.regionUploads == 3)
  }
}
