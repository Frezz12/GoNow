import CoreLocation
import SwiftUI

struct MapWeatherWidget: View {
    let profileLatitude: Double?
    let profileLongitude: Double?
    @ObservedObject var deviceLocation: DeviceLocationProvider

    @AppStorage("gonow.weather.temperature-unit") private var temperatureUnit: TemperatureUnit = .automatic
    @StateObject private var weather = WeatherViewModel()
    @EnvironmentObject private var localizationManager: LocalizationManager
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
                    Text("weather.title")
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
        .accessibilityHint(weather.snapshot == nil ? L10n.string("weather.loading.hint") : (isExpanded ? L10n.string("weather.details.hide") : L10n.string("weather.details.show")))
        .task(id: requestID) {
            await weather.refresh(
                latitude: weatherLatitude,
                longitude: weatherLongitude,
                unit: temperatureUnit,
                locale: localizationManager.selectedLanguage.requestLocaleIdentifier
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
                        title: L10n.string("weather.apparent_temperature"),
                        value: snapshot.apparentTemperatureText(unitSuffix)
                    )
                    WeatherDetailMetric(
                        symbol: "humidity.fill",
                        title: L10n.string("weather.humidity"),
                        value: snapshot.humidityText
                    )
                    WeatherDetailMetric(
                        symbol: "wind",
                        title: L10n.string("weather.wind"),
                        value: snapshot.windText
                    )
                }

                if snapshot.city != nil {
                    Text("weather.location.attribution")
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
        "\(weatherLatitude ?? 0)|\(weatherLongitude ?? 0)|\(temperatureUnit.rawValue)|\(localizationManager.selectedLanguage.requestLocaleIdentifier)"
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
        deviceLocation.coordinate == nil
            ? L10n.string("location.current.short")
            : L10n.string("location.current")
    }

    private var unitSuffix: String {
        temperatureUnit.effective == .celsius ? "C" : "F"
    }

    private var placeholderTitle: String {
        if deviceLocation.isRequesting && profileLatitude == nil && profileLongitude == nil {
            return L10n.string("location.resolving")
        }
        if weatherLatitude == nil || weatherLongitude == nil { return L10n.string("location.permission.required") }
        if weather.unavailableReason == .networkUnavailable { return L10n.string("network.offline") }
        return L10n.string("weather.unavailable")
    }

    private var placeholderSymbol: String {
        if deviceLocation.isRequesting { return "location.fill" }
        if weatherLatitude == nil || weatherLongitude == nil { return "location.slash" }
        return "cloud.fill"
    }

    private var accessibilityLabel: String {
        guard let snapshot = weather.snapshot else {
            if deviceLocation.isRequesting && profileLatitude == nil && profileLongitude == nil {
                return L10n.string("weather.location.resolving")
            }
            if weatherLatitude == nil || weatherLongitude == nil {
                return L10n.string("weather.location.permission")
            }
            if weather.unavailableReason == .networkUnavailable {
                return L10n.string("weather.network.error")
            }
            return weather.isUnavailable ? L10n.string("weather.unavailable") : L10n.string("weather.loading")
        }
        let unitText = snapshot.unit == .celsius
            ? L10n.string("temperature.celsius")
            : L10n.string("temperature.fahrenheit")
        return L10n.string("weather.accessibility.summary \(snapshot.condition.title) \(snapshot.temperatureText) \(unitText)")
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
