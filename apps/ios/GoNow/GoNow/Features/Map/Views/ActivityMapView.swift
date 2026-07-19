import CoreLocation
import SwiftUI
import UIKit

struct ActivityMapView: View {
    @ObservedObject var model: ActivityMapViewModel
    @ObservedObject var location: DeviceLocationProvider
    let activityRepository: any ActivityRepository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var styleLoader = MapStyleLoader()
    @State private var cameraCommand: MapLibreCameraCommand?
    @State private var shouldCenterWhenLocationArrives = false
    @State private var isLocationExplanationPresented = false
    @State private var mapLoadState: MapLibreLoadState = .loading
    @State private var detailActivityID: UUID?

    var body: some View {
        ZStack {
            mapSurface

            mapControls
            attribution

            if let selected = model.selectedActivity {
                ActivityMapCard(activity: selected) {
                    detailActivityID = UUID(uuidString: selected.id)
                } onClose: {
                    model.selectedActivity = nil
                }
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.bottom, 118)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            stateOverlay
        }
        .alert("map.location.permission.title", isPresented: $isLocationExplanationPresented) {
            if location.authorizationStatus == .notDetermined {
                Button("map.location.permission.allow") { requestLocationAndCenter() }
            } else if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                Button("map.location.permission.settings") { openApplicationSettings() }
            }
            Button("common.cancel", role: .cancel) { shouldCenterWhenLocationArrives = false }
        } message: {
            Text("map.location.permission.description")
        }
        .sheet(isPresented: $model.isFilterPresented) {
            MapFilterSheet(filters: model.filters, onApply: model.applyFilters)
        }
        .sheet(isPresented: Binding(
            get: { detailActivityID != nil },
            set: { if !$0 { detailActivityID = nil } }
        )) {
            if let detailActivityID {
                ActivityDetailView(activityID: detailActivityID, repository: activityRepository)
            }
        }
        .task {
            styleLoader.load()
            startLocationForMap()
        }
        .task(id: styleLoader.loadedDocumentID) {
            guard styleLoader.loadedDocumentID != nil else { return }
            guard mapLoadState == .loading else { return }
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, mapLoadState == .loading else { return }
            mapLoadState = .failed
        }
        .onDisappear { location.stopMonitoringLocation() }
        .onChange(of: location.updateSequence) { _, _ in
            guard shouldCenterWhenLocationArrives,
                  let coordinate = location.coordinate.map(MapCoordinate.init) else { return }
            shouldCenterWhenLocationArrives = false
            centerMap(on: coordinate)
        }
        .animation(reduceMotion ? nil : AppAnimation.standard, value: model.selectedActivity?.id)
    }

    @ViewBuilder
    private var mapSurface: some View {
        if case .loaded(let document) = styleLoader.state {
            MapLibreActivityMap(
                styleJSON: document.json,
                activities: model.visibleActivities,
                userCoordinate: location.coordinate.map(MapCoordinate.init),
                selectedActivityID: model.selectedActivity?.id,
                initialCamera: initialMapCamera,
                cameraCommand: cameraCommand,
                reduceMotion: reduceMotion,
                onLoadStateChange: { mapLoadState = $0 },
                onViewportIdle: { viewport, bearing, pitch in
                    model.mapBecameIdle(viewport: viewport, bearing: bearing, pitch: pitch)
                },
                onSelectActivity: model.selectActivity,
                onDeselectActivity: { model.selectedActivity = nil }
            )
            .id(document.id)
            .ignoresSafeArea()
            .accessibilityLabel("map.accessibility.label")
        } else {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
        }
    }

    private var initialMapCamera: PersistedMapCamera {
        guard let coordinate = location.coordinate.map(MapCoordinate.init) else {
            return model.initialCamera
        }
        return PersistedMapCamera(center: coordinate, zoom: 12.2, bearing: 0, pitch: 0)
    }

    private var mapControls: some View {
        VStack(spacing: AppSpacing.sm) {
            Button { model.isFilterPresented = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .mapControlSurface()
                    if model.filters.activeCount > 0 {
                        Text(model.filters.activeCount.formatted())
                            .font(.caption2.bold())
                            .foregroundStyle(AppColors.textOnAccent)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(AppColors.accentPrimary, in: Circle())
                            .offset(x: 2, y: -2)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityLabel("map.filters.title")
            .accessibilityValue(model.filters.activeCount.formatted())
            .buttonStyle(AppPressButtonStyle())

            Button { requestLocationAccessOrCenter() } label: {
                ZStack {
                    if location.isRequesting && location.coordinate == nil {
                        ProgressView()
                            .tint(AppColors.accentPrimary)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .mapControlSurface()
            }
            .accessibilityLabel("map.location.action")
            .buttonStyle(AppPressButtonStyle())
        }
        .padding(.trailing, AppLayout.horizontalInset)
        .padding(.top, 112)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var attribution: some View {
        HStack(spacing: 3) {
            Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                Text(verbatim: "© OpenStreetMap contributors")
            }
            Text(verbatim: "·")
            Link(destination: URL(string: "https://openfreemap.org")!) {
                Text(verbatim: "OpenFreeMap")
            }
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, 7)
        .frame(minHeight: AppLayout.minimumTouchTarget)
        .background(.regularMaterial, in: Capsule())
        .padding(.leading, AppLayout.horizontalInset)
        .padding(.bottom, 92)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "© OpenStreetMap contributors · OpenFreeMap"))
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch styleLoader.state {
        case .idle, .loading:
            ProgressView()
                .padding(AppSpacing.md)
                .glassSurface(.floating, cornerRadius: AppRadius.control)
                .accessibilityLabel("map.loading")
        case .failed:
            MapStatusPill(
                symbol: "wifi.exclamationmark",
                text: L10n.string("map.service.unavailable"),
                retry: retryMap
            )
        case .loaded:
            switch mapLoadState {
            case .loading:
                ProgressView()
                    .padding(AppSpacing.md)
                    .glassSurface(.floating, cornerRadius: AppRadius.control)
                    .accessibilityLabel("map.loading")
            case .failed:
                MapStatusPill(
                    symbol: "wifi.exclamationmark",
                    text: L10n.string("map.service.unavailable"),
                    retry: retryMap
                )
            case .loaded:
                activityStateOverlay
            }
        }
    }

    @ViewBuilder
    private var activityStateOverlay: some View {
        switch model.state {
        case .loading, .initial:
            ProgressView()
                .padding(AppSpacing.md)
                .glassSurface(.floating, cornerRadius: AppRadius.control)
        case .empty:
            EmptyView()
        case .failed(let message, let keepsExistingData):
            if keepsExistingData {
                VStack {
                    Spacer()
                    MapStatusPill(symbol: "wifi.exclamationmark", text: message, retry: model.reload)
                        .padding(.bottom, 118)
                }
            } else {
                MapStatusPill(symbol: "wifi.exclamationmark", text: message, retry: model.reload)
            }
        case .loaded:
            EmptyView()
        }
    }

    private func retryMap() {
        mapLoadState = .loading
        styleLoader.reload()
        model.reload()
    }

    private func startLocationForMap() {
        shouldCenterWhenLocationArrives = true
        if let coordinate = location.coordinate.map(MapCoordinate.init) {
            centerMap(on: coordinate)
        }
        location.startMonitoringLocation()
    }

    private func requestLocationAccessOrCenter() {
        shouldCenterWhenLocationArrives = true
        switch location.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            isLocationExplanationPresented = true
        case .authorizedWhenInUse, .authorizedAlways:
            if let coordinate = location.coordinate.map(MapCoordinate.init) {
                centerMap(on: coordinate)
            }
            location.startMonitoringLocation()
        @unknown default:
            isLocationExplanationPresented = true
        }
    }

    private func requestLocationAndCenter() {
        shouldCenterWhenLocationArrives = true
        if let coordinate = location.coordinate.map(MapCoordinate.init) {
            centerMap(on: coordinate)
        }
        location.requestCurrentLocation()
    }

    private func centerMap(on coordinate: MapCoordinate) {
        cameraCommand = MapLibreCameraCommand(coordinate: coordinate, zoom: 12.2)
    }

    private func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private extension View {
    func mapControlSurface() -> some View {
        frame(width: 50, height: 50)
            .background(.regularMaterial, in: Circle())
            .glassEffect(.regular, in: Circle())
            .overlay { Circle().strokeBorder(AppColors.glassBorder.opacity(0.72), lineWidth: 1) }
            .appShadow(.floating)
    }
}

private struct MapStatusPill: View {
    let symbol: String
    let text: String
    var retry: (() -> Void)?

    init(symbol: String, text: String, retry: (() -> Void)? = nil) {
        self.symbol = symbol
        self.text = text
        self.retry = retry
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: symbol)
            Text(text)
            if let retry {
                Button("common.retry", action: retry)
                    .fontWeight(.semibold)
                    .frame(minHeight: AppLayout.minimumTouchTarget)
            }
        }
        .font(AppTypography.captionStrong)
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: 48)
        .glassSurface(.floating, cornerRadius: AppRadius.control)
    }
}
