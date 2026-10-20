import Foundation
import Testing

@testable import SekaiKit

struct SekaiValueTests {
  @Test func coordinatesNormalizeAtTheRenderBoundary() {
    let camera = SekaiCamera(
      orientation: .init(x: .nan, y: 0, z: 0, w: 0), zoom: .infinity, offsetX: .nan, offsetY: 100
    ).normalized
    #expect(camera.orientation == .identity)
    #expect(camera.zoom == 1)
    #expect(camera.offsetX == 0)
    #expect(camera.offsetY == 4)
    #expect(SekaiCoordinate(latitude: 120, longitude: 540) == .init(latitude: 90, longitude: 180))
  }

  @Test func quaternionCompositionAndInterpolationStayNormalized() {
    var q = SekaiQuaternion.identity
    for _ in 0..<10_000 { q = .axisAngle(x: 0.2, y: 1, z: 0, radians: 0.001) * q }
    #expect(abs(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w - 1) < 0.000_001)
    let halfway = SekaiQuaternion.slerp(
      .identity, .axisAngle(x: 0, y: 1, z: 0, radians: .pi), progress: 0.5)
    let point = ReferenceGlobeVector(.init(latitude: 0, longitude: 0)).rotated(by: halfway)
    #expect(abs(point.x - 1) < 0.000_001)
    #expect(abs(point.z) < 0.000_001)
  }

  @Test func cardinalProjectionAndFocusUseTheSameCoordinateConvention() throws {
    let projection = ReferenceGlobeProjection(
      camera: .init(), orientation: .identity, size: .init(width: 200, height: 200))
    let front = try #require(
      projection.project(ReferenceGlobeVector(.init(latitude: 0, longitude: 0))))
    #expect(abs(front.x - 100) < 0.001 && abs(front.y - 100) < 0.001)
    #expect(projection.project(ReferenceGlobeVector(.init(latitude: 0, longitude: 180))) == nil)
    let north = try #require(
      projection.project(ReferenceGlobeVector(.init(latitude: 90, longitude: 0))))
    #expect(abs(north.y - 20) < 0.001)
    let coordinate = SekaiCoordinate(latitude: 35, longitude: 139)
    let focused = ReferenceGlobeVector(coordinate).rotated(
      by: SekaiCamera.standard.focused(on: coordinate).orientation)
    #expect(abs(focused.z - 1) < 0.000_001)
  }

  @Test func pausedTimeAndSpeedChangesNeverJumpTheAccumulatedPhase() {
    var clock = SekaiMotion()
    clock.update(at: 0, speed: 0.1)
    clock.update(at: 5, speed: 0)
    #expect(abs(clock.angle - 0.5) < 0.000_001)
    clock.update(at: 500, speed: 0.2)
    #expect(abs(clock.angle - 0.5) < 0.000_001)
    clock.update(at: 502, speed: 0.4)
    #expect(abs(clock.angle - 0.9) < 0.000_001)
    #expect(abs(clock.consume(at: 503) - 1.3) < 0.000_001)
    #expect(clock.angle == 0)
  }

  @Test func antipodalArcsHaveADeterministicFiniteGreatCircle() {
    let a = ReferenceGlobeVector(.init(latitude: 0, longitude: 0))
    let b = ReferenceGlobeVector(.init(latitude: 0, longitude: 180))
    let halfway = ReferenceGlobeVector.slerp(a, b, progress: 0.5)
    #expect(halfway.x.isFinite && halfway.y.isFinite && halfway.z.isFinite)
    #expect(abs(halfway.length - 1) < 0.000_001)
    #expect(abs(halfway.dot(a)) < 0.000_001)
  }

  @Test func cameraAndStyleRemainCodableValues() throws {
    let style = SekaiStyle(appearance: .dark, sampleCount: 12_000, opacity: 0)
    let camera = SekaiCamera.standard.focused(on: .init(latitude: 89, longitude: -179))
    #expect(try JSONDecoder().decode(SekaiStyle.self, from: JSONEncoder().encode(style)) == style)
    #expect(
      try JSONDecoder().decode(SekaiCamera.self, from: JSONEncoder().encode(camera)) == camera)
  }
}
