package frezzy.gonow.network

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import frezzy.gonow.BuildConfig
import frezzy.gonow.data.SessionStore
import frezzy.gonow.models.ApiError
import frezzy.gonow.models.ApiErrorEnvelope
import frezzy.gonow.models.RefreshRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.HttpException
import retrofit2.Retrofit
import java.io.IOException
import java.util.concurrent.TimeUnit

class ApiClient(
    private val sessionStore: SessionStore,
    baseUrl: String = BuildConfig.API_BASE_URL
) {

    val json: Json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        encodeDefaults = true
        explicitNulls = false
    }

    val okHttpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(90, TimeUnit.SECONDS)
        .pingInterval(25, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            val original = chain.request()
            val isPublic = original.header(PUBLIC_REQUEST_HEADER) == "true"
            val builder = original.newBuilder().removeHeader(PUBLIC_REQUEST_HEADER)
            if (!isPublic) {
                sessionStore.getAccessToken()?.let { builder.header("Authorization", "Bearer $it") }
            }
            chain.proceed(builder.build())
        }
        .apply {
            if (BuildConfig.DEBUG) {
                addInterceptor(HttpLoggingInterceptor().apply {
                    redactHeader("Authorization")
                    redactHeader("Cookie")
                    level = HttpLoggingInterceptor.Level.BASIC
                })
            }
        }
        .build()

    private val normalizedBaseUrl = baseUrl.trimEnd('/') + "/"

    private val retrofit = Retrofit.Builder()
        .baseUrl(normalizedBaseUrl)
        .client(okHttpClient)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()

    val api: ApiService = retrofit.create(ApiService::class.java)
    val webSocketBaseUrl: String = normalizedBaseUrl
        .replaceFirst("https://", "wss://")
        .replaceFirst("http://", "ws://")

    private val refreshMutex = Mutex()

    suspend fun <T> authenticatedRequest(block: suspend () -> T): T = withContext(Dispatchers.IO) {
        try {
            block()
        } catch (error: HttpException) {
            if (error.code() != 401 || sessionStore.getRefreshToken() == null) {
                throw mapHttpError(error)
            }

            val failedToken = error.response()
                ?.raw()
                ?.request
                ?.header("Authorization")
                ?.removePrefix("Bearer ")
            refreshTokenIfNeeded(failedToken)
            try {
                block()
            } catch (retryError: HttpException) {
                throw mapHttpError(retryError)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: IOException) {
            throw ApiError.Network(error.message ?: "Network error", error)
        } catch (error: SerializationException) {
            throw ApiError.Decoding(error.message ?: "Invalid response", error)
        }
    }

    suspend fun <T> publicRequest(block: suspend () -> T): T = withContext(Dispatchers.IO) {
        try {
            block()
        } catch (error: HttpException) {
            throw mapHttpError(error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: IOException) {
            throw ApiError.Network(error.message ?: "Network error", error)
        } catch (error: SerializationException) {
            throw ApiError.Decoding(error.message ?: "Invalid response", error)
        }
    }

    fun createFilePart(
        bytes: ByteArray,
        fileName: String,
        contentType: String,
        formField: String = "file"
    ): MultipartBody.Part {
        val requestBody = bytes.toRequestBody(contentType.toMediaType())
        return MultipartBody.Part.createFormData(formField, fileName, requestBody)
    }

    fun createImagePart(imageBytes: ByteArray, fileName: String): MultipartBody.Part =
        createFilePart(imageBytes, fileName, "image/jpeg")

    private suspend fun refreshTokenIfNeeded(failedAccessToken: String?) {
        refreshMutex.withLock {
            val currentAccessToken = sessionStore.getAccessToken()
            if (failedAccessToken != null && currentAccessToken != null && currentAccessToken != failedAccessToken) {
                return
            }

            val refreshToken = sessionStore.getRefreshToken() ?: throw ApiError.Unauthorized()
            try {
                val response = api.refresh(RefreshRequest(refreshToken))
                sessionStore.saveTokens(response.data.tokens)
            } catch (error: HttpException) {
                if (error.code() == 400 || error.code() == 401) {
                    sessionStore.clearTokens()
                    throw ApiError.Unauthorized()
                }
                throw mapHttpError(error)
            } catch (error: CancellationException) {
                throw error
            } catch (error: IOException) {
                throw ApiError.Network(error.message ?: "Network error", error)
            } catch (error: SerializationException) {
                throw ApiError.Decoding(error.message ?: "Invalid response", error)
            }
        }
    }

    private fun mapHttpError(error: HttpException): ApiError {
        if (error.code() == 401) return ApiError.Unauthorized()
        return try {
            val errorBody = error.response()?.errorBody()?.string()
            if (errorBody != null) {
                val envelope = json.decodeFromString<ApiErrorEnvelope>(errorBody)
                ApiError.Server(envelope.error, error.code())
            } else {
                ApiError.Http(error.code())
            }
        } catch (mappingError: Exception) {
            ApiError.Http(error.code(), cause = mappingError)
        }
    }

    companion object {
        const val PUBLIC_REQUEST_HEADER = "X-GoNow-Public"
    }
}
