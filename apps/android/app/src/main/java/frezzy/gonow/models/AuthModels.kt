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
    @SerialName("username") val username: String,
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
data class VerifyEmailRequest(
    @SerialName("email") val email: String,
    @SerialName("code") val code: String,
    @SerialName("device") val device: DevicePayload
)

@Serializable
data class ForgotPasswordRequest(
    @SerialName("email") val email: String
)

@Serializable
data class ResetPasswordRequest(
    @SerialName("email") val email: String,
    @SerialName("code") val code: String,
    @SerialName("password") val password: String,
    @SerialName("device") val device: DevicePayload
)

@Serializable
data class RegistrationData(
    @SerialName("email") val email: String,
    @SerialName("verificationRequired") val verificationRequired: Boolean,
    @SerialName("expiresAt") val expiresAt: String
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

sealed class AuthPhase {
    data object Launching : AuthPhase()
    data object Unauthenticated : AuthPhase()
    data object Authenticated : AuthPhase()
    data class RestoreFailed(val reason: String) : AuthPhase()
}

object UsernameRules {
    private val reserved = setOf("admin", "administrator", "support", "gonow", "official", "system")
    private val allowed = Regex("^[a-z][a-z0-9_]{4,31}$")

    fun normalize(value: String): String = value.trim().trimStart('@').lowercase()

    fun validationMessage(value: String): String? {
        val username = normalize(value)
        if (username.length !in 5..32) return "Username должен содержать от 5 до 32 символов"
        if (!allowed.matches(username)) {
            return "Используйте латинские буквы, цифры и знак подчёркивания; первый символ — буква"
        }
        if (username in reserved) return "Этот username зарезервирован"
        return null
    }
}
