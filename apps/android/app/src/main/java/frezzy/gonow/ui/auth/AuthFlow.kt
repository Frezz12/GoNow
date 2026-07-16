package frezzy.gonow.ui.auth

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import frezzy.gonow.ui.theme.AuthBackdrop
import frezzy.gonow.ui.theme.Primary

@Composable
fun AuthFlow(
    viewModel: AuthViewModel
) {
    val state = viewModel.uiState

    Box(modifier = Modifier.fillMaxSize()) {
        AnimatedContent(
            targetState = state.isLoginMode,
            transitionSpec = {
                fadeIn(animationSpec = tween(300)) + slideInHorizontally(
                    animationSpec = tween(300),
                    initialOffsetX = { if (targetState) -it else it }
                ) togetherWith fadeOut(animationSpec = tween(200))
            },
            label = "auth_content"
        ) { isLogin ->
            if (isLogin) {
                LoginScreen(
                    onLogin = viewModel::login,
                    onNavigateToRegister = viewModel::toggleMode,
                    isLoading = state.isLoading,
                    fieldErrors = state.fieldErrors,
                    errorMessage = state.errorMessage
                )
            } else {
                RegisterScreen(
                    onRegister = viewModel::register,
                    onNavigateToLogin = viewModel::toggleMode,
                    isLoading = state.isLoading,
                    fieldErrors = state.fieldErrors,
                    errorMessage = state.errorMessage
                )
            }
        }
    }
}
