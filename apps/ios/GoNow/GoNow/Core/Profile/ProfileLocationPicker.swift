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
            errorMessage = "Разрешите доступ к геопозиции в настройках iPhone."
        @unknown default:
            errorMessage = "Не удалось определить доступ к геопозиции."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isRequesting = true
            manager.requestLocation()
        case .denied, .restricted:
            isRequesting = false
            errorMessage = "Разрешите доступ к геопозиции в настройках iPhone."
        case .notDetermined:
            break
        @unknown default:
            isRequesting = false
            errorMessage = "Не удалось определить доступ к геопозиции."
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
            label = pieces.isEmpty ? "Текущее местоположение" : pieces.joined(separator: ", ")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        errorMessage = "Не удалось определить геопозицию. Попробуйте ещё раз."
    }
}
