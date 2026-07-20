import XCTest
@testable import GoNow

final class GoNowLocalizationTests: XCTestCase {
    func testSupportedInterfaceLanguagesHaveStableLocaleIdentifiers() {
        XCTAssertEqual(AppLanguage.allCases.count, 9)
        XCTAssertEqual(AppLanguage.englishUS.localeIdentifier, "en-US")
        XCTAssertEqual(AppLanguage.portugueseBrazil.localeIdentifier, "pt-BR")
        XCTAssertEqual(AppLanguage.chineseSimplified.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.german.requestLocaleIdentifier, "de")
        XCTAssertEqual(AppLanguage.portugueseBrazil.requestLocaleIdentifier, "pt-BR")
        XCTAssertEqual(AppLanguage.chineseSimplified.requestLocaleIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.resolve("unknown"), .english)
        XCTAssertEqual(AppLanguage.resolve(nil), .system)
    }

    func testFormattersUseLocaleAwareUnitsAndDates() {
        XCTAssertFalse(AppFormatters.distance(kilometers: 3.4, locale: Locale(identifier: "ru_RU")).isEmpty)
        XCTAssertFalse(AppFormatters.distance(kilometers: 3.4, locale: Locale(identifier: "en_US")).isEmpty)
        XCTAssertFalse(AppFormatters.profileDate(.now, locale: Locale(identifier: "de_DE")).isEmpty)
    }

    func testBackendCodeUsesSafeLocalizedFallback() {
        XCTAssertFalse(LocalizedBackendError.message(for: "INVALID_CREDENTIALS").isEmpty)
        XCTAssertFalse(LocalizedBackendError.message(for: "UNEXPECTED_CODE").isEmpty)
    }

    func testEverySupportedLocaleResolvesAnActualTranslation() {
        let expectedSettingsTitles = [
            "ru": "Настройки",
            "en": "Settings",
            "en-US": "Settings",
            "de": "Einstellungen",
            "fr": "Réglages",
            "es": "Ajustes",
            "pt-BR": "Ajustes",
            "zh-Hans": "设置",
        ]

        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: LocalizationManager.appStorageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: LocalizationManager.appStorageKey)
            } else {
                defaults.removeObject(forKey: LocalizationManager.appStorageKey)
            }
        }

        for language in AppLanguage.allCases where language != .system {
            guard let identifier = language.localeIdentifier,
                  let expected = expectedSettingsTitles[identifier] else {
                XCTFail("Missing test fixture for \(language)")
                continue
            }
            defaults.set(language.rawValue, forKey: LocalizationManager.appStorageKey)
            let value = L10n.string("settings.title")
            XCTAssertEqual(value, expected, "Incorrect translation for \(identifier)")
            XCTAssertNotEqual(value, "settings.title")
        }
    }

    func testProgrammaticStringsUseTheInAppLanguageChoice() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: LocalizationManager.appStorageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: LocalizationManager.appStorageKey)
            } else {
                defaults.removeObject(forKey: LocalizationManager.appStorageKey)
            }
        }

        defaults.set(AppLanguage.german.rawValue, forKey: LocalizationManager.appStorageKey)
        XCTAssertEqual(L10n.string("settings.title"), "Einstellungen")

        defaults.set(AppLanguage.chineseSimplified.rawValue, forKey: LocalizationManager.appStorageKey)
        XCTAssertEqual(L10n.string("settings.title"), "设置")

        defaults.set(AppLanguage.russian.rawValue, forKey: LocalizationManager.appStorageKey)
        XCTAssertEqual(L10n.format("profile.setup.progress %lld %lld", 2, 4), "Шаг 2 из 4")
        XCTAssertEqual(L10n.age(21), "21 год")
        XCTAssertEqual(L10n.age(22), "22 года")
        XCTAssertEqual(L10n.age(25), "25 лет")

        defaults.set(AppLanguage.german.rawValue, forKey: LocalizationManager.appStorageKey)
        XCTAssertEqual(L10n.age(1), "1 Jahr")
        XCTAssertEqual(L10n.age(20), "20 Jahre")
    }
}
