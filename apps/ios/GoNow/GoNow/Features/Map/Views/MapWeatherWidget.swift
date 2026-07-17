import CoreLocation
import SwiftUI

struct MapWeatherWidget: View {
    let profileLatitude: Double?
    let profileLongitude: Double?

    @AppStorage("gonow.weather.temperature-unit") private var temperatureUnit: TemperatureUnit = .automatic
    @StateObject private var weather = WeatherViewModel()
    @StateObject private var deviceLocation = DeviceLocationProvider()

    var body: some View {
        Group {
            if let snapshot = weather.snapshot {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: snapshot.condition.symbol)
                        .font(.title3.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColors.warning)
                        .frame(width: 28)
                    Text(snapshot.temperatureText + (snapshot.unit == .celsius ? "C" : "F"))
                        .font(AppTypography.bodyMedium.monospacedDigit())
                        .foregroundStyle(AppColors.textPrimary)
                }
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
        .frame(minHeight: AppLayout.minimumTouchTarget)
        .glassSurface(.floating, cornerRadius: AppRadius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .task {
            deviceLocation.requestCurrentLocation()
        }
        .task(id: requestID) {
            await weather.refresh(
                latitude: weatherLatitude,
                longitude: weatherLongitude,
                unit: temperatureUnit
            )
        }
    }

    private var requestID: String {
        "\(weatherLatitude ?? 0)|\(weatherLongitude ?? 0)|\(temperatureUnit.rawValue)"
    }

    /// The live device coordinate takes priority. Profile location is a fallback when access is unavailable.
    private var weatherLatitude: Double? {
        deviceLocation.coordinate?.latitude ?? profileLatitude
    }

    private var weatherLongitude: Double? {
        deviceLocation.coordinate?.longitude ?? profileLongitude
    }

    private var placeholderTitle: String {
        if deviceLocation.isRequesting { return "Определяем место" }
        if deviceLocation.authorizationStatus == .denied || deviceLocation.authorizationStatus == .restricted {
            return "Геопозиция отключена"
        }
        if weather.unavailableReason == .networkUnavailable { return "Нет подключения" }
        return "Погода недоступна"
    }

    private var placeholderSymbol: String {
        if deviceLocation.isRequesting { return "location.fill" }
        if deviceLocation.authorizationStatus == .denied || deviceLocation.authorizationStatus == .restricted {
            return "location.slash"
        }
        return "cloud.fill"
    }

    private var accessibilityLabel: String {
        guard let snapshot = weather.snapshot else {
            if deviceLocation.isRequesting { return "Определяем геопозицию для погоды" }
            if deviceLocation.authorizationStatus == .denied || deviceLocation.authorizationStatus == .restricted {
                return "Геопозиция отключена. Разрешите доступ в настройках iPhone."
            }
            if weather.unavailableReason == .networkUnavailable {
                return "Нет подключения к сервису погоды. Проверьте интернет или настройки VPN."
            }
            return weather.isUnavailable ? "Погода недоступна." : "Загрузка погоды"
        }
        return "Погода: \(snapshot.condition.title), \(snapshot.temperatureText) градусов \(snapshot.unit == .celsius ? "Цельсия" : "Фаренгейта")"
    }
}
