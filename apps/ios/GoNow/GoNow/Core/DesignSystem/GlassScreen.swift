import SwiftUI

struct GlassScreen<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
                content
                    .frame(maxWidth: AppLayout.maxContentWidth, alignment: .leading)
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.top, AppSpacing.xl)
                    .padding(.bottom, AppLayout.bottomNavigationClearance)
            }
        }
    }
}
