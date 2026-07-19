import Combine
import CoreLocation
import SwiftUI
import UIKit

struct ActivityListItem: Identifiable, Equatable {
    let activity: MapActivity
    let distanceMeters: CLLocationDistance?

    var id: String { activity.id }
}

@MainActor
final class ActivitiesListViewModel: ObservableObject {
    @Published private(set) var items: [ActivityListItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: any MapActivityRepository
    private var activities: [MapActivity] = []

    init(repository: any MapActivityRepository) {
        self.repository = repository
    }

    func load(userCoordinate: CLLocationCoordinate2D?) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let center = userCoordinate.map(MapCoordinate.init) ?? .moscow
        let viewport = MapViewport(
            bounds: MapBounds(south: -85, west: -180, north: 85, east: 180),
            center: center,
            zoom: 0
        )

        do {
            activities = try await repository.activities(in: viewport, filters: MapFilterState()).activities
            updateDistances(from: userCoordinate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateDistances(from userCoordinate: CLLocationCoordinate2D?) {
        items = Self.makeItems(activities: activities, userCoordinate: userCoordinate)
    }

    static func makeItems(
        activities: [MapActivity],
        userCoordinate: CLLocationCoordinate2D?
    ) -> [ActivityListItem] {
        let origin = userCoordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        return activities
            .map { activity in
                let destination = CLLocation(
                    latitude: activity.coordinate.latitude,
                    longitude: activity.coordinate.longitude
                )
                return ActivityListItem(
                    activity: activity,
                    distanceMeters: origin?.distance(from: destination)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.distanceMeters, rhs.distanceMeters) {
                case let (left?, right?) where left != right:
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.activity.startsAt < rhs.activity.startsAt
                }
            }
    }
}

struct ActivitiesTabView: View {
    @ObservedObject var location: DeviceLocationProvider
    @StateObject private var model: ActivitiesListViewModel
    @State private var searchQuery = ""
    @State private var detailActivityID: UUID?
    private let detailRepository: any ActivityRepository

    init(
        mapRepository: any MapActivityRepository,
        detailRepository: any ActivityRepository,
        location: DeviceLocationProvider
    ) {
        self.location = location
        self.detailRepository = detailRepository
        _model = StateObject(wrappedValue: ActivitiesListViewModel(repository: mapRepository))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                        header
                        locationStatus
                        content
                    }
                    .frame(maxWidth: AppLayout.maxContentWidth, alignment: .leading)
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppLayout.bottomNavigationClearance)
                }
                .refreshable {
                    await model.load(userCoordinate: location.coordinate)
                }
            }
        }
        .task {
            if location.coordinate == nil {
                location.requestCurrentLocation()
            }
            await model.load(userCoordinate: location.coordinate)
        }
        .onChange(of: location.updateSequence) { _, _ in
            model.updateDistances(from: location.coordinate)
        }
        .sheet(isPresented: Binding(
            get: { detailActivityID != nil },
            set: { if !$0 { detailActivityID = nil } }
        )) {
            if let detailActivityID {
                ActivityDetailView(activityID: detailActivityID, repository: detailRepository)
            }
        }
    }

    private var filteredItems: [ActivityListItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.items }
        return model.items.filter {
            $0.activity.title.localizedCaseInsensitiveContains(query)
                || L10n.string($0.activity.category.titleKey).localizedCaseInsensitiveContains(query)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("activities.title")
                .font(AppTypography.screenTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text("activities.subtitle")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textSecondary)
                TextField("activities.search.placeholder", text: $searchQuery)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.search)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: AppLayout.minimumTouchTarget, height: AppLayout.minimumTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel("activities.search.clear")
                }
            }
            .padding(.leading, AppSpacing.md)
            .frame(minHeight: 52)
            .liquidGlassField(isInvalid: false, isFocused: !searchQuery.isEmpty)
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        if location.isRequesting && location.coordinate == nil {
            Label("activities.distance.locating", systemImage: "location.fill")
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColors.locationAccent)
                .padding(.horizontal, AppSpacing.sm)
        } else if location.coordinate == nil {
            GlassCard {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "location.slash.fill")
                        .foregroundStyle(AppColors.warning)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("activities.distance.unavailable.title")
                            .font(AppTypography.bodyMedium)
                        Text(location.errorMessage ?? L10n.string("activities.distance.unavailable.message"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: AppSpacing.xs)
                    Button(locationNeedsSettings ? L10n.string("map.location.permission.settings") : L10n.string("common.retry")) {
                        if locationNeedsSettings,
                           let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        } else {
                            location.requestCurrentLocation()
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: AppLayout.minimumTouchTarget)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                Text("activities.loading")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if let errorMessage = model.errorMessage, model.items.isEmpty {
            ContentUnavailableView {
                Label("activities.error.title", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("common.retry") {
                    Task { await model.load(userCoordinate: location.coordinate) }
                }
            }
        } else if filteredItems.isEmpty {
            ContentUnavailableView {
                Label(
                    LocalizedStringKey(searchQuery.isEmpty ? "activities.empty.title" : "activities.search.empty.title"),
                    systemImage: searchQuery.isEmpty ? "figure.walk.circle" : "magnifyingglass"
                )
            } description: {
                Text(LocalizedStringKey(searchQuery.isEmpty ? "activities.empty.message" : "activities.search.empty.message"))
            }
        } else {
            ForEach(filteredItems) { item in
                ActivityListCard(item: item) {
                    detailActivityID = UUID(uuidString: item.activity.id)
                }
            }
        }
    }

    private var locationNeedsSettings: Bool {
        location.authorizationStatus == .denied || location.authorizationStatus == .restricted
    }
}

private struct ActivityListCard: View {
    let item: ActivityListItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                Image(systemName: item.activity.category.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(item.activity.category.listTint, in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(item.activity.title)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(LocalizedStringKey(item.activity.category.titleKey))
                        .font(AppTypography.captionStrong)
                        .foregroundStyle(item.activity.category.listTint)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.md) { metadata }
                        VStack(alignment: .leading, spacing: AppSpacing.xs) { metadata }
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.textMuted)
                    .frame(minHeight: AppLayout.minimumTouchTarget)
            }
            .padding(AppSpacing.md)
            .glassSurface(.regular, cornerRadius: AppRadius.card)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("activities.open.hint")
    }

    private var participantsText: String {
        if let limit = item.activity.participantLimit {
            return "\(item.activity.participantCount)/\(limit)"
        }
        return String(item.activity.participantCount)
    }

    @ViewBuilder
    private var metadata: some View {
        Label(item.activity.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
        Label(participantsText, systemImage: "person.2.fill")
        Label(distanceText, systemImage: item.distanceMeters == nil ? "location.slash" : "location.fill")
            .foregroundStyle(item.distanceMeters == nil ? AppColors.textMuted : AppColors.locationAccent)
    }

    private var distanceText: String {
        guard let distanceMeters = item.distanceMeters else {
            return L10n.string("activities.distance.unavailable.short")
        }
        if distanceMeters < 1_000 {
            return Measurement(value: max(0, distanceMeters), unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
        }
        return AppFormatters.distance(kilometers: max(0, distanceMeters) / 1_000)
    }
}

private extension ActivityCategory {
    var listTint: Color {
        switch self {
        case .walking: .green
        case .sport: .red
        case .travel: .blue
        case .music: .purple
        case .games: .indigo
        case .food: .orange
        case .help: .teal
        case .education: .brown
        case .animals: .mint
        case .event: .pink
        case .other: .gray
        }
    }
}
