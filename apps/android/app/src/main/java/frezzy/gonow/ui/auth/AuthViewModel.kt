package frezzy.gonow.ui.auth

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.AuthRepository
import frezzy.gonow.models.*
import kotlinx.coroutines.launch

data class AuthUiState(
    val phase: AuthPhase = AuthPhase.Launching,
    val isLoginMode: Boolean = true,
    val isLoading: Boolean = false,
    val user: User? = null,
    val errorMessage: String? = null,
    val fieldErrors: Map<String, String> = emptyMap(),
    val pendingVerificationEmail: String? = null,
    val pendingDisplayName: String = "",
    val pendingPassword: String = "",
    val verificationCode: String = "",
    val showPasswordRecovery: Boolean = false,
    val recoveryEmail: String = "",
    val recoveryCode: String = "",
    val newPassword: String = "",
    val newConfirmation: String = "",
    val isRecoveryCodeSent: Boolean = false,
    // Profile
    val profilePhotos: ProfilePhotos = ProfilePhotos(),
    val avatarBytes: ByteArray? = null
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AuthUiState) return false
        return phase == other.phase && isLoginMode == other.isLoginMode && isLoading == other.isLoading
            && user == other.user && errorMessage == other.errorMessage && fieldErrors == other.fieldErrors
            && pendingVerificationEmail == other.pendingVerificationEmail
            && showPasswordRecovery == other.showPasswordRecovery
            && isRecoveryCodeSent == other.isRecoveryCodeSent
            && profilePhotos == other.profilePhotos
            && avatarBytes?.contentEquals(other.avatarBytes ?: ByteArray(0)) == true
    }
    override fun hashCode(): Int = phase.hashCode()
}

class AuthViewModel(private val authRepository: AuthRepository) : ViewModel() {

    var uiState by mutableStateOf(AuthUiState())
        private set

    init { restoreSession() }

    private fun restoreSession() {
        viewModelScope.launch {
            try {
                val user = authRepository.restoreSession()
                if (user != null) {
                    uiState = uiState.copy(phase = AuthPhase.Authenticated, user = user)
                    reloadProfileMedia()
                } else {
                    uiState = uiState.copy(phase = AuthPhase.Unauthenticated)
                }
            } catch (_: Exception) {
                uiState = uiState.copy(phase = AuthPhase.Unauthenticated)
            }
        }
    }

    fun toggleMode() {
        uiState = uiState.copy(isLoginMode = !uiState.isLoginMode, errorMessage = null, fieldErrors = emptyMap())
    }

    fun login(email: String, password: String) {
        if (!validateLogin(email, password)) return
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null, fieldErrors = emptyMap())
            try {
                val user = authRepository.login(email, password)
                uiState = uiState.copy(phase = AuthPhase.Authenticated, user = user, isLoading = false)
                reloadProfileMedia()
            } catch (e: ApiError) { handleApiError(e) }
            catch (_: Exception) { uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
        }
    }

    fun register(name: String, email: String, password: String, confirmPassword: String) {
        if (!validateRegister(name, email, password, confirmPassword)) return
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null, fieldErrors = emptyMap())
            try {
                val data = authRepository.register(name, email, password)
                uiState = uiState.copy(isLoading = false, pendingVerificationEmail = data.email, pendingDisplayName = name.trim(), pendingPassword = password, verificationCode = "")
            } catch (e: ApiError) { handleApiError(e) }
            catch (_: Exception) { uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
        }
    }

    fun onVerificationCodeChange(code: String) { uiState = uiState.copy(verificationCode = code, errorMessage = null) }

    fun verifyEmail() {
        val email = uiState.pendingVerificationEmail ?: return
        val code = uiState.verificationCode
        if (code.length != 6) { uiState = uiState.copy(errorMessage = "Введите шестизначный код"); return }
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            try {
                val user = authRepository.verifyEmail(email, code)
                uiState = uiState.copy(phase = AuthPhase.Authenticated, user = user, isLoading = false, pendingVerificationEmail = null)
                reloadProfileMedia()
            } catch (e: ApiError) { uiState = uiState.copy(isLoading = false, errorMessage = e.message) }
            catch (_: Exception) { uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
        }
    }

    fun dismissVerification() { uiState = uiState.copy(pendingVerificationEmail = null, verificationCode = "", errorMessage = null) }

    fun showPasswordRecovery() { uiState = uiState.copy(showPasswordRecovery = true, isRecoveryCodeSent = false, recoveryCode = "", newPassword = "", newConfirmation = "", errorMessage = null) }
    fun dismissPasswordRecovery() { uiState = uiState.copy(showPasswordRecovery = false, isRecoveryCodeSent = false, recoveryEmail = "", recoveryCode = "", newPassword = "", newConfirmation = "", errorMessage = null, fieldErrors = emptyMap()) }
    fun onRecoveryEmailChange(email: String) { uiState = uiState.copy(recoveryEmail = email, errorMessage = null, fieldErrors = emptyMap()) }
    fun onRecoveryCodeChange(code: String) { uiState = uiState.copy(recoveryCode = code, errorMessage = null) }
    fun onNewPasswordChange(password: String) { uiState = uiState.copy(newPassword = password, errorMessage = null) }
    fun onNewConfirmationChange(confirmation: String) { uiState = uiState.copy(newConfirmation = confirmation, errorMessage = null) }

    fun requestPasswordReset() {
        val email = uiState.recoveryEmail.trim()
        if (!isValidEmail(email)) { uiState = uiState.copy(errorMessage = "Введите корректный email"); return }
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            try { authRepository.requestPasswordReset(email); uiState = uiState.copy(isLoading = false, isRecoveryCodeSent = true) }
            catch (e: ApiError) { uiState = uiState.copy(isLoading = false, errorMessage = e.message) }
            catch (_: Exception) { uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
        }
    }

    fun resetPassword() {
        val email = uiState.recoveryEmail.trim(); val code = uiState.recoveryCode; val password = uiState.newPassword; val confirmation = uiState.newConfirmation
        if (code.length != 6) { uiState = uiState.copy(errorMessage = "Введите шестизначный код из письма"); return }
        validatePassword(password)?.let { uiState = uiState.copy(errorMessage = it); return }
        if (password != confirmation) { uiState = uiState.copy(errorMessage = "Пароли не совпадают"); return }
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            try {
                val user = authRepository.resetPassword(email, code, password)
                uiState = uiState.copy(phase = AuthPhase.Authenticated, user = user, isLoading = false, showPasswordRecovery = false)
                reloadProfileMedia()
            } catch (e: ApiError) { uiState = uiState.copy(isLoading = false, errorMessage = e.message) }
            catch (_: Exception) { uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
        }
    }

    fun resendVerificationCode() {
        val email = uiState.pendingVerificationEmail ?: return
        val name = uiState.pendingDisplayName.ifEmpty { "User" }
        val password = uiState.pendingPassword.ifEmpty { "resend-placeholder-8" }
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            try { authRepository.register(name, email, password); uiState = uiState.copy(isLoading = false, errorMessage = "Код отправлен повторно") }
            catch (_: Exception) { uiState = uiState.copy(isLoading = false, errorMessage = "Не удалось отправить код. Попробуйте позже.") }
        }
    }

    // --- Profile ---

    fun refreshProfile() {
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true)
            try {
                val user = authRepository.currentUser()
                uiState = uiState.copy(user = user, isLoading = false)
            } catch (_: Exception) { uiState = uiState.copy(isLoading = false) }
        }
    }

    fun updateProfile(request: UpdateProfileRequest) {
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            try {
                val user = authRepository.updateProfile(request)
                uiState = uiState.copy(user = user, isLoading = false)
            } catch (e: ApiError) { uiState = uiState.copy(isLoading = false, errorMessage = e.message) }
            catch (_: Exception) { uiState = uiState.copy(isLoading = false, errorMessage = "Не удалось сохранить профиль") }
        }
    }

    fun reloadProfileMedia() {
        viewModelScope.launch {
            try {
                val media = authRepository.getProfilePhotos()
                val avatar = media.avatar?.let { authRepository.getPhotoContent(it.contentPath) }
                uiState = uiState.copy(profilePhotos = media, avatarBytes = avatar)
            } catch (_: Exception) {
                uiState = uiState.copy(profilePhotos = ProfilePhotos(), avatarBytes = null)
            }
        }
    }

    fun uploadAvatar(imageBytes: ByteArray) {
        viewModelScope.launch {
            try {
                authRepository.uploadAvatar(imageBytes)
                reloadProfileMedia()
            } catch (e: ApiError) { uiState = uiState.copy(errorMessage = e.message) }
            catch (_: Exception) { uiState = uiState.copy(errorMessage = "Не удалось загрузить аватар") }
        }
    }

    fun uploadPhoto(imageBytes: ByteArray) {
        viewModelScope.launch {
            try {
                authRepository.uploadPhoto(imageBytes)
                reloadProfileMedia()
            } catch (e: ApiError) { uiState = uiState.copy(errorMessage = e.message) }
            catch (_: Exception) { uiState = uiState.copy(errorMessage = "Не удалось загрузить фото") }
        }
    }

    fun deletePhoto(photoId: String) {
        viewModelScope.launch {
            try {
                authRepository.deletePhoto(photoId)
                reloadProfileMedia()
            } catch (_: Exception) { }
        }
    }

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
            uiState = AuthUiState(phase = AuthPhase.Unauthenticated)
        }
    }

    fun clearError() { uiState = uiState.copy(errorMessage = null, fieldErrors = emptyMap()) }

    private fun handleApiError(e: ApiError) {
        when (e) {
            is ApiError.Server -> uiState = uiState.copy(isLoading = false, errorMessage = e.error.message, fieldErrors = e.error.fields ?: emptyMap())
            else -> uiState = uiState.copy(isLoading = false, errorMessage = e.message)
        }
    }

    private fun validateLogin(email: String, password: String): Boolean {
        val errors = mutableMapOf<String, String>()
        if (!isValidEmail(email)) errors["email"] = "Введите корректный email"
        if (password.length < 8) errors["password"] = "Минимум 8 символов"
        if (errors.isNotEmpty()) { uiState = uiState.copy(fieldErrors = errors); return false }; return true
    }

    private fun validateRegister(name: String, email: String, password: String, confirmPassword: String): Boolean {
        val errors = mutableMapOf<String, String>()
        if (name.trim().length < 2) errors["name"] = "Введите имя не короче 2 символов"
        if (!isValidEmail(email)) errors["email"] = "Введите корректный email"
        validatePassword(password)?.let { errors["password"] = it }
        if (password != confirmPassword) errors["confirmPassword"] = "Пароли не совпадают"
        if (errors.isNotEmpty()) { uiState = uiState.copy(fieldErrors = errors); return false }; return true
    }

    private fun validatePassword(password: String): String? {
        if (password.length < 8) return "Минимум 8 символов"
        if (password.length > 128) return "Не более 128 символов"
        return null
    }

    private fun isValidEmail(email: String): Boolean = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$").matches(email)
}
