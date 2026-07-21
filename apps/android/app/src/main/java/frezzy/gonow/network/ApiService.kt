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

    // ─── Activities ──────────────────────────────────────────

    @GET("activities/map")
    suspend fun getMapActivities(
        @Query("south") south: Double,
        @Query("west") west: Double,
        @Query("north") north: Double,
        @Query("east") east: Double,
        @Query("zoom") zoom: Double,
        @Query("categories") categories: String? = null,
        @Query("startsFrom") startsFrom: String? = null,
        @Query("startsTo") startsTo: String? = null,
        @Query("onlyAvailable") onlyAvailable: Boolean? = null,
        @Query("limit") limit: Int = 500
    ): MapActivitiesEnvelope

    @POST("activities")
    suspend fun createActivity(@Body body: CreateActivityRequest): ApiEnvelope<MapActivityResponse>

    // ─── Map Style ───────────────────────────────────────────

    @GET("map/style")
    suspend fun getMapStyle(): retrofit2.Response<okhttp3.ResponseBody>

    // ─── Activity Detail ────────────────────────────────────

    @GET("activities/{id}")
    suspend fun getActivity(@Path("id") id: String): ApiEnvelope<GoNowActivity>

    @GET("activities/mine")
    suspend fun getOwnedActivities(): ApiEnvelope<List<GoNowActivity>>

    @PATCH("activities/{id}")
    suspend fun updateActivity(@Path("id") id: String, @Body body: UpdateActivityRequest): ApiEnvelope<GoNowActivity>

    @POST("activities/{id}/duplicate")
    suspend fun duplicateActivity(@Path("id") id: String): ApiEnvelope<GoNowActivity>

    @POST("activities/{id}/applications")
    suspend fun applyToActivity(@Path("id") id: String, @Body body: Map<String, String?>): ApiEnvelope<ActivityApplication>

    @GET("activities/{id}/applications")
    suspend fun getApplications(@Path("id") id: String): ApiEnvelope<List<ActivityApplication>>

    @PATCH("activities/{id}/applications/{appId}")
    suspend fun updateApplication(
        @Path("id") id: String,
        @Path("appId") appId: String,
        @Body body: Map<String, String>
    ): ApiEnvelope<ActivityApplication>

    // ─── Social ─────────────────────────────────────────────

    @GET("social/people")
    suspend fun getPeople(@Query("q") query: String? = null): ApiEnvelope<List<SocialUser>>

    @POST("social/friends")
    suspend fun requestFriend(@Body body: Map<String, String>): ApiEnvelope<Unit>

    @PATCH("social/friends/{id}")
    suspend fun decideFriend(@Path("id") id: String, @Body body: Map<String, String>): ApiEnvelope<Unit>

    @DELETE("social/friends/{id}")
    suspend fun removeFriend(@Path("id") id: String)

    @GET("social/invitations")
    suspend fun getInvitations(): ApiEnvelope<List<MeetingInvitation>>

    @POST("social/invitations")
    suspend fun createInvitation(@Body body: CreateInvitationRequest): ApiEnvelope<MeetingInvitation>

    @PATCH("social/invitations/{id}")
    suspend fun decideInvitation(@Path("id") id: String, @Body body: Map<String, String>): ApiEnvelope<MeetingInvitation>

    @GET("social/conversations")
    suspend fun getConversations(): ApiEnvelope<List<Conversation>>

    @POST("social/conversations")
    suspend fun createConversation(@Body body: Map<String, String>): ApiEnvelope<Conversation>

    @GET("social/conversations/{id}/messages")
    suspend fun getMessages(@Path("id") conversationId: String): ApiEnvelope<List<ChatMessage>>

    @POST("social/conversations/{id}/messages")
    suspend fun sendMessage(
        @Path("id") conversationId: String,
        @Body body: Map<String, String>
    ): ApiEnvelope<ChatMessage>

    @POST("social/conversations/{id}/messages/{msgId}/vote")
    suspend fun voteMessage(
        @Path("id") conversationId: String,
        @Path("msgId") messageId: String
    ): ApiEnvelope<ChatMessage>

    // ─── Notifications ──────────────────────────────────────

    @GET("notifications")
    suspend fun getNotifications(): ApiEnvelope<NotificationFeed>

    @GET("notifications/unread-count")
    suspend fun getUnreadCount(): ApiEnvelope<Map<String, Int>>

    @PATCH("notifications/{id}/read")
    suspend fun markNotificationRead(@Path("id") id: String): ApiEnvelope<GoNowNotification>

    @POST("notifications/read-all")
    suspend fun markAllNotificationsRead(): ApiEnvelope<Int>

    @DELETE("notifications/{id}")
    suspend fun deleteNotification(@Path("id") id: String)

    @GET("notifications/settings")
    suspend fun getNotificationPreferences(): ApiEnvelope<NotificationPreferences>

    @PATCH("notifications/settings")
    suspend fun updateNotificationPreferences(@Body body: NotificationPreferences): ApiEnvelope<NotificationPreferences>
}
