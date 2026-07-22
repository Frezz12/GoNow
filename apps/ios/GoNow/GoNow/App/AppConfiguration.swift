import Foundation

enum AppConfiguration {
    private static let localAPIBaseURL = "http://127.0.0.1:8080/api/v1"
    private static let environmentKey = "GONOW_API_BASE_URL"

    static var apiBaseURL: URL {
        let candidates = [
            bundledEnvironmentValue,
            ProcessInfo.processInfo.environment[environmentKey],
            localAPIBaseURL
        ]
        for candidate in candidates {
            if let url = validatedURL(candidate) { return url }
        }
        preconditionFailure("GoNow API base URL is invalid")
    }

    private static var bundledEnvironmentValue: String? {
        guard let fileURL = Bundle.main.url(forResource: "API", withExtension: "env"),
              let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return contents
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("\(environmentKey)=") }
            .map { String($0.dropFirst(environmentKey.count + 1)) }
    }

    private static func validatedURL(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}
