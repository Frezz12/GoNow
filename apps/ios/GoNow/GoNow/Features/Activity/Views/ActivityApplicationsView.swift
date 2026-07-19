import SwiftUI

struct ActivityApplicationsView: View {
    @StateObject private var model: ActivityApplicationsViewModel

    init(activityID: UUID, repository: any ActivityRepository) {
        _model = StateObject(wrappedValue: ActivityApplicationsViewModel(activityID: activityID, repository: repository))
    }

    var body: some View {
        Group {
            if model.isLoading && model.applications.isEmpty {
                ProgressView("activity.applications.loading")
            } else if model.applications.isEmpty {
                ContentUnavailableView(
                    "activity.applications.empty.title",
                    systemImage: "person.2",
                    description: Text("activity.applications.empty.message")
                )
            } else {
                List(model.applications) { application in
                    applicationCard(application)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("activity.applications.title")
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func applicationCard(_ application: ActivityApplication) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                ProfileAvatar(initials: initials(application.applicant.displayName), size: 46, imageData: Data())
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.applicant.displayName).font(AppTypography.cardTitle)
                    Label(application.applicant.rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text(LocalizedStringKey(application.status.titleKey))
                    .font(AppTypography.badge)
            }
            if let message = application.message, !message.isEmpty { Text(message).font(AppTypography.body) }
            ForEach(application.answers, id: \.questionID) { answer in
                Text(answer.value).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
            if application.status == .pending {
                HStack(spacing: AppSpacing.sm) {
                    Button("activity.application.reject", role: .destructive) {
                        Task { await model.decide(.rejected, application: application) }
                    }
                    .buttonStyle(.bordered)
                    Button("activity.application.accept") {
                        Task { await model.decide(.accepted, application: application) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .disabled(model.processingIDs.contains(application.id))
            }
        }
        .padding(AppSpacing.md)
        .glassSurface(.regular, cornerRadius: AppRadius.card)
        .accessibilityElement(children: .contain)
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct OwnedActivitiesView: View {
    @StateObject private var model: OwnedActivitiesViewModel
    private let repository: any ActivityRepository

    init(repository: any ActivityRepository) {
        self.repository = repository
        _model = StateObject(wrappedValue: OwnedActivitiesViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if model.isLoading && model.activities.isEmpty {
                ProgressView("activity.loading")
            } else if model.activities.isEmpty {
                ContentUnavailableView(
                    "activity.mine.empty.title",
                    systemImage: "calendar.badge.plus",
                    description: Text("activity.mine.empty.message")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.sm) {
                        ForEach(model.activities) { activity in
                            NavigationLink(value: activity.id) {
                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: activity.category.symbol)
                                        .foregroundStyle(AppColors.textOnAccent)
                                        .frame(width: 44, height: 44)
                                        .background(AppGradients.brand, in: Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(activity.title).font(AppTypography.cardTitle)
                                        Text(activity.startsAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    Spacer()
                                    ActivityStatusBadge(status: activity.status)
                                }
                                .padding(AppSpacing.md)
                                .glassSurface(.regular, cornerRadius: AppRadius.card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.bottom, AppLayout.bottomNavigationClearance)
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            ActivityDetailView(activityID: id, repository: repository)
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
