import Combine
@preconcurrency import CoreLocation
import Foundation

/// Device location access for one-time profile selection and low-frequency map updates.
@MainActor
final class DeviceLocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequesting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var updateSequence = 0

    private let manager = CLLocationManager()
    private var monitorsLocationChanges = false
    private var requestTimeoutTask: Task<Void, Never>?

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
        requestTimeoutTask?.cancel()
        errorMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if coordinate == nil, let cachedLocation = manager.location {
                coordinate = cachedLocation.coordinate
                updateSequence &+= 1
            }
            beginOneShotRequest()
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
        requestTimeoutTask?.cancel()
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
        requestTimeoutTask?.cancel()
        requestTimeoutTask = nil
        manager.stopUpdatingLocation()
        monitorsLocationChanges = false
        isRequesting = false
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
        requestTimeoutTask?.cancel()
        coordinate = location.coordinate
        updateSequence &+= 1
        isRequesting = false
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        requestTimeoutTask?.cancel()
        isRequesting = false
        errorMessage = L10n.string("location.resolve.error")
    }

    private func beginOneShotRequest() {
        isRequesting = true
        requestTimeoutTask?.cancel()
        requestTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.isRequesting else { return }
            self.manager.stopUpdatingLocation()
            self.isRequesting = false
            self.errorMessage = L10n.string("location.resolve.error")
        }
    }
}
