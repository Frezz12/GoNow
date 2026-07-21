package frezzy.gonow

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.core.SettingsPrefs
import frezzy.gonow.core.location.DeviceLocationProvider
import frezzy.gonow.core.weather.WeatherViewModel
import frezzy.gonow.data.ActivityRepository
import frezzy.gonow.data.AuthRepository
import frezzy.gonow.data.DeviceIdentity
import frezzy.gonow.data.NotificationRepository
import frezzy.gonow.data.SocialRepository
import frezzy.gonow.data.TokenStore
import frezzy.gonow.models.AuthPhase
import frezzy.gonow.network.ApiClient
import frezzy.gonow.features.authentication.AuthFlow
import frezzy.gonow.features.authentication.AuthViewModel
import frezzy.gonow.features.activity.ActivityCreationViewModel
import frezzy.gonow.features.map.ActivityMapViewModel
import frezzy.gonow.features.chat.ChatViewModel
import frezzy.gonow.features.main.MainScreen
import frezzy.gonow.ui.theme.*

class MainActivity : ComponentActivity() {

    private lateinit var authViewModel: AuthViewModel
    private lateinit var weatherViewModel: WeatherViewModel
    private lateinit var locationProvider: DeviceLocationProvider
    private lateinit var settingsPrefs: SettingsPrefs
    private lateinit var activityMapViewModel: ActivityMapViewModel
    private lateinit var activityCreationViewModel: ActivityCreationViewModel
    private lateinit var chatViewModel: ChatViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val tokenStore = TokenStore(applicationContext)
        val deviceIdentity = DeviceIdentity(applicationContext)
        val apiClient = ApiClient(tokenStore)
        val authRepository = AuthRepository(apiClient, tokenStore, deviceIdentity)
        authViewModel = AuthViewModel(authRepository)
        weatherViewModel = WeatherViewModel()
        locationProvider = DeviceLocationProvider(applicationContext)
        settingsPrefs = SettingsPrefs.getInstance(applicationContext)
        activityMapViewModel = ActivityMapViewModel(ActivityRepository(apiClient))
        activityCreationViewModel = ActivityCreationViewModel(ActivityRepository(apiClient))
        chatViewModel = ChatViewModel(SocialRepository(apiClient))

        setContent {
            GoNowTheme(settingsPrefs = settingsPrefs) {
                val state = authViewModel.uiState

                AnimatedContent(
                    targetState = state.phase,
                    transitionSpec = {
                        fadeIn(animationSpec = tween(400)) togetherWith fadeOut(animationSpec = tween(200))
                    },
                    label = "root_content"
                ) { phase ->
                    when (phase) {
                        is AuthPhase.Launching -> LaunchScreen()
                        is AuthPhase.Unauthenticated -> AuthFlow(viewModel = authViewModel)
                        is AuthPhase.Authenticated -> MainScreen(
                            user = state.user,
                            avatarBytes = state.avatarBytes,
                            viewModel = authViewModel,
                            weatherViewModel = weatherViewModel,
                            locationProvider = locationProvider,
                            settingsPrefs = settingsPrefs,
                            activityMapViewModel = activityMapViewModel,
                            activityCreationViewModel = activityCreationViewModel,
                            chatViewModel = chatViewModel,
                            onLogout = authViewModel::logout
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun LaunchScreen() {
    Box(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            MapPointMarker()
            Text("GoNow", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground)
            CircularProgressIndicator(modifier = Modifier.size(24.dp), color = MaterialTheme.colorScheme.primary, strokeWidth = 2.dp)
            Text("Восстанавливаем сессию", style = MaterialTheme.typography.bodyMedium)
        }
    }
}
