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

    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "d MMMM"
        return formatter
    }()
}

enum ProfileCompletionStatus: Equatable {
    case complete
    case optional
    case required

    var tint: Color {
        switch self {
        case .complete: return .clear
        case .optional: return .orange
        case .required: return .red
        }
    }

    var message: String {
        switch self {
        case .complete:
            return ""
        case .optional:
            return "Добавьте немного информации, чтобы люди больше узнали о вас."
        case .required:
            return "Укажите дату рождения, чтобы создавать задания и подавать заявки."
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .complete:
            return "Профиль заполнен"
        case .optional:
            return "Есть необязательные незаполненные поля"
        case .required:
            return "Не заполнено обязательное поле: дата рождения"
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
        return "\(ProfileDate.displayFormatter.string(from: date)), \(age) \(age.russianYears)"
    }
}

private extension Int {
    var russianYears: String {
        let remainder100 = self % 100
        let remainder10 = self % 10
        if (11...14).contains(remainder100) { return "лет" }
        switch remainder10 {
        case 1: return "год"
        case 2...4: return "года"
        default: return "лет"
        }
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
