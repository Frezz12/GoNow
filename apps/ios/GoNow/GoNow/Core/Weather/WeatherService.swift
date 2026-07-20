import Combine
import Foundation

enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case automatic
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: L10n.string("settings.temperature.automatic")
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    var apiValue: String {
        effective == .fahrenheit ? "fahrenheit" : "celsius"
    }

    var effective: TemperatureUnit {
        guard self == .automatic else { return self }
        return Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

struct WeatherSnapshot: Equatable {
    let city: String?
    let temperature: Double
    let unit: TemperatureUnit
    let condition: WeatherCondition
    let apparentTemperature: Double?
    let relativeHumidity: Double?
    let windSpeed: Double?

    var temperatureText: String {
        "\(Int(temperature.rounded()))°"
    }

    func apparentTemperatureText(_ suffix: String) -> String {
        guard let apparentTemperature else { return "—" }
        return "\(Int(apparentTemperature.rounded()))°\(suffix)"
    }

    var humidityText: String {
        guard let relativeHumidity else { return "—" }
        return "\(Int(relativeHumidity.rounded()))%"
    }

    var windText: String {
        guard let windSpeed else { return "—" }
        return Measurement(value: windSpeed, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .wind))
    }
}

enum WeatherCondition: Equatable {
    case clear(day: Bool)
    case partlyCloudy(day: Bool)
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm

    init(code: Int, isDay: Bool) {
        switch code {
        case 0: self = .clear(day: isDay)
        case 1, 2: self = .partlyCloudy(day: isDay)
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57: self = .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        default: self = .thunderstorm
        }
    }

    init(metSymbolCode: String) {
        let isDay = !metSymbolCode.contains("_night")

        if metSymbolCode.contains("thunder") {
            self = .thunderstorm
        } else if metSymbolCode.contains("snow") {
            self = .snow
        } else if metSymbolCode.contains("rain") || metSymbolCode.contains("sleet") {
            self = .rain
        } else if metSymbolCode.contains("fog") {
            self = .fog
        } else if metSymbolCode.contains("partlycloudy") || metSymbolCode.contains("fair") {
            self = .partlyCloudy(day: isDay)
        } else if metSymbolCode.contains("clearsky") {
            self = .clear(day: isDay)
        } else {
            self = .cloudy
        }
    }

    var title: String {
        switch self {
        case .clear: L10n.string("weather.condition.clear")
        case .partlyCloudy: L10n.string("weather.condition.partly_cloudy")
        case .cloudy: L10n.string("weather.condition.cloudy")
        case .fog: L10n.string("weather.condition.fog")
        case .drizzle: L10n.string("weather.condition.drizzle")
        case .rain: L10n.string("weather.condition.rain")
        case .snow: L10n.string("weather.condition.snow")
        case .thunderstorm: L10n.string("weather.condition.thunderstorm")
        }
    }

    var symbol: String {
        switch self {
        case .clear(let day): day ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy(let day): day ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "snowflake"
        case .thunderstorm: "cloud.bolt.rain.fill"
        }
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isUnavailable = false
    @Published private(set) var unavailableReason: WeatherUnavailableReason?

    private var lastRequest: (latitude: Double, longitude: Double, unit: TemperatureUnit, locale: String, date: Date)?
    private var requestGeneration = 0

    func refresh(latitude: Double?, longitude: Double?, unit: TemperatureUnit, locale: String) async {
        requestGeneration += 1
        let generation = requestGeneration
        guard let latitude, let longitude else {
            snapshot = nil
            isUnavailable = true
            unavailableReason = .locationUnavailable
            return
        }

        if let lastRequest,
           abs(lastRequest.latitude - latitude) < 0.001,
           abs(lastRequest.longitude - longitude) < 0.001,
           lastRequest.unit == unit.effective,
           lastRequest.locale == locale,
           Date().timeIntervalSince(lastRequest.date) < 600 {
            return
        }

        isLoading = true
        isUnavailable = false
        unavailableReason = nil
        defer {
            if generation == requestGeneration { isLoading = false }
        }

        do {
            let nextSnapshot = try await WeatherService.fetch(latitude: latitude, longitude: longitude, unit: unit.effective, locale: locale)
            guard !Task.isCancelled, generation == requestGeneration else { return }
            snapshot = nextSnapshot
            lastRequest = (latitude, longitude, unit.effective, locale, .now)
        } catch {
            guard !Task.isCancelled,
                  (error as? URLError)?.code != .cancelled,
                  generation == requestGeneration else { return }
            isUnavailable = true
            unavailableReason = WeatherUnavailableReason(error: error)
        }
    }
}

enum WeatherUnavailableReason: Equatable {
    case locationUnavailable
    case networkUnavailable
    case serviceUnavailable

    init(error: Error) {
        guard let urlError = error as? URLError else {
            self = .serviceUnavailable
            return
        }

        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut:
            self = .networkUnavailable
        default:
            self = .serviceUnavailable
        }
    }
}

private enum WeatherService {
    static func fetch(latitude: Double, longitude: Double, unit: TemperatureUnit, locale: String) async throws -> WeatherSnapshot {
        try await fetchViaGoNowBackend(latitude: latitude, longitude: longitude, unit: unit, locale: locale)
    }

    /// Weather providers are intentionally accessed only by the GoNow backend.
    /// This keeps provider DNS and VPN behaviour outside of the mobile client.
    private static func fetchViaGoNowBackend(latitude: Double, longitude: Double, unit: TemperatureUnit, locale: String) async throws -> WeatherSnapshot {
        var components = URLComponents(
            url: AppConfiguration.apiBaseURL.appendingPathComponent("weather/current"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "unit", value: unit.apiValue),
            URLQueryItem(name: "locale", value: locale)
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(GoNowWeatherResponse.self, from: data).data
        return WeatherSnapshot(
            city: payload.city,
            temperature: payload.temperature,
            unit: unit,
            condition: WeatherCondition(code: payload.weatherCode, isDay: payload.isDay),
            apparentTemperature: payload.apparentTemperature,
            relativeHumidity: payload.relativeHumidity,
            windSpeed: payload.windSpeed
        )
    }

}

private struct GoNowWeatherResponse: Decodable {
    let data: Data

    struct Data: Decodable {
        let city: String?
        let temperature: Double
        let apparentTemperature: Double
        let relativeHumidity: Double
        let windSpeed: Double
        let weatherCode: Int
        let isDay: Bool
    }
}
