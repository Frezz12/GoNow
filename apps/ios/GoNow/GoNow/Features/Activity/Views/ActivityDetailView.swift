import MapKit
import SwiftUI
import UIKit

struct ActivityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ActivityDetailViewModel
    private let repository: any ActivityRepository
    @State private var isApplicationPresented = false
    @State private var isChatPresented = false
    @State private var duplicatedActivity: GoNowActivity?

    init(activityID: UUID, repository: any ActivityRepository) {
        self.repository = repository
        _model = StateObject(wrappedValue: ActivityDetailViewModel(activityID: activityID, repository: repository))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                if let activity = model.activity {
                    ScrollView {
                        ActivityDetailContent(activity: activity, coverPhotoData: model.coverPhotoData)
                            .frame(maxWidth: AppLayout.maxContentWidth)
                            .padding(AppLayout.horizontalInset)
                            .padding(.bottom, 104)
                    }
                    actionBar(activity)
                } else if model.isLoading {
                    ProgressView("activity.loading")
                } else if let error = model.errorMessage {
                    ContentUnavailableView {
                        Label("activity.error.title", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("common.retry") { Task { await model.load() } }
                    }
                }
            }
            .navigationTitle("activity.detail.navigation_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("common.close") { dismiss() } }
                if model.activity?.isOrganizer == true {
                    ToolbarItem(placement: .topBarTrailing) { organizerMenu }
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $isApplicationPresented) {
            ActivityApplicationForm(model: model)
        }
        .sheet(isPresented: $isChatPresented) {
            ChatTabView()
        }
        .alert("activity.duplicate.done", isPresented: Binding(
            get: { duplicatedActivity != nil },
            set: { if !$0 { duplicatedActivity = nil } }
        )) { Button("common.done", role: .cancel) { duplicatedActivity = nil } }
    }

    @ViewBuilder
    private func actionBar(_ activity: GoNowActivity) -> some View {
        VStack {
            Spacer()
            HStack(spacing: AppSpacing.sm) {
                if activity.isOrganizer {
                    NavigationLink {
                        ActivityApplicationsView(activityID: activity.id, repository: repository)
                    } label: {
                        Label("activity.applications.title", systemImage: "person.2.badge.gearshape")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                } else if activity.canAccessChat {
                    Button { isChatPresented = true } label: {
                        Label("activity.chat.open", systemImage: "bubble.left.and.bubble.right.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                } else if activity.applicationStatus == nil && !activity.recruitmentClosed && !activity.isFull {
                    Button { isApplicationPresented = true } label: {
                        Label("activity.apply.action", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(GradientPrimaryButtonStyle())
                } else if let status = activity.applicationStatus {
                    Label(LocalizedStringKey(status.titleKey), systemImage: "clock.badge.checkmark")
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .padding(AppLayout.horizontalInset)
            .background(.regularMaterial)
        }
    }

    private var organizerMenu: some View {
        Menu {
            NavigationLink {
                ActivityApplicationsView(activityID: model.activityID, repository: repository)
            } label: { Label("activity.applications.title", systemImage: "person.2") }
            Button {
                Task { await model.toggleRecruitment() }
            } label: {
                Label(
                    model.activity?.recruitmentClosed == true ? "activity.recruitment.open" : "activity.recruitment.close",
                    systemImage: "person.2.slash"
                )
            }
            Button {
                Task { duplicatedActivity = await model.duplicate() }
            } label: { Label("activity.duplicate", systemImage: "doc.on.doc") }
            Button {
                Task { await model.changeStatus(.completed) }
            } label: { Label("activity.complete", systemImage: "checkmark.seal") }
            Button(role: .destructive) {
                Task { await model.changeStatus(.cancelled) }
            } label: { Label("activity.cancel", systemImage: "xmark.circle") }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
        }
        .accessibilityLabel("activity.manage")
    }
}

struct ActivityDetailContent: View {
    let activity: GoNowActivity
    let coverPhotoData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if let coverPhotoData, let image = UIImage(data: coverPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                    .accessibilityLabel("activity.photos.cover")
            } else {
                ActivityCategoryFallbackCard(category: activity.category)
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .top) {
                    Text(activity.title).font(.title.bold())
                    Spacer(minLength: AppSpacing.sm)
                    ActivityStatusBadge(status: activity.status)
                }
                if !activity.description.isEmpty { Text(activity.description).font(AppTypography.body) }
            }
            ActivityFormSection("activity.detail.when_where") {
                Label(activity.startsAt.formatted(date: .long, time: .shortened), systemImage: "calendar")
                Label(L10n.format("activity.duration.minutes %lld", activity.durationMinutes), systemImage: "clock")
                if let venue = activity.location.venueName { Label(venue, systemImage: "door.left.hand.open") }
                if let address = activity.location.address { Label(address, systemImage: "mappin.and.ellipse") }
                if !activity.location.isExact {
                    Label("activity.location.approximate", systemImage: "eye.slash")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            ActivityFormSection("activity.detail.participation") {
                Label(participantsText, systemImage: "person.2.fill")
                Label(LocalizedStringKey(activity.joinPolicy.titleKey), systemImage: "person.badge.plus")
                Label(LocalizedStringKey(activity.skillLevel.titleKey), systemImage: "chart.bar.fill")
                if !activity.languages.isEmpty { Label(activity.languages.joined(separator: ", "), systemImage: "globe") }
            }
            if !activity.bringItems.isEmpty || !activity.rules.isEmpty {
                ActivityFormSection("activity.detail.preparation") {
                    ForEach(activity.bringItems, id: \.self) { Label($0, systemImage: "bag.fill") }
                    ForEach(activity.rules, id: \.self) { Label($0, systemImage: "checkmark.shield") }
                }
            }
        }
    }

    private var participantsText: String {
        guard let limit = activity.participantLimit else {
            return L10n.format("activity.participants.current %lld", activity.participantCount)
        }
        return L10n.format("activity.participants.current_limit %lld %lld", activity.participantCount, limit)
    }
}

private struct ActivityApplicationForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ActivityDetailViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("activity.apply.message.title") {
                    TextField("activity.apply.message.placeholder", text: $model.applicationMessage, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let questions = model.activity?.additionalQuestions {
                    ForEach(questions) { question in
                        Section(question.prompt) {
                            switch question.kind {
                            case .shortText:
                                TextField("activity.apply.answer.placeholder", text: answerBinding(question.id))
                            case .yesNo:
                                Picker(question.prompt, selection: answerBinding(question.id)) {
                                    Text("common.yes").tag("yes")
                                    Text("common.no").tag("no")
                                }
                                .pickerStyle(.segmented)
                            case .singleChoice:
                                Picker(question.prompt, selection: answerBinding(question.id)) {
                                    ForEach(question.options, id: \.self) { Text($0).tag($0) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("activity.apply.navigation_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("activity.apply.send") {
                        Task { if await model.apply() { dismiss() } }
                    }
                    .disabled(model.isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(model.isSubmitting)
    }

    private func answerBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { model.answers[id, default: ""] }, set: { model.answers[id] = $0 })
    }
}
