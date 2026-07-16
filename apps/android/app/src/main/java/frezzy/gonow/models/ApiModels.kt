package frezzy.gonow.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DevicePayload(
    @SerialName("deviceId") val deviceId: String,
    @SerialName("deviceName") val deviceName: String,
    @SerialName("platform") val platform: String = "android"
)

@Serializable
data class RegisterRequest(
    @SerialName("email") val email: String,
    @SerialName("password") val password: String,
    @SerialName("displayName") val displayName: String,
    @SerialName("device") val device: DevicePayload
)

@Serializable
data class LoginRequest(
    @SerialName("email") val email: String,
    @SerialName("password") val password: String,
    @SerialName("device") val device: DevicePayload
)

@Serializable
data class RefreshRequest(
    @SerialName("refreshToken") val refreshToken: String
)

@Serializable
data class LogoutRequest(
    @SerialName("refreshToken") val refreshToken: String
)

@Serializable
data class ApiEnvelope<T>(
    @SerialName("data") val data: T
)

@Serializable
data class AuthData(
    @SerialName("user") val user: User,
    @SerialName("tokens") val tokens: TokenSet
)

@Serializable
data class TokenSet(
    @SerialName("accessToken") val accessToken: String,
    @SerialName("refreshToken") val refreshToken: String,
    @SerialName("accessTokenExpiresAt") val accessTokenExpiresAt: String
)

@Serializable
data class User(
    @SerialName("id") val id: String,
    @SerialName("email") val email: String,
    @SerialName("displayName") val displayName: String,
    @SerialName("emailVerified") val emailVerified: Boolean,
    @SerialName("createdAt") val createdAt: String
)

@Serializable
data class ApiErrorEnvelope(
    @SerialName("error") val error: ApiErrorBody
)

@Serializable
data class ApiErrorBody(
    @SerialName("code") val code: String,
    @SerialName("message") val message: String,
    @SerialName("fields") val fields: Map<String, String>? = null,
    @SerialName("requestId") val requestId: String = ""
)

sealed class AuthPhase {
    data object Launching : AuthPhase()
    data object Unauthenticated : AuthPhase()
    data object Authenticated : AuthPhase()
}

sealed class ApiError(message: String) : Exception(message) {
    class Server(val error: ApiErrorBody) : ApiError(error.message)
    class Unauthorized(message: String = "Unauthorized") : ApiError(message)
    class Network(message: String = "Network error") : ApiError(message)
    class Decoding(message: String = "Invalid response") : ApiError(message)
}
