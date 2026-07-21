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

sealed class ApiError(message: String) : Exception(message) {
    class Server(val error: ApiErrorBody) : ApiError(error.message)
    class Unauthorized(message: String = "Unauthorized") : ApiError(message)
    class Network(message: String = "Network error") : ApiError(message)
    class Decoding(message: String = "Invalid response") : ApiError(message)
}
