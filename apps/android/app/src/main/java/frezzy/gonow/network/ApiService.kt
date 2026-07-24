package frezzy.gonow.network

import frezzy.gonow.models.*
import okhttp3.MultipartBody
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.*

interface ApiService {

    @Headers("X-GoNow-Public: true")
    @POST("auth/register")
    suspend fun register(@Body body: RegisterRequest): ApiEnvelope<RegistrationData>

    @Headers("X-GoNow-Public: true")
    @POST("auth/verify-email")
    suspend fun verifyEmail(@Body body: VerifyEmailRequest): ApiEnvelope<AuthData>

    @Headers("X-GoNow-Public: true")
    @POST("auth/login")
    suspend fun login(@Body body: LoginRequest): ApiEnvelope<AuthData>

    @Headers("X-GoNow-Public: true")
    @POST("auth/forgot-password")
    suspend fun forgotPassword(@Body body: ForgotPasswordRequest): ApiEnvelope<Unit>

    @Headers("X-GoNow-Public: true")
    @POST("auth/reset-password")
    suspend fun resetPassword(@Body body: ResetPasswordRequest): ApiEnvelope<AuthData>

    @Headers("X-GoNow-Public: true")
    @POST("auth/refresh")
    suspend fun refresh(@Body body: RefreshRequest): ApiEnvelope<AuthData>

    @Headers("X-GoNow-Public: true")
    @POST("auth/logout")
    suspend fun logout(@Body body: LogoutRequest): ApiEnvelope<Unit>

    @Headers("X-GoNow-Public: true")
    @GET("users/username-availability")
    suspend fun usernameAvailability(@Query("username") username: String): ApiEnvelope<UsernameAvailability>

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

    @PATCH("users/me/photos/{photoId}")
    suspend fun updatePhoto(
        @Path("photoId") photoId: String,
        @Body body: UpdatePhotoRequest
    ): ApiEnvelope<ProfilePhoto>

    @POST("users/me/photos/{photoId}/like")
    suspend fun likeOwnPhoto(@Path("photoId") photoId: String): ApiEnvelope<PhotoEngagement>

    @DELETE("users/me/photos/{photoId}/like")
    suspend fun unlikeOwnPhoto(@Path("photoId") photoId: String): ApiEnvelope<PhotoEngagement>

    @Streaming
    @GET
    suspend fun getContent(@Url url: String): Response<ResponseBody>

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
    suspend fun createActivity(@Body body: CreateActivityRequest): ApiEnvelope<GoNowActivity>

    @Multipart
    @POST("activities/{id}/photos")
    suspend fun uploadActivityPhoto(
        @Path("id") id: String,
        @Query("sortIndex") sortIndex: Int,
        @Query("isCover") isCover: Boolean,
        @Part file: MultipartBody.Part
    ): ApiEnvelope<ActivityPhotoRef>

    // ─── Map Style ───────────────────────────────────────────

    @GET("map/style")
    suspend fun getMapStyle(): retrofit2.Response<okhttp3.ResponseBody>

    // ─── Activity Detail ────────────────────────────────────

    @GET("activities/{id}")
    suspend fun getActivity(@Path("id") id: String): ApiEnvelope<GoNowActivity>

    @GET("activities/mine")
    suspend fun getOwnedActivities(): ApiEnvelope<List<GoNowActivity>>

    @GET("activities/participating")
    suspend fun getParticipatingActivities(): ApiEnvelope<List<GoNowActivity>>

    @PATCH("activities/{id}")
    suspend fun updateActivity(@Path("id") id: String, @Body body: UpdateActivityRequest): ApiEnvelope<GoNowActivity>

    @POST("activities/{id}/duplicate")
    suspend fun duplicateActivity(@Path("id") id: String): ApiEnvelope<GoNowActivity>

    @POST("activities/{id}/applications")
    suspend fun applyToActivity(
        @Path("id") id: String,
        @Body body: CreateApplicationRequest
    ): ApiEnvelope<ActivityApplication>

    @GET("activities/{id}/applications")
    suspend fun getApplications(@Path("id") id: String): ApiEnvelope<List<ActivityApplication>>

    @PATCH("activities/{id}/applications/{appId}")
    suspend fun updateApplication(
        @Path("id") id: String,
        @Path("appId") appId: String,
        @Body body: UpdateApplicationRequest
    ): ApiEnvelope<ActivityApplication>

    // ─── Social ─────────────────────────────────────────────

    @GET("social/people")
    suspend fun getPeople(@Query("q") query: String? = null): ApiEnvelope<List<SocialUser>>

    @GET("social/privacy")
    suspend fun getSocialPrivacy(): ApiEnvelope<SocialPrivacySettings>

    @PATCH("social/privacy")
    suspend fun updateSocialPrivacy(@Body body: SocialPrivacySettings): ApiEnvelope<SocialPrivacySettings>

    @GET("users/{id}")
    suspend fun getPublicProfile(@Path("id") id: String): ApiEnvelope<PublicUserProfile>

    @POST("social/friends")
    suspend fun requestFriend(@Body body: Map<String, String>): ApiEnvelope<SocialUser>

    @PATCH("social/friends/{id}")
    suspend fun decideFriend(@Path("id") id: String, @Body body: Map<String, String>): ApiEnvelope<SocialUser>

    @DELETE("social/friends/{id}")
    suspend fun removeFriend(@Path("id") id: String): ApiEnvelope<SocialUser>

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

    @GET("social/conversations/{id}/messages/{msgId}")
    suspend fun getMessage(
        @Path("id") conversationId: String,
        @Path("msgId") messageId: String
    ): ApiEnvelope<ChatMessage>

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

    @Multipart
    @POST("social/conversations/{id}/attachments")
    suspend fun uploadAttachment(
        @Path("id") conversationId: String,
        @Query("kind") kind: String,
        @Query("durationSeconds") durationSeconds: Double? = null,
        @Part file: MultipartBody.Part
    ): ApiEnvelope<ChatMessage>

    // ─── Notifications ──────────────────────────────────────

    @GET("notifications")
    suspend fun getNotifications(): ApiEnvelope<NotificationFeed>

    @GET("notifications/unread-count")
    suspend fun getUnreadCount(): ApiEnvelope<NotificationUnreadCount>

    @PATCH("notifications/{id}/read")
    suspend fun markNotificationRead(@Path("id") id: String): ApiEnvelope<GoNowNotification>

    @POST("notifications/read-all")
    suspend fun markAllNotificationsRead(): ApiEnvelope<NotificationUnreadCount>

    @DELETE("notifications/{id}")
    suspend fun deleteNotification(@Path("id") id: String)

    @GET("notifications/settings")
    suspend fun getNotificationPreferences(): ApiEnvelope<NotificationPreferences>

    @PATCH("notifications/settings")
    suspend fun updateNotificationPreferences(@Body body: NotificationPreferences): ApiEnvelope<NotificationPreferences>
}
