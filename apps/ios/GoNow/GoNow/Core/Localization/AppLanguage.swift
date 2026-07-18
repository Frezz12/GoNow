import Combine
import Foundation
import SwiftUI

private enum LocalizationStorage {
    static let languageKey = "gonow.settings.interface-language"
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case russian
    case english
    case englishUS
    case german
    case french
    case spanish
    case portugueseBrazil
    case chineseSimplified

    var id: String { rawValue }

    /// `nil` means that the app follows the language selected by the operating system.
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .russian: "ru"
        case .english: "en"
        case .englishUS: "en-US"
        case .german: "de"
        case .french: "fr"
        case .spanish: "es"
        case .portugueseBrazil: "pt-BR"
        case .chineseSimplified: "zh-Hans"
        }
    }

    /// A localized description for system mode and the language's own name for explicit choices.
    var displayName: String {
        switch self {
        case .system: L10n.string("settings.language.system")
        default: nativeDisplayName
        }
    }

    /// Language names intentionally remain in their native form so the option is discoverable
    /// after the interface is switched to an unfamiliar language.
    var nativeDisplayName: String {
        switch self {
        case .system: L10n.string("settings.language.system")
        case .russian: "Русский"
        case .english: "English"
        case .englishUS: "English (United States)"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .portugueseBrazil: "Português (Brasil)"
        case .chineseSimplified: "简体中文"
        }
    }

    var locale: Locale {
        guard let localeIdentifier else { return .autoupdatingCurrent }
        return Locale(identifier: localeIdentifier)
    }

    /// Value safe to send to a server. System mode remains local-only and is not synced.
    var preferredLocaleValue: String? { localeIdentifier }

    /// Locale sent with requests whose payload contains localized provider data.
    var requestLocaleIdentifier: String {
        if let localeIdentifier { return localeIdentifier }

        switch Locale.autoupdatingCurrent.language.languageCode?.identifier {
        case "ru": return "ru"
        case "de": return "de"
        case "fr": return "fr"
        case "es": return "es"
        case "pt": return "pt-BR"
        case "zh": return "zh-Hans"
        case "en" where Locale.autoupdatingCurrent.region?.identifier == "US": return "en-US"
        default: return "en"
        }
    }

    static func resolve(_ identifier: String?) -> AppLanguage {
        guard let identifier else { return .system }
        return AppLanguage.allCases.first(where: { $0.localeIdentifier == identifier }) ?? .english
    }
}

enum L10n {
    static var language: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: LocalizationStorage.languageKey)
        return AppLanguage(rawValue: stored ?? AppLanguage.system.rawValue) ?? .system
    }

    static var locale: Locale {
        language.locale
    }

    static func string(_ key: String) -> String {
        localizationBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    private static var localizationBundle: Bundle {
        guard let identifier = language.localeIdentifier else { return .main }

        let baseIdentifier = Locale(identifier: identifier).language.languageCode?.identifier
        let candidates = [identifier, baseIdentifier].compactMap { $0 }
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }

    static func age(_ value: Int) -> String {
        let category: String
        switch language {
        case .russian:
            let lastTwoDigits = value % 100
            if value % 10 == 1, lastTwoDigits != 11 {
                category = "one"
            } else if (2...4).contains(value % 10), !(12...14).contains(lastTwoDigits) {
                category = "few"
            } else {
                category = "other"
            }
        case .chineseSimplified:
            category = "other"
        case .system:
            let languageCode = Locale.autoupdatingCurrent.language.languageCode?.identifier
            if languageCode == "ru" {
                let lastTwoDigits = value % 100
                if value % 10 == 1, lastTwoDigits != 11 {
                    category = "one"
                } else if (2...4).contains(value % 10), !(12...14).contains(lastTwoDigits) {
                    category = "few"
                } else {
                    category = "other"
                }
            } else {
                category = value == 1 ? "one" : "other"
            }
        default:
            category = value == 1 ? "one" : "other"
        }
        return format("profile.age.\(category) %lld", value)
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    nonisolated static let appStorageKey = LocalizationStorage.languageKey

    @AppStorage("gonow.settings.interface-language") private var storedLanguageIdentifier: String = AppLanguage.system.rawValue

    var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: storedLanguageIdentifier) ?? .system
    }

    /// This locale is injected into SwiftUI and updates translated text immediately.
    var locale: Locale { selectedLanguage.locale }

    /// Formatting deliberately follows the device region, independently from interface language.
    var formattingLocale: Locale { .autoupdatingCurrent }

    func select(_ language: AppLanguage) {
        guard selectedLanguage != language else { return }
        objectWillChange.send()
        storedLanguageIdentifier = language.rawValue
        AppHaptics.selection()
    }
}

enum LocalizedBackendError {
    static func message(for code: String) -> String {
        let key: String = switch code {
        case "INVALID_CREDENTIALS": "error.auth.invalid_credentials"
        case "UNAUTHORIZED": "error.auth.unauthorized"
        case "EMAIL_ALREADY_EXISTS": "error.auth.email_exists"
        case "VALIDATION_ERROR": "error.validation"
        case "ACTIVITY_FULL": "error.activity.full"
        default: "error.server.generic"
        }
        return L10n.string(key)
    }
}

enum AppFormatters {
    static func distance(kilometers: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let useImperial = locale.measurementSystem == .us
        let measurement = useImperial
            ? Measurement(value: kilometers * 0.621_371, unit: UnitLength.miles)
            : Measurement(value: kilometers, unit: UnitLength.kilometers)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road))
    }

    static func profileDate(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.locale(locale).day().month().year())
    }
}
