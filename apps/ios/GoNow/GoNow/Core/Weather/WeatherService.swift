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

    private var lastRequest: (latitude: Double, longitude: Double, unit: TemperatureUnit, date: Date)?

    func refresh(latitude: Double?, longitude: Double?, unit: TemperatureUnit) async {
        guard let latitude, let longitude else {
            snapshot = nil
            isUnavailable = true
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
        defer { isLoading = false }

        do {
            snapshot = try await WeatherService.fetch(latitude: latitude, longitude: longitude, unit: unit.effective)
            lastRequest = (latitude, longitude, unit.effective, .now)
        } catch {
            isUnavailable = true
        }
    }
}

private enum WeatherService {
    static func fetch(latitude: Double, longitude: Double, unit: TemperatureUnit) async throws -> WeatherSnapshot {
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
