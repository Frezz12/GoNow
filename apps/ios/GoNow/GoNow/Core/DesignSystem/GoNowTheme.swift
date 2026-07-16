import SwiftUI

enum GoNowTheme {
    static let primary = Color(red: 0.88, green: 0.11, blue: 0.28)
    static let background = Color(red: 1.0, green: 0.945, blue: 0.95)
    static let border = Color(red: 0.996, green: 0.804, blue: 0.835)
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
