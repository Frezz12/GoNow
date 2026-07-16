import SwiftUI

struct GlassScreen<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
                content
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(20)
                    .padding(.bottom, 32)
            }
        }
    }
}
