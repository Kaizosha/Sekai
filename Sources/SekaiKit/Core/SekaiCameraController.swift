import Foundation
import Observation

/// An observable camera owner with cancellable, quaternion-safe flight animations.
@MainActor @Observable
public final class SekaiCameraController {
    public var camera: SekaiCamera
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var transitionID: UUID?

    public init(camera: SekaiCamera = .standard) {
        self.camera = camera
    }

    public func stopAnimation() {
        transitionTask?.cancel()
        transitionTask = nil
        transitionID = nil
    }

    public func fly(
        to destination: SekaiCamera,
        duration: TimeInterval = 0.8
    ) {
        stopAnimation()
        let start = camera
        let safeDuration = max(duration, 0)
        guard safeDuration > 0 else {
            camera = destination
            return
        }
        let identifier = UUID()
        transitionID = identifier
        transitionTask = Task { @MainActor [weak self] in
            let startTime = Date.timeIntervalSinceReferenceDate
            while !Task.isCancelled {
                let elapsed = Date.timeIntervalSinceReferenceDate - startTime
                let linear = min(max(elapsed / safeDuration, 0), 1)
                let eased = linear * linear * (3 - 2 * linear)
                self?.camera = start.interpolated(to: destination, progress: eased)
                if linear >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            if !Task.isCancelled { self?.camera = destination }
            if self?.transitionID == identifier {
                self?.transitionTask = nil
                self?.transitionID = nil
            }
        }
    }

    public func focus(
        on coordinate: SekaiCoordinate,
        zoom: Double? = nil,
        duration: TimeInterval = 0.8
    ) {
        var destination = camera.focused(on: coordinate)
        if let zoom { destination.zoom = zoom }
        fly(to: destination, duration: duration)
    }

    public func fit(
        _ feature: SekaiFeature,
        padding: Double = 0.12,
        limits: SekaiCameraBounds = .standard,
        duration: TimeInterval = 0.8
    ) {
        var destination = camera
        destination.fit(feature, padding: padding, limits: limits)
        fly(to: destination, duration: duration)
    }
}
