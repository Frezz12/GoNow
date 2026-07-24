package frezzy.gonow

import android.os.Bundle
import android.content.Intent
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.core.viewModelFactory
import frezzy.gonow.core.AppRoute
import frezzy.gonow.core.weather.WeatherViewModel
import frezzy.gonow.models.AuthPhase
import frezzy.gonow.features.authentication.AuthFlow
import frezzy.gonow.features.authentication.AuthViewModel
import frezzy.gonow.features.activity.ActivityCreationViewModel
import frezzy.gonow.features.map.ActivityMapViewModel
import frezzy.gonow.features.chat.ChatViewModel
import frezzy.gonow.features.main.MainScreen
import frezzy.gonow.features.tasks.TasksViewModel
import frezzy.gonow.features.notifications.NotificationsViewModel
import frezzy.gonow.ui.theme.*

class MainActivity : AppCompatActivity() {

    private var pendingRoute by mutableStateOf<AppRoute?>(null)

    private val container by lazy { (application as GoNowApp).container }
    private val authViewModel by viewModels<AuthViewModel> {
        viewModelFactory { AuthViewModel(container.authRepository, container.mediaCache) }
    }
    private val weatherViewModel by viewModels<WeatherViewModel> {
        viewModelFactory { WeatherViewModel() }
    }
    private val activityMapViewModel by viewModels<ActivityMapViewModel> {
        viewModelFactory { ActivityMapViewModel(container.activityRepository, container.mapCameraStore) }
    }
    private val activityCreationViewModel by viewModels<ActivityCreationViewModel> {
        viewModelFactory {
            ActivityCreationViewModel(
                container.activityRepository,
                container.activityDraftStore,
                container.activityPhotoProcessor
            )
        }
    }
    private val chatViewModel by viewModels<ChatViewModel> {
        viewModelFactory { ChatViewModel(container.socialRepository) }
    }
    private val tasksViewModel by viewModels<TasksViewModel> {
        viewModelFactory { TasksViewModel(container.activityRepository) }
    }
    private val notificationsViewModel by viewModels<NotificationsViewModel> {
        viewModelFactory { NotificationsViewModel(container.notificationRepository) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingRoute = AppRoute.parse(intent?.data)
        enableEdgeToEdge()

        setContent {
            GoNowTheme(settingsPrefs = container.settingsPrefs) {
                val state by authViewModel.uiStateFlow.collectAsStateWithLifecycle()
                val profileMedia by authViewModel.profileMediaStateFlow.collectAsStateWithLifecycle()
                LaunchedEffect(state.phase) {
                    if (state.phase is AuthPhase.Authenticated) notificationsViewModel.start()
                    else notificationsViewModel.stop()
                }

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
                        is AuthPhase.RestoreFailed -> SessionRestoreErrorScreen(
                            message = phase.reason,
                            onRetry = authViewModel::retrySessionRestore,
                            onLogout = authViewModel::logout
                        )
                        is AuthPhase.Authenticated -> MainScreen(
                            user = state.user,
                            avatarBytes = profileMedia.avatarBytes,
                            viewModel = authViewModel,
                            weatherViewModel = weatherViewModel,
                            locationProvider = container.locationProvider,
                            settingsPrefs = container.settingsPrefs,
                            activityMapViewModel = activityMapViewModel,
                            activityCreationViewModel = activityCreationViewModel,
                            chatViewModel = chatViewModel,
                            tasksViewModel = tasksViewModel,
                            notificationsViewModel = notificationsViewModel,
                            appContainer = container,
                            externalRoute = pendingRoute,
                            onExternalRouteConsumed = { pendingRoute = null },
                            onLogout = authViewModel::logout
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingRoute = AppRoute.parse(intent.data)
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

@Composable
fun SessionRestoreErrorScreen(message: String, onRetry: () -> Unit, onLogout: () -> Unit) {
    Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(Icons.Default.CloudOff, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(48.dp))
            Text("Не удалось восстановить сессию", style = MaterialTheme.typography.titleLarge)
            Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onRetry) { Text("Повторить") }
            TextButton(onClick = onLogout) { Text("Войти заново") }
        }
    }
}
