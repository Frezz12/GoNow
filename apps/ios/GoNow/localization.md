# GoNow localization

The iOS client uses `Localization/Localizable.xcstrings` with stable semantic keys. English is the development language. Every catalog key has an explicit value for `ru`, `en`, `en-US`, `de`, `fr`, `es`, `pt-BR`, and `zh-Hans`; release UI must never depend on a fallback or expose a key to the user.

`AppLanguage` represents the interface choice. `LocalizationManager` persists it in app storage and injects its `Locale` into SwiftUI, so a selection takes effect immediately. `L10n` applies the same selected locale to strings created programmatically, such as validation errors, enum titles, accessibility labels, dates shown as localized text, and pluralized age values. System mode follows the device language. Region-dependent choices, such as the automatic Celsius/Fahrenheit mode, continue to follow the device region.

Backend error codes are mapped by `LocalizedBackendError`; the server message is not shown directly. User-provided data, such as names, cities, and activity descriptions, must never be translated.

The current API does not expose a preferred-locale field. `AppLanguage.preferredLocaleValue` is the single value to send when that contract is added; system mode stays local-only. This keeps server-driven messages and push-notification localization independent from the UI migration.

Run `sh apps/ios/GoNow/tools/check_localizations.sh` from the repository root before review. It checks both catalogs and rejects a key if any of the eight locales is missing or empty, if the visible value exposes a semantic key, or if a translation loses an interpolation placeholder.
