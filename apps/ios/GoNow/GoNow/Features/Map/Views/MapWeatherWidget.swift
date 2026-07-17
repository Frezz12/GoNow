import SwiftUI

struct MapWeatherWidget: View {
    let latitude: Double?
    let longitude: Double?

    @AppStorage("gonow.weather.temperature-unit") private var temperatureUnit: TemperatureUnit = .automatic
    @StateObject private var weather = WeatherViewModel()

    var body: some View {
        Group {
            if let snapshot = weather.snapshot {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: snapshot.condition.symbol)
                        .font(.title3.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColors.warning)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(snapshot.condition.title)
                            .font(AppTypography.captionStrong)
                        Text(snapshot.temperatureText + (snapshot.unit == .celsius ? "C" : "F"))
                            .font(AppTypography.bodyMedium.monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            } else if weather.isLoading {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Погода")
                        .font(AppTypography.captionStrong)
                }
            } else {
                Label("Укажите место", systemImage: "location.slash")
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: AppLayout.minimumTouchTarget)
        .glassSurface(.floating, cornerRadius: AppRadius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .task(id: requestID) {
            await weather.refresh(latitude: latitude, longitude: longitude, unit: temperatureUnit)
        }
    }

    private var requestID: String {
        "\(latitude ?? 0)|\(longitude ?? 0)|\(temperatureUnit.rawValue)"
    }

    private var accessibilityLabel: String {
        guard let snapshot = weather.snapshot else {
            return weather.isUnavailable ? "Погода недоступна. Укажите место в профиле." : "Загрузка погоды"
        }
        return "Погода: \(snapshot.condition.title), \(snapshot.temperatureText) градусов \(snapshot.unit == .celsius ? "Цельсия" : "Фаренгейта")"
    }
}
