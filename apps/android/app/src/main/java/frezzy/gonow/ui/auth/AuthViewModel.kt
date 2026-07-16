package frezzy.gonow.ui.auth

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.AuthRepository
import frezzy.gonow.models.ApiError
import frezzy.gonow.models.AuthPhase
import frezzy.gonow.models.User
import kotlinx.coroutines.launch

data class AuthUiState(
    val phase: AuthPhase = AuthPhase.Launching,
    val isLoginMode: Boolean = true,
    val isLoading: Boolean = false,
    val user: User? = null,
    val errorMessage: String? = null,
    val fieldErrors: Map<String, String> = emptyMap()
)

class AuthViewModel(private val authRepository: AuthRepository) : ViewModel() {

    var uiState by mutableStateOf(AuthUiState())
        private set

    init {
        restoreSession()
    }

    private fun restoreSession() {
        viewModelScope.launch {
            try {
                val user = authRepository.restoreSession()
                if (user != null) {
                    uiState = uiState.copy(phase = AuthPhase.Authenticated, user = user)
                } else {
                    uiState = uiState.copy(phase = AuthPhase.Unauthenticated)
                }
            } catch (_: Exception) {
                uiState = uiState.copy(phase = AuthPhase.Unauthenticated)
            }
        }
    }

    fun toggleMode() {
        uiState = uiState.copy(
            isLoginMode = !uiState.isLoginMode,
            errorMessage = null,
            fieldErrors = emptyMap()
        )
    }

    fun login(email: String, password: String) {
        if (!validateLogin(email, password)) return
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null, fieldErrors = emptyMap())
            try {
                val user = authRepository.login(email, password)
                uiState = uiState.copy(
                    phase = AuthPhase.Authenticated,
                    user = user,
                    isLoading = false
                )
            } catch (e: ApiError) {
                handleApiError(e)
            } catch (_: Exception) {
                uiState = uiState.copy(
                    isLoading = false,
                    errorMessage = "Проверьте подключение к сети"
                )
            }
        }
    }

    fun register(name: String, email: String, password: String, confirmPassword: String) {
        if (!validateRegister(name, email, password, confirmPassword)) return
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null, fieldErrors = emptyMap())
            try {
                val user = authRepository.register(name, email, password)
                uiState = uiState.copy(
                    phase = AuthPhase.Authenticated,
                    user = user,
                    isLoading = false
                )
            } catch (e: ApiError) {
                handleApiError(e)
            } catch (_: Exception) {
                uiState = uiState.copy(
                    isLoading = false,
                    errorMessage = "Проверьте подключение к сети"
                )
            }
        }
    }

    fun refreshProfile() {
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true)
            try {
                val user = authRepository.restoreSession()
                if (user != null) {
                    uiState = uiState.copy(user = user, isLoading = false)
                }
            } catch (_: Exception) {
                uiState = uiState.copy(isLoading = false)
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
            uiState = AuthUiState(phase = AuthPhase.Unauthenticated)
        }
    }

    fun clearError() {
        uiState = uiState.copy(errorMessage = null, fieldErrors = emptyMap())
    }

    private fun handleApiError(e: ApiError) {
        when (e) {
            is ApiError.Server -> {
                uiState = uiState.copy(
                    isLoading = false,
                    errorMessage = e.error.message,
                    fieldErrors = e.error.fields ?: emptyMap()
                )
            }
            is ApiError.Unauthorized -> {
                uiState = uiState.copy(
                    isLoading = false,
                    errorMessage = e.message
                )
            }
            else -> {
                uiState = uiState.copy(
                    isLoading = false,
                    errorMessage = e.message
                )
            }
        }
    }

    private fun validateLogin(email: String, password: String): Boolean {
        val errors = mutableMapOf<String, String>()
        if (!isValidEmail(email)) errors["email"] = "Введите корректный email"
        if (password.length < 8) errors["password"] = "Минимум 8 символов"
        if (errors.isNotEmpty()) {
            uiState = uiState.copy(fieldErrors = errors)
            return false
        }
        return true
    }

    private fun validateRegister(
        name: String,
        email: String,
        password: String,
        confirmPassword: String
    ): Boolean {
        val errors = mutableMapOf<String, String>()
        if (name.trim().length < 2) errors["name"] = "Введите имя не короче 2 символов"
        if (!isValidEmail(email)) errors["email"] = "Введите корректный email"
        if (password.length < 8) errors["password"] = "Минимум 8 символов"
        if (password.length > 128) errors["password"] = "Не более 128 символов"
        if (password != confirmPassword) errors["confirmPassword"] = "Пароли не совпадают"
        if (errors.isNotEmpty()) {
            uiState = uiState.copy(fieldErrors = errors)
            return false
        }
        return true
    }

    private fun isValidEmail(email: String): Boolean {
        return Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$").matches(email)
    }
}
