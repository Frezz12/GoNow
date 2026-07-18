package frezzy.gonow.network

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import frezzy.gonow.BuildConfig
import frezzy.gonow.data.TokenStore
import frezzy.gonow.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import java.util.concurrent.TimeUnit

class ApiClient(private val tokenStore: TokenStore) {

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        encodeDefaults = true
    }

    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            val original = chain.request()
            val token = tokenStore.getAccessToken()
            val request = if (token != null) {
                original.newBuilder()
                    .header("Authorization", "Bearer $token")
                    .build()
            } else {
                original
            }
            chain.proceed(request)
        }
        .apply {
            if (BuildConfig.DEBUG) {
                addInterceptor(HttpLoggingInterceptor().apply {
                    level = HttpLoggingInterceptor.Level.BODY
                })
            }
        }
        .build()

    private val retrofit = Retrofit.Builder()
        .baseUrl(BuildConfig.API_BASE_URL + "/")
        .client(okHttpClient)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()

    val api: ApiService = retrofit.create(ApiService::class.java)

    private val refreshMutex = Mutex()

    suspend fun <T> authenticatedRequest(
        block: suspend () -> T
    ): T = withContext(Dispatchers.IO) {
        try {
            block()
        } catch (e: retrofit2.HttpException) {
            if (e.code() == 401 && tokenStore.getRefreshToken() != null) {
                tryRefreshToken()
                block()
            } else {
                throw mapHttpError(e)
            }
        }
    }

    suspend fun <T> publicRequest(
        block: suspend () -> T
    ): T = withContext(Dispatchers.IO) {
        try {
            block()
        } catch (e: retrofit2.HttpException) {
            throw mapHttpError(e)
        }
    }

    fun createImagePart(imageBytes: ByteArray, fileName: String): MultipartBody.Part {
        val requestBody = imageBytes.toRequestBody("image/jpeg".toMediaType())
        return MultipartBody.Part.createFormData("file", fileName, requestBody)
    }

    private suspend fun tryRefreshToken() = withContext(Dispatchers.IO) {
        refreshMutex.withLock {
            val refreshToken = tokenStore.getRefreshToken() ?: throw ApiError.Unauthorized()
            try {
                val response = api.refresh(RefreshRequest(refreshToken))
                tokenStore.saveTokens(response.data.tokens)
            } catch (e: retrofit2.HttpException) {
                tokenStore.clearTokens()
                throw ApiError.Unauthorized()
            }
        }
    }

    private fun mapHttpError(e: retrofit2.HttpException): ApiError {
        return try {
            val errorBody = e.response()?.errorBody()?.string()
            if (errorBody != null) {
                val envelope = json.decodeFromString<ApiErrorEnvelope>(errorBody)
                ApiError.Server(envelope.error)
            } else {
                ApiError.Network("HTTP ${e.code()}")
            }
        } catch (_: Exception) {
            ApiError.Network("HTTP ${e.code()}")
        }
    }
}
