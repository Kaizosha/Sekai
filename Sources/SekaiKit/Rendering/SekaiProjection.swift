import CoreGraphics
import Foundation

@MainActor
final class SekaiRotationClock {
    private var phase = 0.0
    private var lastTimestamp = Date.timeIntervalSinceReferenceDate
    private var lastSpeed = 0.0

    func angle(at timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate, speed: Double) -> Double {
        let elapsed = min(max(timestamp - lastTimestamp, 0), 0.25)
        phase = (phase + elapsed * lastSpeed).truncatingRemainder(dividingBy: .pi * 2)
        lastTimestamp = timestamp
        lastSpeed = speed.isFinite ? speed : 0
        return phase
    }

    func reset() {
        phase = 0
        lastTimestamp = Date.timeIntervalSinceReferenceDate
        lastSpeed = 0
    }
}

struct SekaiProjectedPoint: Sendable {
    let point: CGPoint
    let depth: Double
}

struct SekaiProjectionContext: Sendable {
    let size: CGSize
    let camera: SekaiCamera
    let spinAngle: Double

    func project(_ coordinate: SekaiCoordinate, elevation: Double = 0) -> SekaiProjectedPoint? {
        project(SekaiVector3(coordinate, radius: 1 + elevation))
    }

    func project(_ source: SekaiVector3) -> SekaiProjectedPoint? {
        guard size.width > 0, size.height > 0 else { return nil }
        let spin = SekaiQuaternion.axisAngle(x: 0, y: 1, z: 0, radians: spinAngle)
        let position = source.rotated(by: spin).rotated(by: camera.orientation)
        guard position.z > 0 else { return nil }
        let aspect = max(size.width / size.height, 0.001)
        var scale = camera.zoom
        if camera.projection.fieldOfViewDegrees != 0 {
            let projectionScale = 1 / tan(camera.projection.fieldOfViewDegrees * .pi / 360)
            scale *= projectionScale / max(0.35, 3 - position.z)
        }
        let normalizedX = position.x * scale / aspect + camera.offsetX
        let normalizedY = position.y * scale + camera.offsetY
        guard abs(normalizedX) <= 1.08, abs(normalizedY) <= 1.08 else { return nil }
        return SekaiProjectedPoint(
            point: CGPoint(
                x: (normalizedX + 1) * size.width * 0.5,
                y: (1 - normalizedY) * size.height * 0.5
            ),
            depth: position.z
        )
    }

    func unproject(_ point: CGPoint) -> SekaiCoordinate? {
        guard size.width > 0, size.height > 0 else { return nil }
        let aspect = max(size.width / size.height, 0.001)
        let normalizedX = Double(point.x / size.width) * 2 - 1 - camera.offsetX
        let normalizedY = 1 - Double(point.y / size.height) * 2 - camera.offsetY
        let x: Double
        let y: Double
        let z: Double

        if camera.projection.fieldOfViewDegrees == 0 {
            x = normalizedX * aspect / max(camera.zoom, 0.0001)
            y = normalizedY / max(camera.zoom, 0.0001)
            let remaining = 1 - x * x - y * y
            guard remaining >= 0 else { return nil }
            z = sqrt(remaining)
        } else {
            let projectionScale = 1 / tan(camera.projection.fieldOfViewDegrees * .pi / 360)
            let base = max(camera.zoom * projectionScale, 0.0001)
            let projectedX = normalizedX * aspect / base
            let projectedY = normalizedY / base
            let radial = projectedX * projectedX + projectedY * projectedY
            let a = radial + 1
            let b = -6 * radial
            let c = 9 * radial - 1
            let discriminant = b * b - 4 * a * c
            guard discriminant >= 0 else { return nil }
            z = (-b + sqrt(discriminant)) / (2 * a)
            guard z > 0, z <= 1.000_001 else { return nil }
            x = projectedX * (3 - z)
            y = projectedY * (3 - z)
        }

        let cameraSpace = SekaiVector3(x: x, y: y, z: z).normalized()
        let spin = SekaiQuaternion.axisAngle(x: 0, y: 1, z: 0, radians: spinAngle)
        return cameraSpace.rotated(by: camera.orientation.inverse).rotated(by: spin.inverse).coordinate
    }
}

func sekaiDistance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let denominator = dx * dx + dy * dy
    guard denominator > 0 else { return hypot(point.x - start.x, point.y - start.y) }
    let progress = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / denominator, 0), 1)
    let closest = CGPoint(x: start.x + dx * progress, y: start.y + dy * progress)
    return hypot(point.x - closest.x, point.y - closest.y)
}
