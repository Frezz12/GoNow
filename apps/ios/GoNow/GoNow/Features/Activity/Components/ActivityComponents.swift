import SwiftUI

struct ActivityWizardProgress: View {
    let step: ActivityWizardStep
    let progress: Double
    let onSelect: (ActivityWizardStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(L10n.format("activity.progress %lld %lld", step.rawValue + 1, ActivityWizardStep.allCases.count))
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColors.accentPrimary)
                Spacer()
                Text(LocalizedStringKey(step.titleKey))
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColors.textSecondary)
            }
            ProgressView(value: progress)
                .tint(AppColors.accentPrimary)
                .accessibilityValue(Text(L10n.format("activity.progress %lld %lld", step.rawValue + 1, ActivityWizardStep.allCases.count)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(ActivityWizardStep.allCases) { item in
                        Button { onSelect(item) } label: {
                            Circle()
                                .fill(item.rawValue <= step.rawValue ? AppColors.accentPrimary : AppColors.surfaceElevated)
                                .frame(width: 12, height: 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(item.rawValue >= step.rawValue)
                        .frame(width: AppLayout.minimumTouchTarget, height: AppLayout.minimumTouchTarget)
                        .accessibilityLabel(LocalizedStringKey(item.titleKey))
                        .accessibilityAddTraits(item == step ? .isSelected : [])
                    }
                }
            }
        }
    }
}

struct ActivityFormSection<Content: View>: View {
    let titleKey: String
    let subtitleKey: String?
    @ViewBuilder let content: Content

    init(_ titleKey: String, subtitleKey: String? = nil, @ViewBuilder content: () -> Content) {
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(LocalizedStringKey(titleKey))
                .font(AppTypography.sectionTitle)
            if let subtitleKey {
                Text(LocalizedStringKey(subtitleKey))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.regular, cornerRadius: AppRadius.card)
    }
}

struct ActivityCharacterCounter: View {
    let current: Int
    let maximum: Int

    var body: some View {
        Text("\(current)/\(maximum)")
            .font(AppTypography.caption)
            .monospacedDigit()
            .foregroundStyle(current > maximum ? AppColors.error : AppColors.textSecondary)
            .accessibilityLabel(L10n.format("activity.characters %lld %lld", current, maximum))
    }
}

struct ActivityCategoryFallbackCard: View {
    let category: ActivityCategory

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AppGradients.brand
            Image(systemName: category.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(AppColors.textOnAccent.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(AppSpacing.lg)
            Text(LocalizedStringKey(category.titleKey))
                .font(.title2.bold())
                .foregroundStyle(AppColors.textOnAccent)
                .padding(AppSpacing.lg)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ActivityLocationPickerMap: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onConfirm: (MapCoordinate) -> Void
    @StateObject private var styleLoader = MapStyleLoader()
    @State private var coordinate: MapCoordinate
    @State private var mapLoadState: MapLibreLoadState = .loading

    init(coordinate: MapCoordinate, onConfirm: @escaping (MapCoordinate) -> Void) {
        self.onConfirm = onConfirm
        _coordinate = State(initialValue: coordinate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mapSurface

                VStack(spacing: 0) {
                    Image(systemName: "mappin")
                        .font(.system(size: 50, weight: .black))
                        .foregroundStyle(AppColors.error)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
                    Circle()
                        .fill(.black.opacity(0.18))
                        .frame(width: 10, height: 5)
                        .blur(radius: 1)
                }
                .offset(y: -25)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                mapStateOverlay

                VStack(spacing: AppSpacing.sm) {
                    Text("activity.location.map.accessibility")
                        .font(AppTypography.captionStrong)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.md)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: Capsule())

                    Spacer()

                    attribution

                    VStack(spacing: AppSpacing.sm) {
                        Text(coordinateText)
                            .font(AppTypography.caption)
                            .monospacedDigit()
                            .foregroundStyle(AppColors.textSecondary)

                        Button("activity.location.map.confirm") {
                            onConfirm(coordinate)
                            dismiss()
                        }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .disabled(mapLoadState != .loaded)
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                }
                .padding(AppLayout.horizontalInset)
                .padding(.bottom, AppSpacing.sm)
            }
            .navigationTitle("activity.location.mode.map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
        .task { styleLoader.load() }
        .task(id: styleLoader.loadedDocumentID) {
            guard styleLoader.loadedDocumentID != nil, mapLoadState == .loading else { return }
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, mapLoadState == .loading else { return }
            mapLoadState = .failed
        }
    }

    @ViewBuilder
    private var mapSurface: some View {
        if case .loaded(let document) = styleLoader.state {
            MapLibreActivityMap(
                styleJSON: document.json,
                activities: [],
                userCoordinate: nil,
                selectedActivityID: nil,
                initialCamera: PersistedMapCamera(center: coordinate, zoom: 14, bearing: 0, pitch: 0),
                cameraCommand: nil,
                reduceMotion: reduceMotion,
                onLoadStateChange: { mapLoadState = $0 },
                onViewportIdle: { viewport, _, _ in coordinate = viewport.center },
                onSelectActivity: { _ in },
                onDeselectActivity: { }
            )
            .id(document.id)
            .ignoresSafeArea(edges: .bottom)
            .accessibilityLabel("activity.location.map.accessibility")
        } else {
            AppColors.backgroundPrimary
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private var mapStateOverlay: some View {
        switch styleLoader.state {
        case .idle, .loading:
            ProgressView()
                .padding(AppSpacing.md)
                .glassSurface(.floating, cornerRadius: AppRadius.control)
                .accessibilityLabel("map.loading")
        case .failed:
            ActivityLocationMapStatus(retry: retryMap)
        case .loaded:
            switch mapLoadState {
            case .loading:
                ProgressView()
                    .padding(AppSpacing.md)
                    .glassSurface(.floating, cornerRadius: AppRadius.control)
                    .accessibilityLabel("map.loading")
            case .failed:
                ActivityLocationMapStatus(retry: retryMap)
            case .loaded:
                EmptyView()
            }
        }
    }

    private var attribution: some View {
        HStack(spacing: 3) {
            Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                Text(verbatim: "© OpenStreetMap")
            }
            Text(verbatim: "·")
            Link(destination: URL(string: "https://openfreemap.org")!) {
                Text(verbatim: "OpenFreeMap")
            }
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, AppSpacing.sm)
        .frame(minHeight: AppLayout.minimumTouchTarget)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func retryMap() {
        mapLoadState = .loading
        styleLoader.reload()
    }

    private var coordinateText: String {
        coordinate.latitude.formatted(.number.precision(.fractionLength(5)))
            + ", "
            + coordinate.longitude.formatted(.number.precision(.fractionLength(5)))
    }
}

private struct ActivityLocationMapStatus: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Label("map.service.unavailable", systemImage: "wifi.exclamationmark")
                .font(AppTypography.captionStrong)
            Button("common.retry", action: retry)
                .fontWeight(.semibold)
                .frame(minHeight: AppLayout.minimumTouchTarget)
        }
        .padding(AppSpacing.md)
        .glassSurface(.floating, cornerRadius: AppRadius.control)
    }
}

struct ActivityStatusBadge: View {
    let status: ActivityLifecycleStatus

    var body: some View {
        Text(LocalizedStringKey(status.titleKey))
            .font(AppTypography.badge)
            .foregroundStyle(AppColors.accentPrimary)
            .padding(.horizontal, AppSpacing.sm)
            .frame(minHeight: 30)
            .background(AppColors.accentPrimary.opacity(0.12), in: Capsule())
    }
}

struct ActivityTagEditor: View {
    let titleKey: String
    @Binding var values: [String]
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(LocalizedStringKey(titleKey)).font(AppTypography.captionStrong)
            TextField("activity.tag.placeholder", text: $input)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(addValue)
                .padding(.horizontal, AppSpacing.md)
                .frame(minHeight: 48)
                .liquidGlassField(isInvalid: false, isFocused: false)
            if !values.isEmpty {
                FlowLayout(spacing: AppSpacing.xs) {
                    ForEach(values, id: \.self) { value in
                        Button { values.removeAll { $0 == value } } label: {
                            Label(value, systemImage: "xmark")
                                .font(AppTypography.captionStrong)
                                .padding(.horizontal, AppSpacing.sm)
                                .frame(minHeight: 36)
                                .background(AppColors.surfaceElevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("activity.tag.remove.hint")
                    }
                }
            }
        }
    }

    private func addValue() {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !values.contains(clean) else { return }
        values.append(clean)
        input = ""
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += lineHeight + spacing; lineHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
