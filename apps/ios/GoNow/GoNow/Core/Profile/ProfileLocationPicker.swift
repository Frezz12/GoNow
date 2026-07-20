import Combine
import Foundation
@preconcurrency import CoreLocation
import MapKit

@MainActor
final class ProfileLocationPicker: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
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
            guard let request = MKReverseGeocodingRequest(location: location) else {
                label = L10n.string("location.current")
                return
            }
            request.preferredLocale = .autoupdatingCurrent
            let representation = try? await request.mapItems.first?.addressRepresentations
            label = representation?.cityWithContext
                ?? representation?.regionName
                ?? L10n.string("location.current")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        errorMessage = L10n.string("location.resolve.error")
    }
}
