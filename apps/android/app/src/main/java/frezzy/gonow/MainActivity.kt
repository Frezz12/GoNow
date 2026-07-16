package frezzy.gonow

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.*
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
import frezzy.gonow.data.AuthRepository
import frezzy.gonow.data.DeviceIdentity
import frezzy.gonow.data.TokenStore
import frezzy.gonow.models.AuthPhase
import frezzy.gonow.network.ApiClient
import frezzy.gonow.ui.auth.AuthFlow
import frezzy.gonow.ui.auth.AuthViewModel
import frezzy.gonow.ui.main.MainScreen
import frezzy.gonow.ui.main.MainViewModel
import frezzy.gonow.ui.theme.*

class MainActivity : ComponentActivity() {

    private lateinit var authViewModel: AuthViewModel
    private val mainViewModel = MainViewModel()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val tokenStore = TokenStore(applicationContext)
        val deviceIdentity = DeviceIdentity(applicationContext)
        val apiClient = ApiClient(tokenStore)
        val authRepository = AuthRepository(apiClient, tokenStore, deviceIdentity)
        authViewModel = AuthViewModel(authRepository)

        setContent {
            GoNowTheme {
                val state = authViewModel.uiState

                AnimatedContent(
                    targetState = state.phase,
                    transitionSpec = {
                        fadeIn(animationSpec = androidx.compose.animation.core.tween(400)) togetherWith
                            fadeOut(animationSpec = androidx.compose.animation.core.tween(200))
                    },
                    label = "root_content"
                ) { phase ->
                    when (phase) {
                        is AuthPhase.Launching -> LaunchScreen()
                        is AuthPhase.Unauthenticated -> AuthFlow(viewModel = authViewModel)
                        is AuthPhase.Authenticated -> MainScreen(
                            user = state.user,
                            viewModel = mainViewModel,
                            onRefreshProfile = authViewModel::refreshProfile,
                            onLogout = authViewModel::logout,
                            isRefreshing = state.isLoading
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
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(BackdropTop, BackdropMid, BackdropBottom)
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            MapPointMarker()
            Text(
                text = "GoNow",
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary
            )
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                color = Primary,
                strokeWidth = 2.dp
            )
            Text(
                text = "Восстанавливаем сессию",
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}
