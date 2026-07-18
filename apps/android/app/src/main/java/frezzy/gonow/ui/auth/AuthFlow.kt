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

@Composable
fun AuthFlow(
    viewModel: AuthViewModel
) {
    val state = viewModel.uiState

    Box(modifier = Modifier.fillMaxSize()) {
        // Password recovery overlay
        if (state.showPasswordRecovery) {
            PasswordRecoveryScreen(
                email = state.recoveryEmail,
                onEmailChange = viewModel::onRecoveryEmailChange,
                code = state.recoveryCode,
                onCodeChange = viewModel::onRecoveryCodeChange,
                newPassword = state.newPassword,
                onNewPasswordChange = viewModel::onNewPasswordChange,
                confirmation = state.newConfirmation,
                onConfirmationChange = viewModel::onNewConfirmationChange,
                isCodeSent = state.isRecoveryCodeSent,
                onRequestCode = viewModel::requestPasswordReset,
                onResetPassword = viewModel::resetPassword,
                onDismiss = viewModel::dismissPasswordRecovery,
                isLoading = state.isLoading,
                errorMessage = state.errorMessage
            )
        }
        // Email verification overlay
        else if (state.pendingVerificationEmail != null) {
            EmailVerificationScreen(
                email = state.pendingVerificationEmail,
                code = state.verificationCode,
                onCodeChange = viewModel::onVerificationCodeChange,
                onVerify = viewModel::verifyEmail,
                onResend = viewModel::resendVerificationCode,
                onDismiss = viewModel::dismissVerification,
                isLoading = state.isLoading,
                errorMessage = state.errorMessage
            )
        }
        // Login / Register
        else {
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
                        onForgotPassword = viewModel::showPasswordRecovery,
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
}
