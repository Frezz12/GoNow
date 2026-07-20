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
    let username: String
    let device: DevicePayload
}

struct LoginPayload: Codable, Sendable {
    let email: String
    let password: String
    let device: DevicePayload
}

struct RefreshPayload: Codable, Sendable { let refreshToken: String }
struct LogoutPayload: Codable, Sendable { let refreshToken: String }
struct VerifyEmailPayload: Codable, Sendable { let email: String; let code: String; let device: DevicePayload }
struct ForgotPasswordPayload: Codable, Sendable { let email: String }
struct ResetPasswordPayload: Codable, Sendable { let email: String; let code: String; let password: String; let device: DevicePayload }
struct UpdateProfilePayload: Codable, Sendable {
    let displayName: String
    let username: String
    let birthDate: String?
    let city: String?
    let occupation: String?
    let bio: String?
    let interests: [String]
    let languages: [String]
    let availability: String?
    let preferredGroupSize: String?
    let relationshipStatus: String?
    let locationLabel: String?
    let latitude: Double?
    let longitude: Double?
    let showDistance: Bool
}

struct ProfilePhoto: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let contentType: String
    let bytes: Int
    let createdAt: Date
    let contentPath: String
    let isAvatar: Bool
    let isCurrentAvatar: Bool
    let description: String?
    let likeCount: Int
    let isLiked: Bool

    private enum CodingKeys: String, CodingKey {
        case id, contentType, bytes, createdAt, contentPath, isAvatar, isCurrentAvatar, description, likeCount, isLiked
    }

    init(
        id: UUID,
        contentType: String,
        bytes: Int,
        createdAt: Date,
        contentPath: String,
        isAvatar: Bool,
        isCurrentAvatar: Bool,
        description: String?,
        likeCount: Int,
        isLiked: Bool
    ) {
        self.id = id
        self.contentType = contentType
        self.bytes = bytes
        self.createdAt = createdAt
        self.contentPath = contentPath
        self.isAvatar = isAvatar
        self.isCurrentAvatar = isCurrentAvatar
        self.description = description
        self.likeCount = likeCount
        self.isLiked = isLiked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        contentType = try container.decode(String.self, forKey: .contentType)
        bytes = try container.decode(Int.self, forKey: .bytes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        contentPath = try container.decode(String.self, forKey: .contentPath)
        isAvatar = try container.decodeIfPresent(Bool.self, forKey: .isAvatar) ?? false
        isCurrentAvatar = try container.decodeIfPresent(Bool.self, forKey: .isCurrentAvatar) ?? false
        description = try container.decodeIfPresent(String.self, forKey: .description)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        isLiked = try container.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false
    }

    func updating(description: String?) -> ProfilePhoto {
        ProfilePhoto(
            id: id,
            contentType: contentType,
            bytes: bytes,
            createdAt: createdAt,
            contentPath: contentPath,
            isAvatar: isAvatar,
            isCurrentAvatar: isCurrentAvatar,
            description: description,
            likeCount: likeCount,
            isLiked: isLiked
        )
    }

    func updating(likeCount: Int, isLiked: Bool) -> ProfilePhoto {
        copy(likeCount: max(0, likeCount), isLiked: isLiked)
    }

    private func copy(likeCount: Int? = nil, isLiked: Bool? = nil) -> ProfilePhoto {
        ProfilePhoto(
            id: id,
            contentType: contentType,
            bytes: bytes,
            createdAt: createdAt,
            contentPath: contentPath,
            isAvatar: isAvatar,
            isCurrentAvatar: isCurrentAvatar,
            description: description,
            likeCount: likeCount ?? self.likeCount,
            isLiked: isLiked ?? self.isLiked
        )
    }
}

struct ProfilePhotos: Codable, Sendable {
    let avatar: ProfilePhoto?
    let avatars: [ProfilePhoto]
    let photos: [ProfilePhoto]

    init(avatar: ProfilePhoto?, avatars: [ProfilePhoto] = [], photos: [ProfilePhoto]) {
        self.avatar = avatar
        self.avatars = avatars
        self.photos = photos
    }

    private enum CodingKeys: String, CodingKey { case avatar, avatars, photos }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        avatar = try container.decodeIfPresent(ProfilePhoto.self, forKey: .avatar)
        avatars = try container.decodeIfPresent([ProfilePhoto].self, forKey: .avatars) ?? avatar.map { [$0] } ?? []
        photos = try container.decode([ProfilePhoto].self, forKey: .photos)
    }

    func replacing(_ photo: ProfilePhoto) -> ProfilePhotos {
        ProfilePhotos(
            avatar: avatar?.id == photo.id ? photo : avatar,
            avatars: avatars.map { $0.id == photo.id ? photo : $0 },
            photos: photos.map { $0.id == photo.id ? photo : $0 }
        )
    }
}
struct RegistrationData: Codable, Sendable { let email: String; let verificationRequired: Bool; let expiresAt: Date }

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
    let username: String
    let emailVerified: Bool
    let birthDate: String?
    let city: String?
    let occupation: String?
    let bio: String?
    let interests: [String]?
    let languages: [String]?
    let availability: String?
    let preferredGroupSize: String?
    let rating: Double?
    let relationshipStatus: String?
    let locationLabel: String?
    let latitude: Double?
    let longitude: Double?
    let showDistance: Bool?
    let profileComplete: Bool?
    let createdAt: Date
}

struct UsernameAvailability: Codable, Sendable, Equatable {
    let username: String
    let available: Bool
    let message: String?
}

enum UsernameRules {
    static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return String(trimmed.drop(while: { $0 == "@" }))
    }

    static func validationMessage(_ username: String) -> String? {
        guard (5...32).contains(username.count) else {
            return "Username должен содержать от 5 до 32 символов"
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        guard username.unicodeScalars.allSatisfy(allowed.contains),
              let first = username.unicodeScalars.first,
              (97...122).contains(first.value) else {
            return "Используйте латинские буквы, цифры и знак подчёркивания; первый символ — буква"
        }
        if ["admin", "administrator", "support", "gonow", "official", "system"].contains(username) {
            return "Этот username зарезервирован"
        }
        return nil
    }
}
