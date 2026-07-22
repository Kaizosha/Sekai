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

/// Geographic bounds that can cross the antimeridian.
public struct SekaiCoordinateBounds: Codable, Equatable, Sendable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = min(max(south, -90), 90)
        self.west = SekaiCoordinate.normalizedLongitude(west)
        self.north = min(max(north, -90), 90)
        self.east = SekaiCoordinate.normalizedLongitude(east)
    }

    public func contains(_ coordinate: SekaiCoordinate) -> Bool {
        guard coordinate.latitude >= south, coordinate.latitude <= north else { return false }
        if west <= east {
            return coordinate.longitude >= west && coordinate.longitude <= east
        }
        return coordinate.longitude >= west || coordinate.longitude <= east
    }

    public static let world = Self(south: -90, west: -180, north: 90, east: 180)
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

    private init(uncheckedX x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

struct SekaiVector3: Equatable, Sendable {
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
        let q = SekaiVector3(x: quaternion.x, y: quaternion.y, z: quaternion.z)
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

    static func + (left: Self, right: Self) -> Self {
        Self(x: left.x + right.x, y: left.y + right.y, z: left.z + right.z)
    }

    static func * (left: Self, right: Double) -> Self {
        Self(x: left.x * right, y: left.y * right, z: left.z * right)
    }

    static func slerp(_ start: Self, _ end: Self, progress: Double) -> Self {
        let a = start.normalized()
        let b = end.normalized()
        let angle = acos(min(max(a.dot(b), -1), 1))
        guard angle > 0.000_001 else { return a }
        let denominator = sin(angle)
        return (a * (sin((1 - progress) * angle) / denominator)
            + b * (sin(progress * angle) / denominator)).normalized()
    }
}
