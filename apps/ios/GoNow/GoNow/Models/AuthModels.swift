import Foundation

struct APIEnvelope<Value: Decodable>: Decodable { let data: Value }

struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
}

struct APIErrorBody: Decodable {
    let code: String
    let message: String
    let fields: [String: String]?
    let requestId: String
}

struct DevicePayload: Codable, Sendable {
    let deviceId: String
    let deviceName: String
    let platform: String
}

struct RegisterPayload: Codable, Sendable {
    let email: String
    let password: String
    let displayName: String
    let device: DevicePayload
}

struct LoginPayload: Codable, Sendable {
    let email: String
    let password: String
    let device: DevicePayload
}

struct RefreshPayload: Codable, Sendable { let refreshToken: String }
struct LogoutPayload: Codable, Sendable { let refreshToken: String }

struct AuthData: Codable, Sendable {
    let user: CurrentUser
    let tokens: TokenSet
}

struct TokenSet: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
}

struct CurrentUser: Codable, Sendable, Equatable {
    let id: UUID
    let email: String
    let displayName: String
    let emailVerified: Bool
    let createdAt: Date
}
