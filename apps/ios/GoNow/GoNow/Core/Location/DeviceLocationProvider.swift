import Combine
import CoreLocation
import Foundation

/// Device location access for one-time profile selection and low-frequency map updates.
@MainActor
final class DeviceLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequesting = false
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private var monitorsLocationChanges = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 1_000
    }

    func requestCurrentLocation() {
        monitorsLocationChanges = false
        manager.stopUpdatingLocation()
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
            errorMessage = L10n.string("location.permission.settings")
        @unknown default:
            isRequesting = false
            errorMessage = L10n.string("location.permission.unknown")
        }
    }

    /// Starts low-frequency updates while the map is visible.
    /// A new city-sized movement refreshes the city label and weather request.
    func startMonitoringLocation() {
        monitorsLocationChanges = true
        errorMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isRequesting = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            isRequesting = false
            errorMessage = L10n.string("location.permission.settings")
        @unknown default:
            isRequesting = false
            errorMessage = L10n.string("location.permission.unknown")
        }
    }

    func stopMonitoringLocation() {
        guard monitorsLocationChanges else { return }
        manager.stopUpdatingLocation()
        monitorsLocationChanges = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            if monitorsLocationChanges {
                isRequesting = true
                manager.startUpdatingLocation()
            } else {
                requestCurrentLocation()
            }
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            isRequesting = false
            errorMessage = L10n.string("location.permission.settings")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        isRequesting = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        errorMessage = L10n.string("location.resolve.error")
    }
}
