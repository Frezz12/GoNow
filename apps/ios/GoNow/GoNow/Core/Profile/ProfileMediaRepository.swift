import Foundation

actor ProfileMediaRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list() async throws -> ProfilePhotos {
        let response: APIEnvelope<ProfilePhotos> = try await api.get("users/me/photos")
        return response.data
    }

    func uploadAvatar(_ imageData: Data) async throws -> ProfilePhoto {
        let response: APIEnvelope<ProfilePhoto> = try await api.uploadImage("users/me/avatar", imageData: imageData)
        await api.cacheData(imageData, for: response.data.contentPath)
        return response.data
    }

    func uploadPhoto(_ imageData: Data) async throws -> ProfilePhoto {
        let response: APIEnvelope<ProfilePhoto> = try await api.uploadImage("users/me/photos", imageData: imageData)
        await api.cacheData(imageData, for: response.data.contentPath)
        return response.data
    }

    func content(for photo: ProfilePhoto) async throws -> Data {
        try await api.getData(photo.contentPath)
    }

    func delete(_ photo: ProfilePhoto) async throws {
        try await api.delete("users/me/photos/\(photo.id.uuidString)")
        await api.removeCachedData(for: photo.contentPath)
    }

    func clearCache() async { await api.clearSessionCaches() }

    func updateDescription(_ description: String?, for photo: ProfilePhoto) async throws -> ProfilePhoto {
        let response: APIEnvelope<ProfilePhoto> = try await api.patch(
            "users/me/photos/\(photo.id.uuidString)",
            body: UpdateProfilePhotoPayload(description: description)
        )
        return response.data
    }

    func setLiked(_ liked: Bool, for photo: ProfilePhoto) async throws -> PhotoEngagement {
        let path = "users/me/photos/\(photo.id.uuidString)/like"
        if liked {
            let response: APIEnvelope<PhotoEngagement> = try await api.post(
                path,
                body: EmptyPayload(),
                authenticated: true
            )
            guard response.data.photoId == photo.id else { throw APIError.invalidResponse }
            return response.data
        } else {
            let response: APIEnvelope<PhotoEngagement> = try await api.deleteDecodable(path)
            guard response.data.photoId == photo.id else { throw APIError.invalidResponse }
            return response.data
        }
    }
}

private struct UpdateProfilePhotoPayload: Encodable, Sendable { let description: String? }
private struct EmptyPayload: Encodable, Sendable { }
struct PhotoEngagement: Decodable, Sendable {
    let photoId: UUID
    let likeCount: Int
    let isLiked: Bool
}
