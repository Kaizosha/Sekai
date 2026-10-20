import CoreGraphics
import Foundation

@testable import SekaiKit

struct ReferenceGlobeVector: Equatable, Sendable {
  var x: Double
  var y: Double
  var z: Double

  init(_ coordinate: SekaiCoordinate, radius: Double = 1) {
    let latitude = coordinate.latitude * .pi / 180
    let longitude = coordinate.longitude * .pi / 180
    let latitudeRadius = cos(latitude) * radius
    x = latitudeRadius * sin(longitude)
    y = sin(latitude) * radius
    z = latitudeRadius * cos(longitude)
  }

  init(x: Double, y: Double, z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  var length: Double { sqrt(x * x + y * y + z * z) }

  func normalized() -> Self {
    let scale = 1 / max(length, .leastNonzeroMagnitude)
    return Self(x: x * scale, y: y * scale, z: z * scale)
  }

  func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z }

  func rotated(by quaternion: SekaiQuaternion) -> Self {
    let q = ReferenceGlobeVector(x: quaternion.x, y: quaternion.y, z: quaternion.z)
    let twiceCross = q.cross(self) * 2
    return self + twiceCross * quaternion.w + q.cross(twiceCross)
  }

  func cross(_ other: Self) -> Self {
    Self(
      x: y * other.z - z * other.y,
      y: z * other.x - x * other.z,
      z: x * other.y - y * other.x
    )
  }

  var coordinate: SekaiCoordinate {
    let value = normalized()
    return SekaiCoordinate(
      latitude: asin(min(max(value.y, -1), 1)) * 180 / .pi,
      longitude: atan2(value.x, value.z) * 180 / .pi
    )
  }

  static func + (left: Self, right: Self) -> Self {
    Self(x: left.x + right.x, y: left.y + right.y, z: left.z + right.z)
  }

  static func * (left: Self, right: Double) -> Self {
    Self(x: left.x * right, y: left.y * right, z: left.z * right)
  }

  static func slerp(_ start: Self, _ end: Self, progress: Double) -> Self {
    let a = start.normalized()
    let b = end.normalized()
    let progress = min(max(progress.isFinite ? progress : 0, 0), 1)
    let angle = acos(min(max(a.dot(b), -1), 1))
    guard angle > 0.000_001 else { return a }
    if .pi - angle < 0.000_001 {
      let reference =
        abs(a.y) < 0.9
        ? Self(x: 0, y: 1, z: 0)
        : Self(x: 1, y: 0, z: 0)
      let orthogonal = a.cross(reference).normalized()
      return (a * cos(.pi * progress) + orthogonal * sin(.pi * progress)).normalized()
    }
    let denominator = sin(angle)
    return
      (a * (sin((1 - progress) * angle) / denominator)
      + b * (sin(progress * angle) / denominator)).normalized()
  }
}

struct ReferenceGlobeProjection {
  let camera: SekaiCamera
  let orientation: SekaiQuaternion
  let size: CGSize

  func project(_ source: ReferenceGlobeVector) -> CGPoint? {
    let p = source.rotated(by: orientation)
    let radial = p.x * p.x + p.y * p.y
    if radial < 1, p.z < sqrt(max(0, 1 - radial)) - 0.0001 { return nil }
    let shortest = min(size.width, size.height)
    return CGPoint(
      x: size.width / 2 + (p.x * 0.8 * camera.zoom + camera.offsetX) * shortest / 2,
      y: size.height / 2 - (p.y * 0.8 * camera.zoom + camera.offsetY) * shortest / 2
    )
  }
}
