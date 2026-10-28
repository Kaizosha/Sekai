import Foundation

/// Colors a territory's existing land dots without painting its ocean or neighboring territories.
/// Region codes use ISO 3166-1 alpha-2. Unknown codes draw no highlight.
public struct SekaiRegionHighlight: Equatable, Sendable {
  public let regionCode: String
  public var color: SekaiColor
  /// A representative point for a territory too small to contain a globe dot.
  public var fallbackCoordinate: SekaiCoordinate?

  /// The optional anchor is drawn only when the current dot density has no sample in this territory.
  public init(
    regionCode: String, color: SekaiColor, fallbackCoordinate: SekaiCoordinate? = nil
  ) {
    self.regionCode = regionCode.uppercased()
    self.color = color
    self.fallbackCoordinate = fallbackCoordinate
  }
}
