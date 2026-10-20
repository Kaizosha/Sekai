import Foundation

/// An sRGB color. Components are normalized at the render boundary.
public struct SekaiColor: Codable, Equatable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  var linear: SIMD4<Float> {
    func component(_ x: Double) -> Float {
      let x = sekaiBound(x, 0...1, fallback: 0)
      return Float(x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4))
    }
    return SIMD4(
      component(red), component(green), component(blue),
      Float(sekaiBound(alpha, 0...1, fallback: 1)))
  }
}

/// Colors and density for the analytic globe. `.automatic` follows the host's appearance.
public struct SekaiStyle: Codable, Equatable, Sendable {
  public enum Appearance: String, Codable, Sendable { case automatic, light, dark }
  public var appearance: Appearance
  public var sampleCount: Int
  public var dotSize: Double
  public var brightness: Double
  public var diffuse: Double
  public var opacity: Double
  public var glow: Double
  public var landColor: SekaiColor?
  public var oceanColor: SekaiColor?
  public var markerColor: SekaiColor
  public var arcColor: SekaiColor

  public init(
    appearance: Appearance = .automatic,
    sampleCount: Int = 16_000,
    dotSize: Double = 0.008,
    brightness: Double = 1,
    diffuse: Double = 1,
    opacity: Double = 1,
    glow: Double = 0.12,
    landColor: SekaiColor? = nil,
    oceanColor: SekaiColor? = nil,
    markerColor: SekaiColor = .init(red: 1, green: 0.55, blue: 0.15),
    arcColor: SekaiColor = .init(red: 0.18, green: 0.57, blue: 0.95)
  ) {
    self.appearance = appearance
    self.sampleCount = sampleCount
    self.dotSize = dotSize
    self.brightness = brightness
    self.diffuse = diffuse
    self.opacity = opacity
    self.glow = glow
    self.landColor = landColor
    self.oceanColor = oceanColor
    self.markerColor = markerColor
    self.arcColor = arcColor
  }

  public static let automatic = Self()
  public static let light = Self(appearance: .light)
  public static let dark = Self(appearance: .dark)

  func palette(dark: Bool) -> (land: SekaiColor, ocean: SekaiColor, glow: SekaiColor) {
    let dark = appearance == .dark || (appearance == .automatic && dark)
    return (
      landColor
        ?? (dark
          ? .init(red: 0.84, green: 0.88, blue: 0.93) : .init(red: 0.19, green: 0.24, blue: 0.30)),
      oceanColor
        ?? (dark
          ? .init(red: 0.07, green: 0.09, blue: 0.13) : .init(red: 0.92, green: 0.94, blue: 0.97)),
      dark ? .init(red: 0.45, green: 0.55, blue: 0.68) : .init(red: 0.72, green: 0.78, blue: 0.86)
    )
  }
}

/// A disk anchored to a geographic coordinate. Size is its diameter in native points.
public struct SekaiMarker: Identifiable, Equatable, Sendable {
  public let id: String
  public var coordinate: SekaiCoordinate
  public var size: Double
  public var color: SekaiColor?

  public init(id: String, coordinate: SekaiCoordinate, size: Double = 6, color: SekaiColor? = nil) {
    self.id = id
    self.coordinate = coordinate
    self.size = size
    self.color = color
  }
}

/// A raised great-circle ribbon. Width is in native points; height is relative to the globe radius.
public struct SekaiArc: Identifiable, Equatable, Sendable {
  public let id: String
  public var from: SekaiCoordinate
  public var to: SekaiCoordinate
  public var height: Double
  public var width: Double
  public var color: SekaiColor?

  public init(
    id: String, from: SekaiCoordinate, to: SekaiCoordinate, height: Double = 0.15,
    width: Double = 1.5, color: SekaiColor? = nil
  ) {
    self.id = id
    self.from = from
    self.to = to
    self.height = height
    self.width = width
    self.color = color
  }
}

/// Rendering availability, separate from animation activity.
public enum SekaiRenderStatus: Equatable, Sendable {
  case preparing
  case ready
  case failed(SekaiRenderError)
}

/// A failed renderer remains stationary and reports why it could not draw.
public enum SekaiRenderError: Error, Equatable, Sendable {
  case metalUnavailable
  case resourceUnavailable
  case pipelineUnavailable
  case allocationFailed
  case renderingFailed
}
