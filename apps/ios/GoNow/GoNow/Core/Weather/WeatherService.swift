import Combine
import Foundation

enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case automatic
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Авто"
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
    let temperature: Double
    let unit: TemperatureUnit
    let condition: WeatherCondition

    var temperatureText: String {
        "\(Int(temperature.rounded()))°"
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
        case .clear: "Солнечно"
        case .partlyCloudy: "Облачно"
        case .cloudy: "Пасмурно"
        case .fog: "Туман"
        case .drizzle: "Морось"
        case .rain: "Дождь"
        case .snow: "Снег"
        case .thunderstorm: "Гроза"
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

    private var lastRequest: (latitude: Double, longitude: Double, unit: TemperatureUnit, date: Date)?

    func refresh(latitude: Double?, longitude: Double?, unit: TemperatureUnit) async {
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
           Date().timeIntervalSince(lastRequest.date) < 600 {
            return
        }

        isLoading = true
        isUnavailable = false
        unavailableReason = nil
        defer { isLoading = false }

        do {
            snapshot = try await WeatherService.fetch(latitude: latitude, longitude: longitude, unit: unit.effective)
            lastRequest = (latitude, longitude, unit.effective, .now)
        } catch {
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
    static func fetch(latitude: Double, longitude: Double, unit: TemperatureUnit) async throws -> WeatherSnapshot {
        do {
            return try await fetchViaGoNowBackend(latitude: latitude, longitude: longitude, unit: unit)
        } catch {
            do {
                return try await fetchOpenMeteo(latitude: latitude, longitude: longitude, unit: unit)
            } catch let error as URLError where shouldTryFallback(for: error) {
                return try await fetchMetNorway(latitude: latitude, longitude: longitude, unit: unit)
            }
        }
    }

    /// Uses the GoNow server first so a simulator's VPN/DNS configuration cannot block weather updates.
    private static func fetchViaGoNowBackend(latitude: Double, longitude: Double, unit: TemperatureUnit) async throws -> WeatherSnapshot {
        var components = URLComponents(
            url: AppConfiguration.apiBaseURL.appendingPathComponent("weather/current"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "unit", value: unit.apiValue)
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
            temperature: payload.temperature,
            unit: unit,
            condition: WeatherCondition(code: payload.weatherCode, isDay: payload.isDay)
        )
    }

    private static func fetchOpenMeteo(latitude: Double, longitude: Double, unit: TemperatureUnit) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: unit.apiValue),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return WeatherSnapshot(
            temperature: payload.current.temperature,
            unit: unit,
            condition: WeatherCondition(code: payload.current.weatherCode, isDay: payload.current.isDay == 1)
        )
    }

    /// A second provider makes the map widget resilient to VPNs that cannot resolve Open-Meteo's host.
    private static func fetchMetNorway(latitude: Double, longitude: Double, unit: TemperatureUnit) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude))
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("GoNow/1.0 (https://github.com/Frezz12/GoNow)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(MetNorwayResponse.self, from: data)
        guard let current = payload.properties.timeSeries.first else { throw URLError(.cannotParseResponse) }

        let celsius = current.data.instant.details.airTemperature
        let temperature = unit == .fahrenheit ? (celsius * 9 / 5) + 32 : celsius
        let symbol = current.data.nextOneHour?.summary.symbolCode
            ?? current.data.nextSixHours?.summary.symbolCode
            ?? current.data.nextTwelveHours?.summary.symbolCode
            ?? "cloudy"

        return WeatherSnapshot(
            temperature: temperature,
            unit: unit,
            condition: WeatherCondition(metSymbolCode: symbol)
        )
    }

    private static func shouldTryFallback(for error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut:
            true
        default:
            false
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }
}

private struct GoNowWeatherResponse: Decodable {
    let data: Data

    struct Data: Decodable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Bool
    }
}

private struct MetNorwayResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let timeSeries: [TimeSeries]

        enum CodingKeys: String, CodingKey {
            case timeSeries = "timeseries"
        }
    }

    struct TimeSeries: Decodable {
        let data: DataPoint
    }

    struct DataPoint: Decodable {
        let instant: Instant
        let nextOneHour: Forecast?
        let nextSixHours: Forecast?
        let nextTwelveHours: Forecast?

        enum CodingKeys: String, CodingKey {
            case instant
            case nextOneHour = "next_1_hours"
            case nextSixHours = "next_6_hours"
            case nextTwelveHours = "next_12_hours"
        }
    }

    struct Instant: Decodable {
        let details: Details
    }

    struct Details: Decodable {
        let airTemperature: Double

        enum CodingKeys: String, CodingKey {
            case airTemperature = "air_temperature"
        }
    }

    struct Forecast: Decodable {
        let summary: Summary
    }

    struct Summary: Decodable {
        let symbolCode: String

        enum CodingKeys: String, CodingKey {
            case symbolCode = "symbol_code"
        }
    }
}
