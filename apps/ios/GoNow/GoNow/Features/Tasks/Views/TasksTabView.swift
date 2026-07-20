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
    private var loadGeneration = 0

    init(repository: any MapActivityRepository) {
        self.repository = repository
    }

    func load(
        userCoordinate: CLLocationCoordinate2D?,
        filters: MapFilterState = MapFilterState()
    ) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil

        let center = userCoordinate.map(MapCoordinate.init) ?? .moscow
        let viewport = MapViewport(
            bounds: MapBounds(south: -85, west: -180, north: 85, east: 180),
            center: center,
            zoom: 0
        )

        do {
            let page = try await repository.activities(in: viewport, filters: filters)
            guard generation == loadGeneration else { return }
            activities = page.activities
            updateDistances(from: userCoordinate)
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == loadGeneration { isLoading = false }
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

@MainActor
final class ManagedActivitiesViewModel: ObservableObject {
    @Published private(set) var created: [GoNowActivity] = []
    @Published private(set) var participating: [GoNowActivity] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: any ActivityRepository

    init(repository: any ActivityRepository) {
        self.repository = repository
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let createdRequest = repository.ownedActivities()
            async let participatingRequest = repository.participatingActivities()
            let (created, participating) = try await (createdRequest, participatingRequest)
            self.created = Self.sorted(created)
            self.participating = Self.sorted(participating)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func sorted(_ activities: [GoNowActivity]) -> [GoNowActivity] {
        activities.sorted { lhs, rhs in
            let leftFinished = lhs.status == .completed || lhs.status == .cancelled || lhs.status == .expired
            let rightFinished = rhs.status == .completed || rhs.status == .cancelled || rhs.status == .expired
            if leftFinished != rightFinished { return !leftFinished }
            return leftFinished ? lhs.startsAt > rhs.startsAt : lhs.startsAt < rhs.startsAt
        }
    }
}

private enum ActivitiesSection: String, CaseIterable, Identifiable {
    case created
    case participating
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .created: "Мои"
        case .participating: "Участвую"
        case .discover: "Найти"
        }
    }
}

private struct ActivityChatTarget: Identifiable, Hashable {
    let id: UUID
    let title: String
}

struct ActivitiesTabView: View {
    @ObservedObject var location: DeviceLocationProvider
    @StateObject private var model: ActivitiesListViewModel
    @StateObject private var managedModel: ManagedActivitiesViewModel
    @State private var section: ActivitiesSection = .created
    @State private var searchQuery = ""
    @State private var filters = MapFilterState()
    @State private var isFiltersPresented = false
    @State private var detailActivityID: UUID?
    @State private var chatTarget: ActivityChatTarget?
    private let detailRepository: any ActivityRepository

    init(
        mapRepository: any MapActivityRepository,
        detailRepository: any ActivityRepository,
        location: DeviceLocationProvider
    ) {
        self.location = location
        self.detailRepository = detailRepository
        _model = StateObject(wrappedValue: ActivitiesListViewModel(repository: mapRepository))
        _managedModel = StateObject(wrappedValue: ManagedActivitiesViewModel(repository: detailRepository))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                        header
                        if section == .discover {
                            discoveryControls
                            locationStatus
                        }
                        content
                    }
                    .frame(maxWidth: AppLayout.maxContentWidth, alignment: .leading)
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppLayout.bottomNavigationClearance)
                }
                .refreshable {
                    await reloadSelectedSection()
                }
            }
            .navigationDestination(item: $chatTarget) { target in
                ChatConversationView(conversationID: target.id, title: target.title)
            }
        }
        .task {
            if location.coordinate == nil {
                location.requestCurrentLocation()
            }
            await managedModel.load()
            await model.load(userCoordinate: location.coordinate, filters: filters)
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
        .sheet(isPresented: $isFiltersPresented) {
            MapFilterSheet(filters: filters) { newFilters in
                filters = newFilters
                isFiltersPresented = false
                Task { await model.load(userCoordinate: location.coordinate, filters: newFilters) }
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

            Picker("Раздел активностей", selection: $section) {
                ForEach(ActivitiesSection.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Раздел активностей")
        }
    }

    private var discoveryControls: some View {
        HStack(spacing: AppSpacing.sm) {
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

            Button { isFiltersPresented = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: filters.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(filters.isEmpty ? AppColors.textPrimary : GoNowTheme.primary)
                        .frame(width: 52, height: 52)
                        .glassSurface(.regular, cornerRadius: 26)
                    if filters.activeCount > 0 {
                        Text("\(filters.activeCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(AppColors.error, in: Circle())
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(AppPressButtonStyle())
            .accessibilityLabel("Фильтры активностей")
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
        switch section {
        case .created:
            managedContent(
                activities: managedModel.created,
                emptyTitle: "Вы ещё не создавали активности",
                emptyMessage: "Созданные активности, включая завершённые, будут храниться здесь."
            )
        case .participating:
            managedContent(
                activities: managedModel.participating,
                emptyTitle: "Нет активностей с вашим участием",
                emptyMessage: "Найдите подходящую активность и присоединитесь — после принятия здесь появится доступ к чату."
            )
        case .discover:
            discoveryContent
        }
    }

    @ViewBuilder
    private func managedContent(
        activities: [GoNowActivity],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        if managedModel.isLoading && activities.isEmpty {
            loadingView
        } else if let errorMessage = managedModel.errorMessage, activities.isEmpty {
            errorView(errorMessage) { await managedModel.load() }
        } else if activities.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "figure.walk.circle")
            } description: {
                Text(emptyMessage)
            } actions: {
                Button("Найти активности") { section = .discover }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
            }
        } else {
            ForEach(activities) { activity in
                ManagedActivityCard(
                    activity: activity,
                    distanceMeters: distance(to: activity),
                    open: { detailActivityID = activity.id },
                    openChat: activity.chatConversationID.map { conversationID in
                        { chatTarget = ActivityChatTarget(id: conversationID, title: activity.title) }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var discoveryContent: some View {
        if model.isLoading && model.items.isEmpty {
            loadingView
        } else if let errorMessage = model.errorMessage, model.items.isEmpty {
            errorView(errorMessage) {
                await model.load(userCoordinate: location.coordinate, filters: filters)
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

    private var loadingView: some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView()
            Text("activities.loading")
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func errorView(
        _ message: String,
        retry: @escaping @MainActor () async -> Void
    ) -> some View {
        ContentUnavailableView {
            Label("activities.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("common.retry") { Task { await retry() } }
        }
    }

    private func distance(to activity: GoNowActivity) -> CLLocationDistance? {
        guard let coordinate = location.coordinate else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(
                latitude: activity.location.coordinate.latitude,
                longitude: activity.location.coordinate.longitude
            ))
    }

    private func reloadSelectedSection() async {
        switch section {
        case .created, .participating:
            await managedModel.load()
        case .discover:
            await model.load(userCoordinate: location.coordinate, filters: filters)
        }
    }

    private var locationNeedsSettings: Bool {
        location.authorizationStatus == .denied || location.authorizationStatus == .restricted
    }
}

private struct ManagedActivityCard: View {
    let activity: GoNowActivity
    let distanceMeters: CLLocationDistance?
    let open: () -> Void
    let openChat: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Button(action: open) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    Image(systemName: activity.category.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(activity.category.listTint, in: Circle())

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(activity.title)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        HStack(spacing: AppSpacing.xs) {
                            Text(LocalizedStringKey(activity.category.titleKey))
                                .foregroundStyle(activity.category.listTint)
                            Text("•")
                            Text(LocalizedStringKey(activity.status.titleKey))
                                .foregroundStyle(statusColor)
                        }
                        .font(AppTypography.captionStrong)
                        Label(activity.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        Label(distanceText, systemImage: distanceMeters == nil ? "location.slash" : "location.fill")
                            .foregroundStyle(distanceMeters == nil ? AppColors.textMuted : AppColors.locationAccent)
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.textMuted)
                        .frame(minHeight: AppLayout.minimumTouchTarget)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let openChat {
                Divider().opacity(0.5)
                Button(action: openChat) {
                    Label("Открыть чат активности", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(AppTypography.bodyMedium)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
                }
                .buttonStyle(GlassInlineButtonStyle())
            }
        }
        .padding(AppSpacing.md)
        .glassSurface(.regular, cornerRadius: AppRadius.card)
    }

    private var statusColor: Color {
        switch activity.status {
        case .completed: AppColors.success
        case .cancelled, .blocked: AppColors.error
        case .expired, .hidden: AppColors.textMuted
        default: GoNowTheme.primary
        }
    }

    private var distanceText: String {
        guard let distanceMeters else { return L10n.string("activities.distance.unavailable.short") }
        if distanceMeters < 1_000 {
            return Measurement(value: max(0, distanceMeters), unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
        }
        return AppFormatters.distance(kilometers: max(0, distanceMeters) / 1_000)
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
