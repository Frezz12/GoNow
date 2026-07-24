package frezzy.gonow.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ApiEnvelope<T>(
    @SerialName("data") val data: T
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

sealed class ApiError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Server(val error: ApiErrorBody, val statusCode: Int) : ApiError(error.message)
    class Unauthorized(message: String = "Unauthorized") : ApiError(message)
    class Http(val statusCode: Int, message: String = "HTTP $statusCode", cause: Throwable? = null) :
        ApiError(message, cause)
    class Network(message: String = "Network error", cause: Throwable? = null) : ApiError(message, cause)
    class Decoding(message: String = "Invalid response", cause: Throwable? = null) : ApiError(message, cause)
}
