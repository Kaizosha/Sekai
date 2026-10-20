import Foundation

/// The requested orthographic camera. Offsets are in units of half the shorter view dimension.
public struct SekaiCamera: Codable, Equatable, Sendable {
  public var orientation: SekaiQuaternion
  public var zoom: Double
  public var offsetX: Double
  public var offsetY: Double

  public init(
    orientation: SekaiQuaternion = .identity,
    zoom: Double = 1,
    offsetX: Double = 0,
    offsetY: Double = 0
  ) {
    self.orientation = orientation
    self.zoom = zoom
    self.offsetX = offsetX
    self.offsetY = offsetY
  }

  public static let standard = Self(orientation: .lookingAt(.init(latitude: 12, longitude: 10)))

  public mutating func focus(on coordinate: SekaiCoordinate) {
    orientation = .lookingAt(coordinate)
  }

  public func focused(on coordinate: SekaiCoordinate) -> Self {
    var result = self
    result.focus(on: coordinate)
    return result
  }

  var normalized: Self {
    Self(
      orientation: .init(x: orientation.x, y: orientation.y, z: orientation.z, w: orientation.w),
      zoom: sekaiBound(zoom, 0.5...4, fallback: 1),
      offsetX: sekaiBound(offsetX, -4...4, fallback: 0),
      offsetY: sekaiBound(offsetY, -4...4, fallback: 0)
    )
  }
}

/// Autonomous rotation in radians per second, or a retained stationary presentation.
public enum SekaiActivity: Equatable, Sendable {
  case active(rotationSpeed: Double = 0)
  case suspended

  var speed: Double {
    switch self {
    case .active(let speed): sekaiBound(speed, -4...4, fallback: 0)
    case .suspended: 0
    }
  }
}

/// Native drag and pinch behavior. No per-frame SwiftUI animation is required.
public enum SekaiInteraction: Equatable, Sendable {
  case disabled
  case rotation
  case rotationAndZoom
}

func sekaiBound(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
  value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
}
