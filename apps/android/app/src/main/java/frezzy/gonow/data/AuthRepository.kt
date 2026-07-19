package frezzy.gonow.data

import frezzy.gonow.models.*
import frezzy.gonow.network.ApiClient

class AuthRepository(
    private val apiClient: ApiClient,
    private val tokenStore: TokenStore,
    private val deviceIdentity: DeviceIdentity
) {

    suspend fun register(name: String, email: String, password: String): RegistrationData {
        val response = apiClient.publicRequest {
            apiClient.api.register(
                RegisterRequest(
                    email = email.trim().lowercase(),
                    password = password,
                    displayName = name.trim(),
                    device = deviceIdentity.getDevicePayload()
                )
            )
        }
        return response.data
    }

    suspend fun verifyEmail(email: String, code: String): User {
        val response = apiClient.publicRequest {
            apiClient.api.verifyEmail(
                VerifyEmailRequest(
                    email = email.trim().lowercase(),
                    code = code,
                    device = deviceIdentity.getDevicePayload()
                )
            )
        }
        tokenStore.saveTokens(response.data.tokens)
        return response.data.user
    }

    suspend fun login(email: String, password: String): User {
        val response = apiClient.publicRequest {
            apiClient.api.login(
                LoginRequest(
                    email = email.trim().lowercase(),
                    password = password,
                    device = deviceIdentity.getDevicePayload()
                )
            )
        }
        tokenStore.saveTokens(response.data.tokens)
        return response.data.user
    }

    suspend fun requestPasswordReset(email: String) {
        apiClient.publicRequest {
            apiClient.api.forgotPassword(ForgotPasswordRequest(email = email.trim().lowercase()))
        }
    }

    suspend fun resetPassword(email: String, code: String, password: String): User {
        val response = apiClient.publicRequest {
            apiClient.api.resetPassword(
                ResetPasswordRequest(
                    email = email.trim().lowercase(),
                    code = code,
                    password = password,
                    device = deviceIdentity.getDevicePayload()
                )
            )
        }
        tokenStore.saveTokens(response.data.tokens)
        return response.data.user
    }

    suspend fun restoreSession(): User? {
        val refreshToken = tokenStore.getRefreshToken() ?: return null
        return try {
            val response = apiClient.authenticatedRequest { apiClient.api.getCurrentUser() }
            response.data
        } catch (e: ApiError) {
            tokenStore.clearTokens()
            null
        }
    }

    suspend fun currentUser(): User {
        val response = apiClient.authenticatedRequest { apiClient.api.getCurrentUser() }
        return response.data
    }

    suspend fun updateProfile(request: UpdateProfileRequest): User {
        val response = apiClient.authenticatedRequest {
            apiClient.api.updateProfile(request)
        }
        return response.data
    }

    suspend fun getProfilePhotos(): ProfilePhotos {
        val response = apiClient.authenticatedRequest { apiClient.api.getProfilePhotos() }
        return response.data
    }

    suspend fun uploadAvatar(imageBytes: ByteArray): ProfilePhoto {
        val part = apiClient.createImagePart(imageBytes, "avatar.jpg")
        val response = apiClient.authenticatedRequest { apiClient.api.uploadAvatar(part) }
        return response.data
    }

    suspend fun uploadPhoto(imageBytes: ByteArray): ProfilePhoto {
        val part = apiClient.createImagePart(imageBytes, "photo.jpg")
        val response = apiClient.authenticatedRequest { apiClient.api.uploadPhoto(part) }
        return response.data
    }

    suspend fun getPhotoContent(photoId: String): ByteArray {
        return apiClient.authenticatedRequest {
            val response = apiClient.api.getPhotoContent(photoId)
            if (response.isSuccessful) {
                response.body()?.bytes() ?: ByteArray(0)
            } else {
                throw ApiError.Network("Failed to load photo")
            }
        }
    }

    suspend fun deletePhoto(photoId: String) {
        apiClient.authenticatedRequest { apiClient.api.deletePhoto(photoId) }
    }

    suspend fun logout() {
        val refreshToken = tokenStore.getRefreshToken()
        if (refreshToken != null) {
            try {
                apiClient.api.logout(LogoutRequest(refreshToken))
            } catch (_: Exception) {
            }
        }
        tokenStore.clearTokens()
    }
}
