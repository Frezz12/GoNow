#if DEBUG
import SwiftUI

struct LocalizationDebugView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        List {
            Section("debug.localization.section") {
                LabeledContent("debug.localization.language", value: localizationManager.selectedLanguage.nativeDisplayName)
                LabeledContent("debug.localization.interface_locale", value: localizationManager.locale.identifier)
                LabeledContent("debug.localization.format_locale", value: localizationManager.formattingLocale.identifier)
                LabeledContent("debug.localization.region", value: localizationManager.formattingLocale.region?.identifier ?? "—")
                LabeledContent("debug.localization.time_zone", value: TimeZone.autoupdatingCurrent.identifier)
                LabeledContent("debug.localization.distance", value: AppFormatters.distance(kilometers: 3.4, locale: localizationManager.formattingLocale))
                LabeledContent("debug.localization.date", value: AppFormatters.profileDate(.now, locale: localizationManager.formattingLocale))
            }

            Section("debug.localization.supported_locales") {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeDisplayName)
                }
            }
        }
        .navigationTitle("debug.localization.title")
    }
}
#endif
