import SwiftUI

/// Compatibility names for existing feature code. New code should use AppColors and AppGradients.
enum GoNowTheme {
    static let primary = AppColors.accentPrimary
    static let accent = AppColors.accentSecondary
    static let background = AppColors.backgroundPrimary
    static let border = AppColors.borderSubtle
    static let buttonGradient = AppGradients.brand
}

enum GlassSurfaceStyle {
    case subtle
    case regular
    case prominent
    case floating

    var material: Material {
        switch self {
        case .subtle: .ultraThinMaterial
        case .regular: .thinMaterial
        case .prominent, .floating: .regularMaterial
        }
    }

    var tint: Color {
        switch self {
        case .subtle: AppColors.surfaceGlass.opacity(0.20)
        case .regular: AppColors.surfaceGlass.opacity(0.34)
        case .prominent: AppColors.surfaceGlassStrong.opacity(0.62)
        case .floating: AppColors.surfaceGlassStrong.opacity(0.64)
        }
    }

    var shadowLevel: AppShadowLevel {
        switch self {
        case .subtle: .subtle
        case .regular: .card
        case .prominent: .sheet
        case .floating: .floating
        }
    }
}

enum AppShadowLevel {
    case none
    case subtle
    case card
    case floating
    case sheet
}

struct GlassSurfaceModifier: ViewModifier {
    let style: GlassSurfaceStyle
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if reduceTransparency {
                content
                    .background(AppColors.surfaceGlassStrong, in: shape)
            } else {
                content
                    .background(style.tint, in: shape)
                    .background(style.material, in: shape)
                    .glassEffect(.regular, in: shape)
            }
        }
        .overlay {
            shape.strokeBorder(
                AppGradients.glassHighlight,
                lineWidth: reduceTransparency ? 1.5 : 1
            )
        }
        .overlay(alignment: .top) {
            shape
                .strokeBorder(AppColors.glassHighlight.opacity(reduceTransparency ? 0.22 : 0.42), lineWidth: 0.75)
                .mask(alignment: .top) { Rectangle().frame(height: cornerRadius * 0.86) }
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .appShadow(style.shadowLevel)
    }
}

extension View {
    func glassSurface(_ style: GlassSurfaceStyle = .regular, cornerRadius: CGFloat = AppRadius.card) -> some View {
        modifier(GlassSurfaceModifier(style: style, cornerRadius: cornerRadius))
    }

    func appShadow(_ level: AppShadowLevel) -> some View {
        modifier(AppShadowModifier(level: level))
    }

    func liquidGlassField(isInvalid: Bool, isFocused: Bool) -> some View {
        modifier(AppTextFieldSurfaceModifier(isInvalid: isInvalid, isFocused: isFocused))
    }
}

private struct AppShadowModifier: ViewModifier {
    let level: AppShadowLevel
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let values: (opacity: Double, radius: CGFloat, y: CGFloat) = switch level {
        case .none: (0, 0, 0)
        case .subtle: (0.06, 8, 3)
        case .card: (0.08, 16, 6)
        case .floating: (0.12, 20, 8)
        case .sheet: (0.14, 28, 12)
        }
        content.shadow(
            color: AppColors.shadow.opacity(colorScheme == .dark ? values.opacity * 0.42 : values.opacity),
            radius: values.radius,
            y: values.y
        )
    }
}

struct AppPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.fast, value: configuration.isPressed)
    }
}

struct GradientPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(AppColors.textOnAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AppGradients.brand, in: shape)
            .overlay { shape.strokeBorder(AppColors.glassHighlight.opacity(0.64), lineWidth: 1) }
            .overlay {
                shape.fill(AppGradients.glassHighlight)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .appShadow(.floating)
            .buttonStyle(AppPressButtonStyle())
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(isDestructive ? AppColors.error : AppColors.accentPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .glassSurface(.regular, cornerRadius: AppRadius.control)
            .buttonStyle(AppPressButtonStyle())
    }
}

struct GlassInlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.captionStrong)
            .foregroundStyle(AppColors.accentPrimary)
            .padding(.horizontal, AppSpacing.sm)
            .frame(minHeight: AppLayout.minimumTouchTarget)
            .glassSurface(.subtle, cornerRadius: AppRadius.control)
            .buttonStyle(AppPressButtonStyle())
    }
}

struct GlassCard<Content: View>: View {
    let style: GlassSurfaceStyle
    private let content: Content

    init(style: GlassSurfaceStyle = .regular, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppSpacing.lg)
            .glassSurface(style, cornerRadius: AppRadius.card)
    }
}

struct GlassPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppSpacing.md)
            .glassSurface(.floating, cornerRadius: AppRadius.largeCard)
    }
}

struct AppTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String? = nil
    var isSecure = false
    var error: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColors.textSecondary)
            Group {
                if isSecure {
                    SecureField(prompt ?? title, text: $text)
                } else {
                    TextField(prompt ?? title, text: $text)
                }
            }
            .focused($isFocused)
            .padding(.horizontal, AppSpacing.md)
            .frame(minHeight: 52)
            .liquidGlassField(isInvalid: error != nil, isFocused: isFocused)
            if let error {
                ErrorMessage(text: error)
            }
        }
    }
}

struct AppEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(AppColors.accentPrimary)
                .frame(width: 68, height: 68)
                .glassSurface(.subtle, cornerRadius: 24)
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GradientPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
    }
}

struct AppBadge: View {
    let title: String
    var tint: Color = AppColors.accentPrimary

    var body: some View {
        Text(title)
            .font(AppTypography.badge)
            .foregroundStyle(tint)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(title)
    }
}

enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case map
    case tasks
    case chat
    case profile

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .map: L10n.string("tab.map")
        case .tasks: L10n.string("tab.tasks")
        case .chat: L10n.string("tab.chat")
        case .profile: L10n.string("tab.profile")
        }
    }

    var symbol: String {
        switch self {
        case .map: "map.fill"
        case .tasks: "checklist"
        case .chat: "message.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

struct AuthBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.backgroundPrimary, AppColors.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            AppGradients.brandSoft
                .blur(radius: 34)
                .opacity(0.86)
                .padding(-40)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct MapPointMarker: View {
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.palette)
            .foregroundStyle(AppColors.textOnAccent, AppColors.accentPrimary)
            .appShadow(.floating)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("map.marker.accessibility")
    }
}

private struct AppTextFieldSurfaceModifier: ViewModifier {
    let isInvalid: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        content
            .foregroundStyle(AppColors.textPrimary)
            .background(AppColors.surfaceSecondary, in: shape)
            .overlay {
                shape.strokeBorder(
                    isInvalid ? AppColors.error : (isFocused ? AppColors.accentPrimary : AppColors.borderSubtle),
                    lineWidth: isFocused || isInvalid ? 1.5 : 1
                )
            }
            .shadow(color: isFocused ? AppColors.accentPrimary.opacity(0.20) : .clear, radius: 12, y: 4)
            .animation(AppAnimation.fast, value: isFocused)
    }
}

struct ErrorMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.error)
            .accessibilityLabel(L10n.format("common.error.accessibility %@", text))
    }
}
