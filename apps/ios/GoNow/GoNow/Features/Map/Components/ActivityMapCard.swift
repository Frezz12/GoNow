import SwiftUI

struct ActivityMapCard: View {
    let activity: MapActivity
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: activity.category.symbol)
                    .font(.headline)
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 42, height: 42)
                    .background(AppGradients.brand, in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(activity.title)
                        .font(AppTypography.cardTitle)
                        .lineLimit(2)
                    Text(LocalizedStringKey(activity.category.titleKey))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: AppLayout.minimumTouchTarget, height: AppLayout.minimumTouchTarget)
                }
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityLabel("common.close")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.lg) {
                    activityMetadata
                }
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    activityMetadata
                }
            }
            .font(AppTypography.captionStrong)
            .foregroundStyle(AppColors.textSecondary)

            Button("map.activity.open", action: onOpen)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
        }
        .padding(AppSpacing.md)
        .glassSurface(.prominent, cornerRadius: AppRadius.card)
        .appShadow(.floating)
        .accessibilityElement(children: .contain)
    }

    private var participantsText: String {
        if let limit = activity.participantLimit { return "\(activity.participantCount)/\(limit)" }
        return String(activity.participantCount)
    }

    @ViewBuilder
    private var activityMetadata: some View {
        Label(activity.startsAt.formatted(date: .omitted, time: .shortened), systemImage: "clock.fill")
        Label(participantsText, systemImage: "person.2.fill")
        if let distance = activity.distanceMeters {
            Label(AppFormatters.distance(kilometers: max(0, distance) / 1_000), systemImage: "location.fill")
        }
    }
}
