import CoreGraphics
import Foundation

/// A WGS84 coordinate in decimal degrees.
public struct SekaiCoordinate: Codable, Hashable, Sendable {
  public var latitude: Double
  public var longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = min(max(latitude.isFinite ? latitude : 0, -90), 90)
    self.longitude = Self.normalizedLongitude(longitude)
  }

  static func normalizedLongitude(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    var result = value.truncatingRemainder(dividingBy: 360)
    if result > 180 { result -= 360 }
    if result < -180 { result += 360 }
    return result
  }
}

/// A Codable quaternion used as Sekai's gimbal-free camera orientation.
public struct SekaiQuaternion: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var z: Double
  public var w: Double

  public init(x: Double, y: Double, z: Double, w: Double) {
    let length = sqrt(x * x + y * y + z * z + w * w)
    if length.isFinite, length > .leastNonzeroMagnitude {
      self.x = x / length
      self.y = y / length
      self.z = z / length
      self.w = w / length
    } else {
      self = .identity
    }
  }

  public static let identity = SekaiQuaternion(uncheckedX: 0, y: 0, z: 0, w: 1)

  public static func axisAngle(x: Double, y: Double, z: Double, radians: Double) -> Self {
    let axisLength = max(sqrt(x * x + y * y + z * z), .leastNonzeroMagnitude)
    let half = radians * 0.5
    let scale = sin(half) / axisLength
    return Self(x: x * scale, y: y * scale, z: z * scale, w: cos(half))
  }

  public static func lookingAt(_ coordinate: SekaiCoordinate) -> Self {
    let yaw = axisAngle(x: 0, y: 1, z: 0, radians: -coordinate.longitude * .pi / 180)
    let pitch = axisAngle(x: 1, y: 0, z: 0, radians: coordinate.latitude * .pi / 180)
    return pitch * yaw
  }

  public static func * (left: Self, right: Self) -> Self {
    Self(
      x: left.w * right.x + left.x * right.w + left.y * right.z - left.z * right.y,
      y: left.w * right.y - left.x * right.z + left.y * right.w + left.z * right.x,
      z: left.w * right.z + left.x * right.y - left.y * right.x + left.z * right.w,
      w: left.w * right.w - left.x * right.x - left.y * right.y - left.z * right.z
    )
  }

  public var inverse: Self {
    Self(x: -x, y: -y, z: -z, w: w)
  }

  public static func slerp(_ start: Self, _ end: Self, progress: Double) -> Self {
    let t = min(max(progress.isFinite ? progress : 0, 0), 1)
    var destination = end
    var cosine = start.x * end.x + start.y * end.y + start.z * end.z + start.w * end.w
    if cosine < 0 {
      cosine = -cosine
      destination = Self(uncheckedX: -end.x, y: -end.y, z: -end.z, w: -end.w)
    }
    guard cosine < 0.9995 else {
      return Self(
        x: start.x + (destination.x - start.x) * t,
        y: start.y + (destination.y - start.y) * t,
        z: start.z + (destination.z - start.z) * t,
        w: start.w + (destination.w - start.w) * t
      )
    }
    let angle = acos(min(max(cosine, -1), 1))
    let denominator = sin(angle)
    let a = sin((1 - t) * angle) / denominator
    let b = sin(t * angle) / denominator
    return Self(
      x: start.x * a + destination.x * b,
      y: start.y * a + destination.y * b,
      z: start.z * a + destination.z * b,
      w: start.w * a + destination.w * b
    )
  }

  private init(uncheckedX x: Double, y: Double, z: Double, w: Double) {
    self.x = x
    self.y = y
    self.z = z
    self.w = w
  }
}

struct SekaiVector3 {
  let x: Double
  let y: Double
  let z: Double

  init(_ coordinate: SekaiCoordinate) {
    let latitude = coordinate.latitude * .pi / 180
    let longitude = coordinate.longitude * .pi / 180
    x = cos(latitude) * sin(longitude)
    y = sin(latitude)
    z = cos(latitude) * cos(longitude)
  }
}
