import Combine
import CoreLocation
import Foundation

/// A single-shot device location request for features that need the user's current area.
@MainActor
final class DeviceLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequesting = false
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() {
        errorMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isRequesting = true
            manager.requestLocation()
        case .denied, .restricted:
            isRequesting = false
            errorMessage = "Разрешите доступ к геопозиции в настройках iPhone."
        @unknown default:
            isRequesting = false
            errorMessage = "Не удалось определить доступ к геопозиции."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            requestCurrentLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            isRequesting = false
            errorMessage = "Разрешите доступ к геопозиции в настройках iPhone."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
        isRequesting = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        errorMessage = "Не удалось определить геопозицию. Попробуйте ещё раз."
    }
}
