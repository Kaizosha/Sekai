import Foundation
import Testing
@testable import SekaiKit

struct SekaiRegionTests {
  @Test(arguments: [
    (36.0, 138.0, "JP"), (37.5, 127.0, "KR"), (35.0, 105.0, "CN"),
    (39.0, -98.0, "US"), (64.0, -151.0, "US"), (-25.0, 134.0, "AU"),
    (47.0, 2.0, "FR"), (45.0, 10.0, "IT"), (-17.8, 178.0, "FJ"),
    (67.0, 179.0, "RU"), (67.0, -179.0, "RU")
  ])
  func maskPreservesTerritoriesAndBothSidesOfTheAntimeridian(
    latitude: Double, longitude: Double, code: String
  ) throws {
    let map = try #require(SekaiRegionMap.bundled)
    #expect(map.identifier(at: .init(latitude: latitude, longitude: longitude)) ==
      SekaiRegionMap.identifier(for: code))
  }

  @Test(arguments: [(0.0, -140.0), (30.0, -40.0), (33.0, 132.0), (90.0, 0.0)])
  func oceansAndStraitsHaveNoTerritory(latitude: Double, longitude: Double) throws {
    let map = try #require(SekaiRegionMap.bundled)
    #expect(map.identifier(at: .init(latitude: latitude, longitude: longitude)) == 0)
  }

  @Test func regionCodesAndSmallTerritoriesDoNotInventGeography() throws {
    for code in ["ZZ", "EU", "EZ", "UN"] {
      #expect(SekaiRegionMap.identifier(for: code) == nil)
    }
    #expect(SekaiRegionMap.identifier(for: "419") == nil)
    #expect(SekaiRegionMap.identifier(for: "A") == nil)
    #expect(SekaiRegionMap.identifier(for: "ZZZZ") == nil)
    #expect(SekaiRegionHighlight(regionCode: "jp", color: .init(red: 0, green: 1, blue: 0)).regionCode == "JP")
    let map = try #require(SekaiRegionMap.bundled)
    let samples = map.sampledIdentifiers(count: 14_000)
    #expect(samples.contains(try #require(SekaiRegionMap.identifier(for: "JP"))))
    for code in ["HK", "MO", "SG", "CY"] {
      #expect(!samples.contains(try #require(SekaiRegionMap.identifier(for: code))))
    }
  }

  @Test func invalidMaskDataIsRejectedBeforeTextureAllocation() throws {
    let url = try #require(Bundle.module.url(forResource: "RegionMask", withExtension: "rle"))
    let valid = try Data(contentsOf: url)
    #expect(SekaiRegionMap(data: valid) != nil)
    #expect(SekaiRegionMap(data: valid.dropLast()) == nil)
    var badMagic = valid
    badMagic[0] = 0
    #expect(SekaiRegionMap(data: badMagic) == nil)
    let runsStart = 12 + (Int(valid[10]) | (Int(valid[11]) << 8)) * 2
    func replacingWord(at offset: Int, with value: UInt16) -> Data {
      var bytes = valid
      bytes[offset] = UInt8(value & 255)
      bytes[offset + 1] = UInt8(value >> 8)
      return bytes
    }
    #expect(SekaiRegionMap(data: replacingWord(at: 10, with: 0)) == nil)
    #expect(SekaiRegionMap(data: replacingWord(at: 10, with: 65535)) == nil)
    #expect(SekaiRegionMap(data: replacingWord(at: 12, with: 0)) == nil)
    #expect(SekaiRegionMap(data: replacingWord(at: 12, with: 65535)) == nil)
    let firstIdentifier = UInt16(valid[12]) | (UInt16(valid[13]) << 8)
    #expect(SekaiRegionMap(data: replacingWord(at: 14, with: firstIdentifier)) == nil)
    #expect(SekaiRegionMap(data: valid.prefix(runsStart - 1)) == nil)
    #expect(SekaiRegionMap(data: replacingWord(at: runsStart + 2, with: 0)) == nil)
    #expect(SekaiRegionMap(data: replacingWord(at: runsStart, with: 65535)) == nil)
    var extraRun = valid
    extraRun.append(contentsOf: [0, 0, 1, 0])
    #expect(SekaiRegionMap(data: extraRun) == nil)
  }
}
