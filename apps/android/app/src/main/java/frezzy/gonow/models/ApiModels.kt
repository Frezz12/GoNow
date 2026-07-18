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
data class UpdateProfileRequest(
    @SerialName("displayName") val displayName: String,
    @SerialName("birthDate") val birthDate: String? = null,
    @SerialName("city") val city: String? = null,
    @SerialName("occupation") val occupation: String? = null,
    @SerialName("bio") val bio: String? = null,
    @SerialName("interests") val interests: List<String> = emptyList(),
    @SerialName("relationshipStatus") val relationshipStatus: String? = null,
    @SerialName("locationLabel") val locationLabel: String? = null,
    @SerialName("latitude") val latitude: Double? = null,
    @SerialName("longitude") val longitude: Double? = null,
    @SerialName("showDistance") val showDistance: Boolean = true
)

@Serializable
data class ProfilePhoto(
    @SerialName("id") val id: String,
    @SerialName("contentType") val contentType: String,
    @SerialName("bytes") val bytes: Long,
    @SerialName("createdAt") val createdAt: String,
    @SerialName("contentPath") val contentPath: String
)

@Serializable
data class ProfilePhotos(
    @SerialName("avatar") val avatar: ProfilePhoto? = null,
    @SerialName("photos") val photos: List<ProfilePhoto> = emptyList()
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
    @SerialName("birthDate") val birthDate: String? = null,
    @SerialName("city") val city: String? = null,
    @SerialName("occupation") val occupation: String? = null,
    @SerialName("bio") val bio: String? = null,
    @SerialName("interests") val interests: List<String>? = null,
    @SerialName("rating") val rating: Double? = null,
    @SerialName("relationshipStatus") val relationshipStatus: String? = null,
    @SerialName("locationLabel") val locationLabel: String? = null,
    @SerialName("latitude") val latitude: Double? = null,
    @SerialName("longitude") val longitude: Double? = null,
    @SerialName("showDistance") val showDistance: Boolean? = null,
    @SerialName("profileComplete") val profileComplete: Boolean? = null,
    @SerialName("createdAt") val createdAt: String
) {
    val initials: String
        get() = displayName.split("\\s+".toRegex())
            .take(2)
            .mapNotNull { it.firstOrNull()?.uppercase() }
            .joinToString("")

    val ratingText: String
        get() = String.format("%.1f", (rating ?: 5.0).coerceIn(1.0, 5.0))

    val age: Int?
        get() {
            if (birthDate == null) return null
            return try {
                val parts = birthDate.split("-")
                val birthYear = parts[0].toInt()
                val birthMonth = parts[1].toInt()
                val birthDay = parts[2].toInt()
                val now = java.time.LocalDate.now()
                var age = now.year - birthYear
                if (now.monthValue < birthMonth || (now.monthValue == birthMonth && now.dayOfMonth < birthDay)) {
                    age--
                }
                age
            } catch (_: Exception) {
                null
            }
        }

    val birthDateDisplay: String?
        get() {
            if (birthDate == null) return null
            return try {
                val parts = birthDate.split("-")
                val day = parts[2].toInt()
                val month = parts[1].toInt()
                val months = listOf("", "января", "февраля", "марта", "апреля", "мая", "июня",
                    "июля", "августа", "сентября", "октября", "ноября", "декабря")
                val ageStr = age?.let { ", $it ${ruYears(it)}" } ?: ""
                "$day ${months[month]}$ageStr"
            } catch (_: Exception) {
                birthDate
            }
        }

    val profileStatus: ProfileStatus
        get() {
            if (profileComplete == false || birthDate == null) return ProfileStatus.REQUIRED
            if (city.isNullOrBlank() || occupation.isNullOrBlank() || bio.isNullOrBlank() || interests.isNullOrEmpty()) {
                return ProfileStatus.OPTIONAL
            }
            return ProfileStatus.COMPLETE
        }

    val isFreshProfile: Boolean
        get() = birthDate == null
            && city.isNullOrBlank()
            && occupation.isNullOrBlank()
            && bio.isNullOrBlank()
            && interests.isNullOrEmpty()
            && relationshipStatus.isNullOrBlank()
            && locationLabel.isNullOrBlank()
}

enum class ProfileStatus {
    COMPLETE, OPTIONAL, REQUIRED;

    val color: androidx.compose.ui.graphics.Color
        get() = when (this) {
            COMPLETE -> androidx.compose.ui.graphics.Color.Transparent
            OPTIONAL -> androidx.compose.ui.graphics.Color(0xFFF59E0B)
            REQUIRED -> androidx.compose.ui.graphics.Color(0xFFDC2626)
        }

    val message: String
        get() = when (this) {
            COMPLETE -> ""
            OPTIONAL -> "Добавьте немного информации, чтобы люди больше узнали о вас."
            REQUIRED -> "Укажите дату рождения, чтобы создавать задания и подавать заявки."
        }
}

private fun ruYears(n: Int): String {
    val r100 = n % 100
    val r10 = n % 10
    if (r100 in 11..14) return "лет"
    return when (r10) {
        1 -> "год"
        in 2..4 -> "года"
        else -> "лет"
    }
}

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
