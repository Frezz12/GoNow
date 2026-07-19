import Combine
@preconcurrency import CoreLocation
import Foundation

/// Device location access for one-time profile selection and live map updates.
@MainActor
final class DeviceLocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var weatherCoordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequesting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var updateSequence = 0

    private let manager = CLLocationManager()
    private var monitorsLocationChanges = false
    private var lastWeatherLocation: CLLocation?
    private var requestTimeoutTask: Task<Void, Never>?
    private let weatherRefreshDistance: CLLocationDistance = 1_000

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
    }

    func requestCurrentLocation() {
        monitorsLocationChanges = false
        manager.stopUpdatingLocation()
        requestTimeoutTask?.cancel()
        errorMessage = nil
        configureForPreciseOneShot()

        switch manager.authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if coordinate == nil, let cachedLocation = manager.location {
                accept(cachedLocation)
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

    /// Starts precise updates while the map is visible. Weather updates remain
    /// coalesced to city-sized movements through `weatherCoordinate`.
    func startMonitoringLocation() {
        monitorsLocationChanges = true
        requestTimeoutTask?.cancel()
        errorMessage = nil
        configureForEfficientMonitoring()

        switch manager.authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if coordinate == nil, let cachedLocation = manager.location {
                accept(cachedLocation)
            }
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
        accept(location)
    }

    private func accept(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        requestTimeoutTask?.cancel()
        coordinate = location.coordinate
        updateSequence &+= 1
        if lastWeatherLocation.map({ location.distance(from: $0) >= weatherRefreshDistance }) ?? true {
            lastWeatherLocation = location
            weatherCoordinate = location.coordinate
        }
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

    private func configureForPreciseOneShot() {
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    private func configureForEfficientMonitoring() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }
}
