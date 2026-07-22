@preconcurrency import CoreLocation
import Observation
import SekaiKit

@MainActor @Observable
public final class SekaiLocationProvider: NSObject, @MainActor CLLocationManagerDelegate {
    public private(set) var authorizationStatus: CLAuthorizationStatus
    public private(set) var coordinate: SekaiCoordinate?
    public private(set) var accuracy: CLLocationAccuracy?
    public private(set) var error: Error?

    private let manager: CLLocationManager

    public override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    public func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    #if os(tvOS)
    public func start() {}
    public func stop() {}
    #else
    public func start() { manager.startUpdatingLocation() }
    public func stop() { manager.stopUpdatingLocation() }
    #endif

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = SekaiCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        accuracy = location.horizontalAccuracy
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = error
    }

    public var annotation: SekaiAnnotation? {
        coordinate.map { SekaiAnnotation(id: "sekai.user-location", coordinate: $0, title: "Current Location") }
    }
}
