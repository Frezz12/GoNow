import SwiftUI

struct ActivityMapCard: View {
    let activity: MapActivity
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header: icon, title, close button
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(AppGradients.brand)
                        .frame(width: 52, height: 52)

                    Image(systemName: activity.category.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.textOnAccent)
                }
                .appShadow(.card)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)

                    Text(LocalizedStringKey(activity.category.titleKey))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColors.textMuted)
                }
                .buttonStyle(AppPressButtonStyle())
                .accessibilityLabel("common.close")
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)

            // Divider with glass effect
            Divider()
                .background(AppColors.glassBorder.opacity(0.4))
                .padding(.horizontal, AppSpacing.md)

            // Metadata row with icons
            HStack(spacing: AppSpacing.md) {
                metadataItem(
                    icon: "clock.fill",
                    text: activity.startsAt.formatted(date: .omitted, time: .shortened)
                )

                metadataItem(
                    icon: "person.2.fill",
                    text: participantsText
                )

                if let distance = activity.distanceMeters {
                    metadataItem(
                        icon: "location.fill",
                        text: AppFormatters.distance(kilometers: max(0, distance) / 1_000)
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)

            // Action buttons row
            HStack(spacing: AppSpacing.xs) {
                // View details button (primary action)
                Button(action: onOpen) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.body.weight(.semibold))
                        Text("map.activity.open")
                            .font(AppTypography.bodyMedium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppGradients.brand, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .foregroundStyle(AppColors.textOnAccent)
                }
                .buttonStyle(AppPressButtonStyle())
                .appShadow(.card)

                // Quick action: view participants
                actionButton(icon: "person.2", accessibilityLabel: "activity.participants") {
                    onOpen() // ponytail: Opens full detail; add direct participants sheet later
                }

                // Quick action: expand to full view
                actionButton(icon: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "activity.expand") {
                    onOpen()
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.md)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColors.glassBorder.opacity(0.5), lineWidth: 0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AppColors.glassHighlight.opacity(0.8),
                            AppColors.glassHighlight.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .appShadow(.floating)
        .accessibilityElement(children: .contain)
    }

    private var participantsText: String {
        if let limit = activity.participantLimit { return "\(activity.participantCount)/\(limit)" }
        return String(activity.participantCount)
    }

    private func metadataItem(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.accentPrimary)

            Text(text)
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 6)
        .background(AppColors.surfaceElevated.opacity(0.5), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(AppColors.glassBorder.opacity(0.3), lineWidth: 0.5)
        }
    }

    private func actionButton(icon: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(AppColors.accentPrimary)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control)
                        .strokeBorder(AppColors.glassBorder.opacity(0.4), lineWidth: 0.5)
                }
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}
