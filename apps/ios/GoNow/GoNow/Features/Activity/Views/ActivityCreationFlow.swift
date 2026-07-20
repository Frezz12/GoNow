import PhotosUI
import SwiftUI

struct ActivityCreationFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var location: DeviceLocationProvider
    @StateObject private var model: ActivityCreationViewModel
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var locationMode: ActivityLocationMode = .current
    @State private var isMapPickerPresented = false
    @State private var isDiscardConfirmationPresented = false
    @State private var waitsForCurrentLocation = false
    let onComplete: (GoNowActivity) -> Void

    init(
        repository: any ActivityRepository,
        location: DeviceLocationProvider,
        onComplete: @escaping (GoNowActivity) -> Void
    ) {
        _model = StateObject(wrappedValue: ActivityCreationViewModel(repository: repository))
        self.location = location
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                if model.isRestoring {
                    ProgressView("activity.draft.restoring")
                } else {
                    VStack(spacing: 0) {
                        ActivityWizardProgress(step: model.step, progress: model.progress, onSelect: model.selectStep)
                            .padding(.horizontal, AppLayout.horizontalInset)
                            .padding(.vertical, AppSpacing.sm)
                            .background(.regularMaterial)
                        ScrollView {
                            stepContent
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .frame(maxWidth: AppLayout.maxContentWidth)
                                .padding(AppLayout.horizontalInset)
                                .padding(.bottom, AppSpacing.xxl)
                                .frame(maxWidth: .infinity)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        navigationBar
                    }
                }
            }
            .navigationTitle("activity.create.navigation_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.close") { isDiscardConfirmationPresented = true }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .fullScreenCover(isPresented: $isMapPickerPresented) {
            ActivityLocationPickerMap(coordinate: mapCoordinateBinding.wrappedValue) { coordinate in
                Task { await model.useCoordinate(coordinate, resolveAddress: false) }
            }
        }
        .task {
            await model.restoreDraft()
            if model.draft.location == nil { useCurrentLocation() }
        }
        .onChange(of: locationMode) { _, mode in
            if mode == .map { isMapPickerPresented = true }
        }
        .onChange(of: selectedPhotos) { _, items in
            Task {
                for item in items {
                    guard model.draft.photos.count < 6,
                          let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    await model.addPhotoData(data)
                }
                selectedPhotos = []
            }
        }
        .onChange(of: location.updateSequence) { _, _ in
            guard waitsForCurrentLocation,
                  let coordinate = location.coordinate.map(MapCoordinate.init) else { return }
            waitsForCurrentLocation = false
            Task { await model.useCoordinate(coordinate, resolveAddress: false) }
        }
        .alert("activity.discard.title", isPresented: $isDiscardConfirmationPresented) {
            Button("activity.discard.keep", role: .cancel) { }
            Button("activity.discard.close", role: .destructive) { dismiss() }
        } message: {
            Text("activity.discard.message")
        }
        .alert("error.validation", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.dismissError() } }
        )) {
            Button("common.done", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .basics: basicsStep
        case .photos: photosStep
        case .location: locationStep
        case .schedule: scheduleStep
        case .participants: participantsStep
        case .preview: previewStep
        }
    }

    private var basicsStep: some View {
        VStack(spacing: AppSpacing.lg) {
            ActivityFormSection("activity.basics.title", subtitleKey: "activity.basics.subtitle") {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("activity.field.title").font(AppTypography.captionStrong)
                    TextField("activity.field.title.placeholder", text: $model.draft.title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(1...3)
                        .padding(.horizontal, AppSpacing.md)
                        .frame(minHeight: 52)
                        .liquidGlassField(isInvalid: model.draft.title.count > 70, isFocused: false)
                        .onChange(of: model.draft.title) { _, value in
                            if value.count > 70 { model.draft.title = String(value.prefix(70)) }
                        }
                    ActivityCharacterCounter(current: model.draft.title.count, maximum: 70)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            ActivityFormSection("activity.field.category") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: AppSpacing.xs)], spacing: AppSpacing.xs) {
                    ForEach(ActivityCategory.allCases) { category in
                        Button { model.draft.category = category } label: {
                            VStack(spacing: AppSpacing.xs) {
                                Image(systemName: category.symbol).font(.title3)
                                Text(LocalizedStringKey(category.titleKey))
                                    .font(AppTypography.captionStrong)
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(model.draft.category == category ? AppColors.textOnAccent : AppColors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 76)
                            .background(model.draft.category == category ? AppColors.accentPrimary : AppColors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppRadius.medium))
                        }
                        .buttonStyle(AppPressButtonStyle())
                        .accessibilityAddTraits(model.draft.category == category ? .isSelected : [])
                    }
                }
            }

            ActivityFormSection("activity.field.description", subtitleKey: "activity.field.description.helper") {
                TextEditor(text: $model.draft.description)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(AppSpacing.sm)
                    .background(AppColors.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .onChange(of: model.draft.description) { _, value in
                        if value.count > 3_000 { model.draft.description = String(value.prefix(3_000)) }
                    }
                ActivityCharacterCounter(current: model.draft.description.count, maximum: 3_000)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var photosStep: some View {
        VStack(spacing: AppSpacing.lg) {
            ActivityFormSection("activity.photos.title", subtitleKey: "activity.photos.subtitle") {
                if model.draft.photos.isEmpty {
                    ActivityCategoryFallbackCard(category: model.draft.category)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: AppSpacing.sm) {
                            ForEach(model.draft.photos) { photo in photoCard(photo) }
                        }
                        .padding(.vertical, AppSpacing.xxs)
                    }
                    .scrollIndicators(.hidden)
                }

                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: max(0, 6 - model.draft.photos.count),
                    matching: .images
                ) {
                    Label("activity.photos.add", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(GradientPrimaryButtonStyle())
                .clipShape(Capsule())
                .disabled(model.draft.photos.count >= 6 || model.isProcessingPhotos)

                if model.isProcessingPhotos {
                    ProgressView("activity.photos.processing")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func photoCard(_ photo: ActivityDraftPhoto) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let image = UIImage(data: photo.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 208, height: 156)
                        .clipped()
                        .accessibilityLabel(photo.isCover ? "activity.photos.cover" : "activity.photos.item")
                }
                if photo.isCover {
                    Label("Обложка", systemImage: "star.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(AppSpacing.sm)
                }
            }

            HStack(spacing: 0) {
                Button { model.movePhoto(id: photo.id, direction: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                Button { model.movePhoto(id: photo.id, direction: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                Button { model.makeCover(id: photo.id) } label: {
                    Image(systemName: photo.isCover ? "star.fill" : "star").frame(width: 44, height: 44)
                }
                Button(role: .destructive) { model.removePhoto(id: photo.id) } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
        }
        .frame(width: 208)
        .background(AppColors.surfaceElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(photo.isCover ? AppColors.accentPrimary : AppColors.textMuted.opacity(0.16), lineWidth: photo.isCover ? 2 : 1)
        }
    }

    private var locationStep: some View {
        VStack(spacing: AppSpacing.lg) {
            ActivityFormSection("activity.location.title", subtitleKey: "activity.location.subtitle") {
                Picker("activity.location.mode.label", selection: $locationMode) {
                    ForEach([ActivityLocationMode.current, .map]) { mode in
                        Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch locationMode {
                case .map:
                    Button { isMapPickerPresented = true } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "map.fill")
                            Text("activity.location.mode.map")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(GradientPrimaryButtonStyle())
                    .clipShape(Capsule())
                case .current:
                    Button { useCurrentLocation() } label: {
                        Label("activity.location.current.action", systemImage: "location.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(GradientPrimaryButtonStyle())
                    .clipShape(Capsule())
                }

                if let location = model.draft.location {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Label("Точное местоположение выбрано", systemImage: "checkmark.circle.fill")
                            .font(AppTypography.captionStrong)
                            .foregroundStyle(AppColors.success)
                        Text(String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            ActivityFormSection("activity.location.details") {
                Picker("activity.location.visibility.label", selection: Binding(
                    get: { model.draft.location?.visibility ?? .everyone },
                    set: { value in
                        if model.draft.location == nil {
                            model.draft.location = ActivityLocation(coordinate: .moscow, address: nil, venueName: nil, visibility: value, isExact: true)
                        } else { model.draft.location?.visibility = value }
                    }
                )) {
                    ForEach(ActivityLocationVisibility.allCases) { value in
                        Text(LocalizedStringKey(value.titleKey)).tag(value)
                    }
                }
            }
        }
    }

    private var scheduleStep: some View {
        VStack(spacing: AppSpacing.lg) {
            ActivityFormSection("activity.schedule.start") {
                DatePicker("activity.schedule.date", selection: $model.draft.startsAt, in: Date()...)
                DatePicker("activity.schedule.time", selection: $model.draft.startsAt, displayedComponents: .hourAndMinute)
            }
            ActivityFormSection("activity.schedule.duration") {
                Picker("activity.schedule.duration", selection: $model.draft.durationPreset) {
                    ForEach(ActivityDurationPreset.allCases) { value in
                        Text(LocalizedStringKey(value.titleKey)).tag(value)
                    }
                }
                if model.draft.durationPreset == .custom {
                    Stepper(
                        L10n.format("activity.duration.minutes %lld", model.draft.customDurationMinutes),
                        value: $model.draft.customDurationMinutes,
                        in: 15...43_200,
                        step: 15
                    )
                }
            }
            ActivityFormSection("activity.schedule.visibility") {
                Picker("activity.schedule.show", selection: $model.draft.showTiming) {
                    ForEach(ActivityShowTiming.allCases) { value in Text(LocalizedStringKey(value.titleKey)).tag(value) }
                }
                if model.draft.showTiming == .custom {
                    DatePicker("activity.schedule.custom", selection: $model.draft.customShowAfter)
                }
                Picker("activity.schedule.hide", selection: $model.draft.hideTiming) {
                    ForEach(ActivityHideTiming.allCases) { value in Text(LocalizedStringKey(value.titleKey)).tag(value) }
                }
                if model.draft.hideTiming == .custom {
                    DatePicker("activity.schedule.custom", selection: $model.draft.customHideAfter)
                }
            }
        }
    }

    private var participantsStep: some View {
        VStack(spacing: AppSpacing.lg) {
            ActivityFormSection("activity.participants.title") {
                Picker("activity.participants.limit", selection: $model.draft.participantLimit) {
                    Text("activity.participants.unlimited").tag(Int?.none)
                    ForEach([2, 5, 10, 20], id: \.self) { value in Text(value.formatted()).tag(Int?.some(value)) }
                }
                Picker("activity.participants.join", selection: $model.draft.joinPolicy) {
                    ForEach(ActivityJoinPolicy.allCases) { value in Text(LocalizedStringKey(value.titleKey)).tag(value) }
                }
            }

            ActivityFormSection("activity.participants.requirements") {
                Picker("activity.participants.age", selection: $model.draft.ageMin) {
                    Text("activity.age.unlimited").tag(Int?.none)
                    Text("activity.age.18").tag(Int?.some(18))
                }
                Picker("activity.participants.skill", selection: $model.draft.skillLevel) {
                    ForEach(ActivitySkillLevel.allCases) { value in Text(LocalizedStringKey(value.titleKey)).tag(value) }
                }
                ActivityTagEditor(titleKey: "activity.participants.languages", values: $model.draft.languages)
            }

            ActivityFormSection("activity.cost.title") {
                Picker("activity.cost.title", selection: $model.draft.costType) {
                    ForEach(ActivityCostType.allCases) { value in Text(LocalizedStringKey(value.titleKey)).tag(value) }
                }
                if model.draft.costType == .fixed || model.draft.costType == .estimated {
                    TextField("activity.cost.amount.placeholder", value: Binding(
                        get: { model.draft.costAmountCents.map { Double($0) / 100 } },
                        set: { model.draft.costAmountCents = $0.map { Int($0 * 100) } }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(minHeight: 50)
                    .liquidGlassField(isInvalid: false, isFocused: false)
                }
            }

            ActivityFormSection("activity.rules.title") {
                ActivityTagEditor(titleKey: "activity.bring.title", values: $model.draft.bringItems)
                ActivityTagEditor(titleKey: "activity.rules.additional", values: $model.draft.rules)
            }

        }
    }

    private var previewStep: some View {
        ActivityDraftPreview(draft: model.draft)
            .frame(maxWidth: .infinity)
    }

    private var navigationBar: some View {
        HStack(spacing: AppSpacing.sm) {
            if model.step != .basics {
                Button("common.back", action: model.moveBack)
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                    .frame(minHeight: 52)
            }
            Spacer(minLength: 0)
            if model.isLastStep {
                Button {
                    Task {
                        if await model.submit(), let activity = model.publishedActivity {
                            onComplete(activity)
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if model.isSubmitting { ProgressView().tint(AppColors.textOnAccent) }
                        Text("activity.publish")
                    }
                    .frame(minWidth: 150)
                }
                .buttonStyle(GradientPrimaryButtonStyle())
                .clipShape(Capsule())
                .disabled(model.isSubmitting)
            } else {
                Button("common.next", action: model.moveForward)
                    .buttonStyle(GradientPrimaryButtonStyle())
                    .clipShape(Capsule())
                    .disabled(!model.canMoveForward)
            }
        }
        .padding(.horizontal, AppLayout.horizontalInset)
        .padding(.vertical, AppSpacing.sm)
        .background(.regularMaterial)
    }

    private var mapCoordinateBinding: Binding<MapCoordinate> {
        Binding(
            get: { model.draft.location?.coordinate ?? location.coordinate.map(MapCoordinate.init) ?? .moscow },
            set: { coordinate in
                if model.draft.location == nil {
                    model.draft.location = ActivityLocation(coordinate: coordinate, address: nil, venueName: nil, visibility: .everyone, isExact: true)
                } else { model.draft.location?.coordinate = coordinate }
            }
        )
    }

    private func useCurrentLocation() {
        waitsForCurrentLocation = true
        if let coordinate = location.coordinate.map(MapCoordinate.init) {
            waitsForCurrentLocation = false
            Task { await model.useCoordinate(coordinate, resolveAddress: false) }
        } else {
            location.requestCurrentLocation()
        }
    }
}

private struct ActivityDraftPreview: View {
    let draft: ActivityDraft

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if let cover = draft.photos.first(where: \.isCover), let image = UIImage(data: cover.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
            } else {
                ActivityCategoryFallbackCard(category: draft.category)
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(draft.title).font(.title.bold())
                Label(LocalizedStringKey(draft.category.titleKey), systemImage: draft.category.symbol)
                    .foregroundStyle(AppColors.accentPrimary)
                if !draft.description.isEmpty { Text(draft.description).font(AppTypography.body) }
                Divider()
                Label(draft.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label(L10n.format("activity.duration.minutes %lld", draft.durationMinutes), systemImage: "clock")
                if let location = draft.location {
                    Label(
                        String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude),
                        systemImage: "mappin.and.ellipse"
                    )
                }
                Label(draft.participantLimit?.formatted() ?? L10n.string("activity.participants.unlimited"), systemImage: "person.2")
            }
            .padding(AppSpacing.lg)
            .glassSurface(.prominent, cornerRadius: AppRadius.card)
        }
    }
}
