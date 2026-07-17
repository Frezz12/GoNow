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
        return response.data
    }

    func uploadPhoto(_ imageData: Data) async throws -> ProfilePhoto {
        let response: APIEnvelope<ProfilePhoto> = try await api.uploadImage("users/me/photos", imageData: imageData)
        return response.data
    }

    func content(for photo: ProfilePhoto) async throws -> Data {
        try await api.getData(photo.contentPath)
    }

    func delete(_ photo: ProfilePhoto) async throws {
        try await api.delete("users/me/photos/\(photo.id.uuidString)")
    }
}
