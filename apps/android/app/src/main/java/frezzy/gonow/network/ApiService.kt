package frezzy.gonow.network

import frezzy.gonow.models.*
import okhttp3.MultipartBody
import okhttp3.RequestBody
import retrofit2.http.*

interface ApiService {

    @POST("auth/register")
    suspend fun register(@Body body: RegisterRequest): ApiEnvelope<RegistrationData>

    @POST("auth/verify-email")
    suspend fun verifyEmail(@Body body: VerifyEmailRequest): ApiEnvelope<AuthData>

    @POST("auth/login")
    suspend fun login(@Body body: LoginRequest): ApiEnvelope<AuthData>

    @POST("auth/forgot-password")
    suspend fun forgotPassword(@Body body: ForgotPasswordRequest): ApiEnvelope<Unit>

    @POST("auth/reset-password")
    suspend fun resetPassword(@Body body: ResetPasswordRequest): ApiEnvelope<AuthData>

    @POST("auth/refresh")
    suspend fun refresh(@Body body: RefreshRequest): ApiEnvelope<AuthData>

    @POST("auth/logout")
    suspend fun logout(@Body body: LogoutRequest): ApiEnvelope<Unit>

    @GET("users/me")
    suspend fun getCurrentUser(): ApiEnvelope<User>

    @PATCH("users/me")
    suspend fun updateProfile(@Body body: UpdateProfileRequest): ApiEnvelope<User>

    @GET("users/me/photos")
    suspend fun getProfilePhotos(): ApiEnvelope<ProfilePhotos>

    @Multipart
    @POST("users/me/avatar")
    suspend fun uploadAvatar(@Part file: MultipartBody.Part): ApiEnvelope<ProfilePhoto>

    @Multipart
    @POST("users/me/photos")
    suspend fun uploadPhoto(@Part file: MultipartBody.Part): ApiEnvelope<ProfilePhoto>

    @GET("users/me/photos/{photoId}/content")
    suspend fun getPhotoContent(@Path("photoId") photoId: String): retrofit2.Response<okhttp3.ResponseBody>

    @DELETE("users/me/photos/{photoId}")
    suspend fun deletePhoto(@Path("photoId") photoId: String)
}
