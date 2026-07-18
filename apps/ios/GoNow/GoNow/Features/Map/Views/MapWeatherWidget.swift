import CoreLocation
import SwiftUI

struct MapWeatherWidget: View {
    let profileLatitude: Double?
    let profileLongitude: Double?
    let profileLocationLabel: String?

    @AppStorage("gonow.weather.temperature-unit") private var temperatureUnit: TemperatureUnit = .automatic
    @StateObject private var weather = WeatherViewModel()
    @StateObject private var deviceLocation = DeviceLocationProvider()
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : AppAnimation.standard) {
                isExpanded.toggle()
            }
        } label: {
            if let snapshot = weather.snapshot {
                weatherContent(snapshot)
            } else if weather.isLoading {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Погода")
                        .font(AppTypography.captionStrong)
                }
            } else {
                Label(placeholderTitle, systemImage: placeholderSymbol)
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, isExpanded && weather.snapshot != nil ? AppSpacing.sm : 0)
        .frame(minHeight: AppLayout.minimumTouchTarget)
        .glassSurface(.floating, cornerRadius: AppRadius.control)
        .buttonStyle(AppPressButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(weather.snapshot == nil ? "Ожидайте загрузки погоды" : (isExpanded ? "Скрыть подробности погоды" : "Показать подробности погоды"))
        .task {
            deviceLocation.startMonitoringLocation()
        }
        .onDisappear { deviceLocation.stopMonitoringLocation() }
        .task(id: requestID) {
            await weather.refresh(
                latitude: weatherLatitude,
                longitude: weatherLongitude,
                unit: temperatureUnit
            )
        }
    }

    @ViewBuilder
    private func weatherContent(_ snapshot: WeatherSnapshot) -> some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: snapshot.condition.symbol)
                        .font(.title2.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColors.warning)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(snapshot.city ?? cityName)
                            .font(AppTypography.captionStrong)
                            .lineLimit(1)
                        Text(snapshot.condition.title)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: AppSpacing.sm)

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        Text(snapshot.temperatureText + unitSuffix)
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                }

                Divider().overlay(AppColors.divider)

                HStack(spacing: AppSpacing.md) {
                    WeatherDetailMetric(
                        symbol: "thermometer.medium",
                        title: "Ощущается",
                        value: snapshot.apparentTemperatureText(unitSuffix)
                    )
                    WeatherDetailMetric(
                        symbol: "humidity.fill",
                        title: "Влажность",
                        value: snapshot.humidityText
                    )
                    WeatherDetailMetric(
                        symbol: "wind",
                        title: "Ветер",
                        value: snapshot.windText
                    )
                }

                if snapshot.city != nil {
                    Text("Данные места © OpenStreetMap contributors")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .frame(minWidth: 246, alignment: .leading)
        } else {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: snapshot.condition.symbol)
                    .font(.title3.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColors.warning)
                    .frame(width: 28)
                Text(snapshot.temperatureText + unitSuffix)
                    .font(AppTypography.bodyMedium.monospacedDigit())
            }
        }
    }

    private var requestID: String {
        "\(weatherLatitude ?? 0)|\(weatherLongitude ?? 0)|\(temperatureUnit.rawValue)"
    }

    /// The device coordinate is collected by Core Location and sent only to the GoNow API.
    /// A saved profile point keeps the weather widget useful after location access is denied.
    private var weatherLatitude: Double? {
        deviceLocation.coordinate?.latitude ?? profileLatitude
    }

    private var weatherLongitude: Double? {
        deviceLocation.coordinate?.longitude ?? profileLongitude
    }

    private var cityName: String {
        if deviceLocation.coordinate != nil {
            if let locality = deviceLocation.locality {
                return locality
            }
            return deviceLocation.isResolvingLocality ? "Определяем город…" : "Текущее местоположение"
        }
        return profileLocationLabel ?? "Текущее место"
    }

    private var unitSuffix: String {
        temperatureUnit.effective == .celsius ? "C" : "F"
    }

    private var placeholderTitle: String {
        if deviceLocation.isRequesting && profileLatitude == nil && profileLongitude == nil {
            return "Определяем место"
        }
        if weatherLatitude == nil || weatherLongitude == nil { return "Разрешите геолокацию" }
        if weather.unavailableReason == .networkUnavailable { return "Нет подключения" }
        return "Погода недоступна"
    }

    private var placeholderSymbol: String {
        if deviceLocation.isRequesting { return "location.fill" }
        if weatherLatitude == nil || weatherLongitude == nil { return "location.slash" }
        return "cloud.fill"
    }

    private var accessibilityLabel: String {
        guard let snapshot = weather.snapshot else {
            if deviceLocation.isRequesting && profileLatitude == nil && profileLongitude == nil {
                return "Определяем геопозицию для погоды."
            }
            if weatherLatitude == nil || weatherLongitude == nil {
                return "Разрешите доступ к геопозиции, чтобы показывать погоду."
            }
            if weather.unavailableReason == .networkUnavailable {
                return "Нет подключения к сервису погоды. Проверьте интернет или настройки VPN."
            }
            return weather.isUnavailable ? "Погода недоступна." : "Загрузка погоды"
        }
        return "Погода: \(snapshot.condition.title), \(snapshot.temperatureText) градусов \(snapshot.unit == .celsius ? "Цельсия" : "Фаренгейта")"
    }
}

private struct WeatherDetailMetric: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accentPrimary)
            Text(value)
                .font(AppTypography.captionStrong.monospacedDigit())
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
