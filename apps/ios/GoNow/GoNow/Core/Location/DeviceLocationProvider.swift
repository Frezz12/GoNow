import Combine
import CoreLocation
import Foundation

/// Device location access for one-time profile selection and low-frequency map updates.
@MainActor
final class DeviceLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var locality: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequesting = false
    @Published private(set) var isResolvingLocality = false
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private var monitorsLocationChanges = false
    private var localityRequestID = UUID()

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
        locality = nil

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

    /// Starts low-frequency updates while the map is visible.
    /// A new city-sized movement refreshes the city label and weather request.
    func startMonitoringLocation() {
        monitorsLocationChanges = true
        errorMessage = nil
        locality = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isRequesting = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            isRequesting = false
            errorMessage = "Разрешите доступ к геопозиции в настройках iPhone."
        @unknown default:
            isRequesting = false
            errorMessage = "Не удалось определить доступ к геопозиции."
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
            errorMessage = "Разрешите доступ к геопозиции в настройках iPhone."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        isRequesting = false
        isResolvingLocality = true
        let requestID = UUID()
        localityRequestID = requestID

        Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            guard localityRequestID == requestID else { return }
            locality = placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.administrativeArea
            isResolvingLocality = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        isResolvingLocality = false
        errorMessage = "Не удалось определить геопозицию. Попробуйте ещё раз."
    }
}
