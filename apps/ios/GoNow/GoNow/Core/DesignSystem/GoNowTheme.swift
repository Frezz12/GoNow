import SwiftUI

enum GoNowTheme {
    static let primary = Color(red: 0.73, green: 0.30, blue: 0.52)
    static let accent = Color(red: 0.90, green: 0.43, blue: 0.62)
    static let background = Color(red: 0.97, green: 0.96, blue: 1.0)
    static let border = Color(red: 0.81, green: 0.77, blue: 0.95)
    static let buttonGradient = LinearGradient(
        colors: [Color(red: 0.83, green: 0.12, blue: 0.39), Color(red: 0.48, green: 0.22, blue: 0.78)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct AuthBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.87, blue: 0.91), Color(red: 0.86, green: 0.84, blue: 0.98), Color(red: 0.73, green: 0.86, blue: 0.98)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct MapPointMarker: View {
    var size: CGFloat = 76

    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, GoNowTheme.primary)
            .shadow(color: GoNowTheme.primary.opacity(0.22), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Метка активности на карте")
    }
}

struct GradientPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(GoNowTheme.buttonGradient, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.34), .white.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                shape
                    .strokeBorder(.black.opacity(0.16), lineWidth: 1)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: 18)
                    }
                    .allowsHitTesting(false)
            }
            .shadow(color: GoNowTheme.primary.opacity(0.32), radius: 14, y: 7)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isDestructive ? .red : .primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.thinMaterial, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(
                    isDestructive ? Color.red.opacity(0.32) : .white.opacity(0.72),
                    lineWidth: 1
                )
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct GlassInlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(GoNowTheme.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(.thinMaterial, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay { shape.strokeBorder(.white.opacity(0.72), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        content
            .padding(18)
            .background(.thinMaterial, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.84), GoNowTheme.primary.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: GoNowTheme.primary.opacity(0.1), radius: 14, y: 6)
    }
}

private struct LiquidGlassFieldModifier: ViewModifier {
    let isInvalid: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .background(.ultraThinMaterial, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(
                    isInvalid
                        ? AnyShapeStyle(Color.red.opacity(0.9))
                        : AnyShapeStyle(LinearGradient(
                            colors: [.white.opacity(0.82), GoNowTheme.primary.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )),
                    lineWidth: isInvalid ? 1.6 : 1
                )
            }
            .overlay {
                if isFocused && !isInvalid {
                    FieldFocusGlow(shape: shape)
                }
            }
            .shadow(color: isFocused ? .white.opacity(0.4) : .white.opacity(0.18), radius: isFocused ? 7 : 4, y: -1)
            .shadow(color: isFocused ? GoNowTheme.primary.opacity(0.3) : GoNowTheme.primary.opacity(0.1), radius: isFocused ? 16 : 10, y: 4)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

private struct FieldFocusGlow: View {
    let shape: RoundedRectangle

    var body: some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: [GoNowTheme.primary, GoNowTheme.accent, Color(red: 0.39, green: 0.49, blue: 0.94), GoNowTheme.primary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.8
            )
            .shadow(color: GoNowTheme.primary.opacity(0.34), radius: 13, x: -8)
            .shadow(color: Color(red: 0.39, green: 0.49, blue: 0.94).opacity(0.30), radius: 13, x: 8)
            .shadow(color: GoNowTheme.accent.opacity(0.18), radius: 5)
    }
}

extension View {
    func liquidGlassField(isInvalid: Bool, isFocused: Bool) -> some View {
        modifier(LiquidGlassFieldModifier(isInvalid: isInvalid, isFocused: isFocused))
    }
}

struct ErrorMessage: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .accessibilityLabel("Ошибка: \(text)")
    }
}
