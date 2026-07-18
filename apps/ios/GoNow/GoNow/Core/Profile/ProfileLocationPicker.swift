import CoreLocation
import Combine
import Foundation

@MainActor
final class ProfileLocationPicker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRequesting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var label: String?

    private let manager = CLLocationManager()

    override init() {
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
            errorMessage = L10n.string("location.permission.settings")
        @unknown default:
            errorMessage = L10n.string("location.permission.unknown")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isRequesting = true
            manager.requestLocation()
        case .denied, .restricted:
            isRequesting = false
            errorMessage = L10n.string("location.permission.settings")
        case .notDetermined:
            break
        @unknown default:
            isRequesting = false
            errorMessage = L10n.string("location.permission.unknown")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        isRequesting = false

        Task {
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
            let placemark = placemarks?.first
            let pieces = [placemark?.locality, placemark?.administrativeArea].compactMap { $0 }
            label = pieces.isEmpty ? L10n.string("location.current") : pieces.joined(separator: ", ")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        errorMessage = L10n.string("location.resolve.error")
    }
}
