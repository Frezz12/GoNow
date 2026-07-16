package frezzy.gonow.network

import frezzy.gonow.models.*
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

interface ApiService {

    @POST("auth/register")
    suspend fun register(@Body body: RegisterRequest): ApiEnvelope<AuthData>

    @POST("auth/login")
    suspend fun login(@Body body: LoginRequest): ApiEnvelope<AuthData>

    @POST("auth/refresh")
    suspend fun refresh(@Body body: RefreshRequest): ApiEnvelope<AuthData>

    @POST("auth/logout")
    suspend fun logout(@Body body: LogoutRequest): ApiEnvelope<Unit>

    @GET("users/me")
    suspend fun getCurrentUser(): ApiEnvelope<User>
}
