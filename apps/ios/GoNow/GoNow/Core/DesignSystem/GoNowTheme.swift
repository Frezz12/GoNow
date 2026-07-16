import SwiftUI

enum GoNowTheme {
    static let primary = Color(red: 0.73, green: 0.30, blue: 0.52)
    static let accent = Color(red: 0.90, green: 0.43, blue: 0.62)
    static let background = Color(red: 0.97, green: 0.96, blue: 1.0)
    static let border = Color(red: 0.81, green: 0.77, blue: 0.95)
    static let buttonGradient = LinearGradient(
        colors: [Color(red: 0.91, green: 0.39, blue: 0.58), Color(red: 0.66, green: 0.46, blue: 0.85)],
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
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(GoNowTheme.buttonGradient)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct LiquidGlassFieldModifier: ViewModifier {
    let isInvalid: Bool

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
                    lineWidth: isInvalid ? 1.5 : 1
                )
            }
            .shadow(color: .white.opacity(0.18), radius: 4, y: -1)
            .shadow(color: GoNowTheme.primary.opacity(0.1), radius: 10, y: 4)
    }
}

extension View {
    func liquidGlassField(isInvalid: Bool) -> some View {
        modifier(LiquidGlassFieldModifier(isInvalid: isInvalid))
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
