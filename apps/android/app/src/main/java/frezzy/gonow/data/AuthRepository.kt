package frezzy.gonow.data

import frezzy.gonow.models.*
import frezzy.gonow.network.ApiClient

class AuthRepository(
    private val apiClient: ApiClient,
    private val tokenStore: TokenStore,
    private val deviceIdentity: DeviceIdentity
) {

    suspend fun register(
        name: String,
        email: String,
        password: String
    ): User {
        val response = apiClient.api.register(
            RegisterRequest(
                email = email.trim().lowercase(),
                password = password,
                displayName = name.trim(),
                device = deviceIdentity.getDevicePayload()
            )
        )
        tokenStore.saveTokens(response.data.tokens)
        return response.data.user
    }

    suspend fun login(email: String, password: String): User {
        val response = apiClient.api.login(
            LoginRequest(
                email = email.trim().lowercase(),
                password = password,
                device = deviceIdentity.getDevicePayload()
            )
        )
        tokenStore.saveTokens(response.data.tokens)
        return response.data.user
    }

    suspend fun restoreSession(): User? {
        val refreshToken = tokenStore.getRefreshToken() ?: return null
        return try {
            val response = apiClient.authenticatedRequest {
                apiClient.api.getCurrentUser()
            }
            response.data
        } catch (e: ApiError) {
            tokenStore.clearTokens()
            null
        }
    }

    suspend fun refresh(): User {
        val refreshToken = tokenStore.getRefreshToken()
            ?: throw ApiError.Unauthorized("No refresh token")
        val response = apiClient.api.refresh(RefreshRequest(refreshToken))
        tokenStore.saveTokens(response.data.tokens)
        return response.data.user
    }

    suspend fun logout() {
        val refreshToken = tokenStore.getRefreshToken()
        if (refreshToken != null) {
            try {
                apiClient.api.logout(LogoutRequest(refreshToken))
            } catch (_: Exception) {
                // Logout is best-effort; clear tokens regardless
            }
        }
        tokenStore.clearTokens()
    }
}
