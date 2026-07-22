import CoreGraphics
import Foundation

public enum SekaiProjectionMode: Codable, Equatable, Sendable {
    case orthographic
    case perspective(fieldOfViewDegrees: Double)

    var fieldOfViewDegrees: Double {
        switch self {
        case .orthographic: 0
        case let .perspective(value): min(max(value, 15), 80)
        }
    }
}

public struct SekaiCameraBounds: Codable, Equatable, Sendable {
    public var minimumZoom: Double
    public var maximumZoom: Double

    public init(minimumZoom: Double = 0.5, maximumZoom: Double = 8) {
        self.minimumZoom = max(0.05, minimumZoom)
        self.maximumZoom = max(self.minimumZoom, maximumZoom)
    }

    public static let standard = Self()
}

/// Camera state shared by rendering, gestures, picking, and anchored overlays.
public struct SekaiCamera: Codable, Equatable, Sendable {
    public var orientation: SekaiQuaternion
    public var zoom: Double
    public var projection: SekaiProjectionMode
    public var offsetX: Double
    public var offsetY: Double

    public init(
        orientation: SekaiQuaternion = .identity,
        zoom: Double = 1,
        projection: SekaiProjectionMode = .orthographic,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) {
        self.orientation = orientation
        self.zoom = zoom.isFinite ? zoom : 1
        self.projection = projection
        self.offsetX = offsetX.isFinite ? offsetX : 0
        self.offsetY = offsetY.isFinite ? offsetY : 0
    }

    public static let standard = Self(
        orientation: .lookingAt(SekaiCoordinate(latitude: 12, longitude: 10))
    )

    public mutating func focus(on coordinate: SekaiCoordinate) {
        orientation = .lookingAt(coordinate)
    }

    public func focused(on coordinate: SekaiCoordinate) -> Self {
        var result = self
        result.focus(on: coordinate)
        return result
    }

    public mutating func fit(
        _ bounds: SekaiCoordinateBounds,
        padding: Double = 0.12,
        limits: SekaiCameraBounds = .standard
    ) {
        let west = bounds.west
        let unwrappedEast = bounds.east < west ? bounds.east + 360 : bounds.east
        let longitudeSpan = min(max(unwrappedEast - west, 0), 360)
        let latitudeSpan = min(max(bounds.north - bounds.south, 0), 180)
        let center = SekaiCoordinate(
            latitude: (bounds.south + bounds.north) * 0.5,
            longitude: west + longitudeSpan * 0.5
        )
        focus(on: center)
        let correctedLongitudeSpan = longitudeSpan * max(cos(center.latitude * .pi / 180), 0.2)
        let angularRadius = min(max(latitudeSpan, correctedLongitudeSpan) * .pi / 360, .pi / 2)
        let projectedRadius = max(sin(angularRadius), 0.035)
        zoom = (1 - min(max(padding, 0), 0.8)) / projectedRadius
        offsetX = 0
        offsetY = 0
        clamp(to: limits)
    }

    public mutating func fit(
        _ feature: SekaiFeature,
        padding: Double = 0.12,
        limits: SekaiCameraBounds = .standard
    ) {
        fit(feature.bounds, padding: padding, limits: limits)
    }

    public func fitted(
        to bounds: SekaiCoordinateBounds,
        padding: Double = 0.12,
        limits: SekaiCameraBounds = .standard
    ) -> Self {
        var result = self
        result.fit(bounds, padding: padding, limits: limits)
        return result
    }

    public func interpolated(to destination: Self, progress: Double) -> Self {
        let t = min(max(progress.isFinite ? progress : 0, 0), 1)
        let startZoom = max(zoom, 0.0001)
        let endZoom = max(destination.zoom, 0.0001)
        return Self(
            orientation: .slerp(orientation, destination.orientation, progress: t),
            zoom: exp(log(startZoom) + (log(endZoom) - log(startZoom)) * t),
            projection: t < 0.5 ? projection : destination.projection,
            offsetX: offsetX + (destination.offsetX - offsetX) * t,
            offsetY: offsetY + (destination.offsetY - offsetY) * t
        )
    }

    public mutating func clamp(to bounds: SekaiCameraBounds) {
        zoom = min(max(zoom, bounds.minimumZoom), bounds.maximumZoom)
    }
}

public struct SekaiInteractionOptions: Codable, Equatable, Sendable {
    public var allowsRotation: Bool
    public var allowsZoom: Bool
    public var allowsSelection: Bool
    public var allowsAnnotationDragging: Bool
    public var inertia: Double
    public var doubleTapZoom: Double
    public var autoRotationSpeed: Double
    public var stopsAutoRotationOnInteraction: Bool
    public var cameraBounds: SekaiCameraBounds

    public init(
        allowsRotation: Bool = true,
        allowsZoom: Bool = true,
        allowsSelection: Bool = true,
        allowsAnnotationDragging: Bool = false,
        inertia: Double = 0.88,
        doubleTapZoom: Double = 1.6,
        autoRotationSpeed: Double = 0,
        stopsAutoRotationOnInteraction: Bool = false,
        cameraBounds: SekaiCameraBounds = .standard
    ) {
        self.allowsRotation = allowsRotation
        self.allowsZoom = allowsZoom
        self.allowsSelection = allowsSelection
        self.allowsAnnotationDragging = allowsAnnotationDragging
        self.inertia = inertia
        self.doubleTapZoom = doubleTapZoom
        self.autoRotationSpeed = autoRotationSpeed
        self.stopsAutoRotationOnInteraction = stopsAutoRotationOnInteraction
        self.cameraBounds = cameraBounds
    }

    public static let standard = Self()
}

public enum SekaiPerformancePolicy: Codable, Equatable, Sendable {
    case adaptive(minimumFramesPerSecond: Int = 60)
    case exact
    case batterySaver
}

public struct SekaiRenderMetrics: Codable, Equatable, Sendable {
    public var logicalParticleCount: Int
    public var requestedParticleCount: Int
    public var renderedParticleCount: Int
    public var culledParticleCount: Int
    public var framesPerSecond: Double
    public var frameTimeMilliseconds: Double
    public var renderScale: Double
    public var levelOfDetail: Int
    public var policy: SekaiPerformancePolicy

    public init(
        logicalParticleCount: Int = 0,
        requestedParticleCount: Int = 0,
        renderedParticleCount: Int = 0,
        culledParticleCount: Int = 0,
        framesPerSecond: Double = 0,
        frameTimeMilliseconds: Double = 0,
        renderScale: Double = 1,
        levelOfDetail: Int = 0,
        policy: SekaiPerformancePolicy = .adaptive()
    ) {
        self.logicalParticleCount = logicalParticleCount
        self.requestedParticleCount = requestedParticleCount
        self.renderedParticleCount = renderedParticleCount
        self.culledParticleCount = culledParticleCount
        self.framesPerSecond = framesPerSecond
        self.frameTimeMilliseconds = frameTimeMilliseconds
        self.renderScale = renderScale
        self.levelOfDetail = levelOfDetail
        self.policy = policy
    }
}
