import SwiftUI
import UIKit

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

enum AppRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let control: CGFloat = 16
    static let card: CGFloat = 22
    static let largeCard: CGFloat = 28
    static let sheet: CGFloat = 30
}

enum AppTypography {
    static let largeTitle: Font = .largeTitle.weight(.bold)
    static let screenTitle: Font = .title2.weight(.semibold)
    static let sectionTitle: Font = .headline.weight(.semibold)
    static let cardTitle: Font = .headline.weight(.semibold)
    static let body: Font = .body
    static let bodyMedium: Font = .body.weight(.medium)
    static let caption: Font = .caption
    static let captionStrong: Font = .caption.weight(.semibold)
    static let button: Font = .body.weight(.semibold)
    static let badge: Font = .caption.weight(.semibold)
}

enum AppLayout {
    static let horizontalInset: CGFloat = AppSpacing.lg
    static let maxContentWidth: CGFloat = 620
    static let minimumTouchTarget: CGFloat = 44
    static let bottomNavigationClearance: CGFloat = 112
}

enum AppAnimation {
    static let fast = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let slow = Animation.easeInOut(duration: 0.4)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.88)
}

enum AppHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func confirmation() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
