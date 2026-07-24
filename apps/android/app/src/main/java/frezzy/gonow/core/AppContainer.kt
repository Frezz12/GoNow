package frezzy.gonow.core

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import frezzy.gonow.core.location.DeviceLocationProvider
import frezzy.gonow.data.ActivityRepository
import frezzy.gonow.data.ActivityDraftStore
import frezzy.gonow.data.AndroidActivityPhotoProcessor
import frezzy.gonow.data.MapCameraStore
import frezzy.gonow.data.AuthRepository
import frezzy.gonow.data.DeviceIdentity
import frezzy.gonow.data.NotificationRepository
import frezzy.gonow.data.SocialRepository
import frezzy.gonow.data.TokenStore
import frezzy.gonow.network.ApiClient
import frezzy.gonow.network.OkHttpRealtimeClient
import frezzy.gonow.network.RealtimeClient

/** Application-scoped dependency graph. Repositories share one session and one HTTP connection pool. */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val tokenStore: TokenStore by lazy { TokenStore(appContext) }
    val apiClient: ApiClient by lazy { ApiClient(tokenStore) }
    val realtimeClient: RealtimeClient by lazy {
        OkHttpRealtimeClient(apiClient.okHttpClient, apiClient.webSocketBaseUrl, tokenStore)
    }
    val mediaCache: MediaCache by lazy { DiskMediaCache(appContext) }
    val deviceIdentity: DeviceIdentity by lazy { DeviceIdentity(appContext) }

    val authRepository: AuthRepository by lazy {
        AuthRepository(apiClient, tokenStore, deviceIdentity)
    }
    val activityRepository: ActivityRepository by lazy { ActivityRepository(apiClient) }
    val activityDraftStore: ActivityDraftStore by lazy { ActivityDraftStore(appContext) }
    val activityPhotoProcessor by lazy { AndroidActivityPhotoProcessor(appContext) }
    val mapCameraStore: MapCameraStore by lazy { MapCameraStore(appContext) }
    val socialRepository: SocialRepository by lazy { SocialRepository(apiClient, realtimeClient) }
    val notificationRepository: NotificationRepository by lazy {
        NotificationRepository(apiClient, realtimeClient)
    }

    val settingsPrefs: SettingsPrefs by lazy { SettingsPrefs.getInstance(appContext) }
    val locationProvider: DeviceLocationProvider by lazy { DeviceLocationProvider(appContext) }
}

inline fun <reified VM : ViewModel> viewModelFactory(crossinline create: () -> VM): ViewModelProvider.Factory =
    object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            require(modelClass.isAssignableFrom(VM::class.java)) {
                "Unknown ViewModel class: ${modelClass.name}"
            }
            return create() as T
        }
    }
