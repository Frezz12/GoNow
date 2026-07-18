import SwiftUI
import Foundation

enum ProfileDate {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ value: String) -> Date? { formatter.date(from: value) }
    static func format(_ value: Date) -> String { formatter.string(from: value) }

    static func display(_ value: Date) -> String {
        value.formatted(.dateTime.locale(L10n.locale).day().month(.wide))
    }
}

enum ProfileCompletionStatus: Equatable {
    case complete
    case optional
    case required

    var tint: Color {
        switch self {
        case .complete: return .clear
        case .optional: return AppColors.warning
        case .required: return AppColors.error
        }
    }

    var message: String {
        switch self {
        case .complete:
            return ""
        case .optional:
            return L10n.string("profile.status.optional")
        case .required:
            return L10n.string("profile.status.required")
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .complete:
            return L10n.string("profile.status.complete")
        case .optional:
            return L10n.string("profile.status.optional.accessibility")
        case .required:
            return L10n.string("profile.status.required.accessibility")
        }
    }
}

extension CurrentUser {
    var initials: String { displayName.initials }
    var profileSubtitle: String {
        [city?.nonEmpty, occupation?.nonEmpty].compactMap { $0 }.joined(separator: " · ")
    }
    var ratingText: String {
        String(format: "%.1f", min(max(rating ?? 5, 1), 5))
    }
    var profileLocationText: String? {
        let values = [city?.nonEmpty, locationLabel?.nonEmpty].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return Array(NSOrderedSet(array: values)).compactMap { $0 as? String }.joined(separator: " · ")
    }
    var profileStatus: ProfileCompletionStatus {
        if profileComplete == false || birthDate == nil {
            return .required
        }
        if city?.nonEmpty == nil || occupation?.nonEmpty == nil || bio?.nonEmpty == nil || interests?.isEmpty != false {
            return .optional
        }
        return .complete
    }
    var isFreshProfile: Bool {
        birthDate == nil
            && city?.nonEmpty == nil
            && occupation?.nonEmpty == nil
            && bio?.nonEmpty == nil
            && interests?.isEmpty != false
            && relationshipStatus?.nonEmpty == nil
            && locationLabel?.nonEmpty == nil
    }
    var age: Int? {
        guard let birthDate, let date = ProfileDate.parse(birthDate) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }

    var birthDateAndAgeText: String? {
        guard let birthDate, let date = ProfileDate.parse(birthDate), let age else { return nil }
        return "\(ProfileDate.display(date)), \(L10n.age(age))"
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var nilIfEmpty: String? { nonEmpty }
    var initials: String {
        split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }
}
