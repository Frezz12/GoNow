import Foundation

enum AppConfiguration {
    static var apiBaseURL: URL {
        let value = Bundle.main.object(forInfoDictionaryKey: "GoNowAPIBaseURL") as? String
        return URL(string: value ?? "http://127.0.0.1:8080/api/v1") ?? URL(fileURLWithPath: "/")
    }
}
