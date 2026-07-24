package frezzy.gonow.features.authentication

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.AuthRepository
import frezzy.gonow.core.MediaCache
import frezzy.gonow.core.throwIfCancellation
import frezzy.gonow.models.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class AuthUiState(
    val phase: AuthPhase = AuthPhase.Launching,
    val isLoginMode: Boolean = true,
    val isLoading: Boolean = false,
    val user: User? = null,
    val errorMessage: String? = null,
    val fieldErrors: Map<String, String> = emptyMap(),
    val pendingVerificationEmail: String? = null,
    val pendingDisplayName: String = "",
    val pendingUsername: String = "",
    val pendingPassword: String = "",
    val verificationCode: String = "",
    val showPasswordRecovery: Boolean = false,
    val recoveryEmail: String = "",
    val recoveryCode: String = "",
    val newPassword: String = "",
    val newConfirmation: String = "",
    val isRecoveryCodeSent: Boolean = false,
    val usernameAvailability: UsernameAvailability? = null,
    val isCheckingUsername: Boolean = false
)

data class ProfileMediaUiState(
    val profilePhotos: ProfilePhotos = ProfilePhotos(),
    val avatarBytes: ByteArray? = null,
    val photoContentFiles: Map<String, String> = emptyMap(),
    val unavailablePhotoIds: Set<String> = emptySet()
)

class AuthViewModel(
    private val authRepository: AuthRepository,
    private val mediaCache: MediaCache
) : ViewModel() {

    private val mutableUiState = MutableStateFlow(AuthUiState())
    val uiStateFlow = mutableUiState.asStateFlow()
    private var uiState: AuthUiState
        get() = mutableUiState.value
        set(value) { mutableUiState.value = value }

    private val mutableProfileMediaState = MutableStateFlow(ProfileMediaUiState())
    val profileMediaStateFlow = mutableProfileMediaState.asStateFlow()
    private var profileMediaState: ProfileMediaUiState
        get() = mutableProfileMediaState.value
        set(value) { mutableProfileMediaState.value = value }

    private var usernameCheckJob: Job? = null

    init { restoreSession() }

    fun retrySessionRestore() {
        uiState = uiState.copy(phase = AuthPhase.Launching, errorMessage = null)
        restoreSession()
    }

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
            } catch (error: Exception) {
                error.throwIfCancellation()
                uiState = uiState.copy(
                    phase = AuthPhase.RestoreFailed(error.message ?: "Нет соединения с сервером"),
                    errorMessage = error.message
                )
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
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
        }
    }

    fun register(name: String, username: String, email: String, password: String, confirmPassword: String) {
        if (!validateRegister(name, username, email, password, confirmPassword)) return
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null, fieldErrors = emptyMap())
            try {
                val normalizedUsername = UsernameRules.normalize(username)
                val data = authRepository.register(name, normalizedUsername, email, password)
                uiState = uiState.copy(
                    isLoading = false,
                    pendingVerificationEmail = data.email,
                    pendingDisplayName = name.trim(),
                    pendingUsername = normalizedUsername,
                    pendingPassword = password,
                    verificationCode = ""
                )
            } catch (e: ApiError) { handleApiError(e) }
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
        }
    }

    fun checkUsername(value: String) {
        usernameCheckJob?.cancel()
        val username = UsernameRules.normalize(value)
        val validationError = UsernameRules.validationMessage(username)
        if (validationError != null) {
            uiState = uiState.copy(
                usernameAvailability = null,
                isCheckingUsername = false,
                fieldErrors = uiState.fieldErrors + ("username" to validationError)
            )
            return
        }
        uiState = uiState.copy(
            usernameAvailability = null,
            isCheckingUsername = true,
            fieldErrors = uiState.fieldErrors - "username"
        )
        usernameCheckJob = viewModelScope.launch {
            delay(350)
            try {
                val result = authRepository.usernameAvailability(username)
                uiState = uiState.copy(
                    usernameAvailability = result,
                    isCheckingUsername = false,
                    fieldErrors = if (result.available) {
                        uiState.fieldErrors - "username"
                    } else {
                        uiState.fieldErrors + ("username" to (result.message ?: "Этот username уже занят"))
                    }
                )
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                uiState = uiState.copy(isCheckingUsername = false)
            }
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
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
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
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
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
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(isLoading = false, errorMessage = "Проверьте подключение к сети") }
        }
    }

    fun resendVerificationCode() {
        val email = uiState.pendingVerificationEmail ?: return
        val name = uiState.pendingDisplayName.ifEmpty { "User" }
        val username = uiState.pendingUsername
        val password = uiState.pendingPassword.ifEmpty { "resend-placeholder-8" }
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            try { authRepository.register(name, username, email, password); uiState = uiState.copy(isLoading = false, errorMessage = "Код отправлен повторно") }
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(isLoading = false, errorMessage = "Не удалось отправить код. Попробуйте позже.") }
        }
    }

    // --- Profile ---

    fun refreshProfile() {
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true)
            try {
                val user = authRepository.currentUser()
                uiState = uiState.copy(user = user, isLoading = false)
            } catch (error: Exception) {
                error.throwIfCancellation()
                uiState = uiState.copy(
                    isLoading = false,
                    errorMessage = error.message ?: "Не удалось обновить профиль"
                )
            }
        }
    }

    fun updateProfile(request: UpdateProfileRequest) {
        viewModelScope.launch {
            uiState = uiState.copy(isLoading = true, errorMessage = null)
            try {
                val user = authRepository.updateProfile(request)
                uiState = uiState.copy(user = user, isLoading = false)
            } catch (e: ApiError) { uiState = uiState.copy(isLoading = false, errorMessage = e.message) }
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(isLoading = false, errorMessage = "Не удалось сохранить профиль") }
        }
    }

    fun reloadProfileMedia() {
        viewModelScope.launch {
            try {
                val media = authRepository.getProfilePhotos()
                // Keep only content for photos still in the list
                val validIds = (
                    media.photos.map { it.id } +
                        media.avatars.map { it.id } +
                        listOfNotNull(media.avatar?.id)
                    ).toSet()
                val filteredContent = profileMediaState.photoContentFiles.filter { it.key in validIds }
                profileMediaState = ProfileMediaUiState(
                    profilePhotos = media,
                    avatarBytes = profileMediaState.avatarBytes,
                    photoContentFiles = filteredContent,
                    unavailablePhotoIds = profileMediaState.unavailablePhotoIds.intersect(validIds)
                )
                media.avatar?.let { photo ->
                    try {
                        val avatar = mediaCache.get(photo.contentPath) {
                            authRepository.getPhotoContent(photo.id)
                        }
                        profileMediaState = profileMediaState.copy(avatarBytes = avatar)
                    } catch (error: Exception) {
                        error.throwIfCancellation()
                        // Media storage may be unavailable while the core API remains healthy.
                    }
                }
            } catch (e: Exception) {
                e.throwIfCancellation()
                uiState = uiState.copy(errorMessage = e.message ?: "Не удалось загрузить медиа профиля")
            }
        }
    }

    fun uploadAvatar(imageBytes: ByteArray) {
        viewModelScope.launch {
            try {
                authRepository.uploadAvatar(imageBytes)
                reloadProfileMedia()
            } catch (e: ApiError) { uiState = uiState.copy(errorMessage = mediaUploadMessage(e)) }
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(errorMessage = "Не удалось загрузить аватар") }
        }
    }

    fun uploadPhoto(imageBytes: ByteArray) {
        viewModelScope.launch {
            try {
                authRepository.uploadPhoto(imageBytes)
                reloadProfileMedia()
            } catch (e: ApiError) { uiState = uiState.copy(errorMessage = mediaUploadMessage(e)) }
            catch (error: Exception) { error.throwIfCancellation(); uiState = uiState.copy(errorMessage = "Не удалось загрузить фото") }
        }
    }

    fun deletePhoto(photoId: String) {
        viewModelScope.launch {
            try {
                authRepository.deletePhoto(photoId)
                reloadProfileMedia()
            } catch (error: Exception) {
                error.throwIfCancellation()
                uiState = uiState.copy(
                    errorMessage = error.message ?: "Не удалось удалить фотографию"
                )
            }
        }
    }

    fun updatePhotoDescription(photoId: String, description: String?) {
        viewModelScope.launch {
            try {
                val updated = authRepository.updatePhotoDescription(photoId, description)
                replaceProfilePhoto(updated)
            } catch (error: Exception) {
                error.throwIfCancellation()
                uiState = uiState.copy(errorMessage = error.message ?: "Не удалось сохранить описание")
            }
        }
    }

    fun togglePhotoLike(photoId: String) {
        val photo = (profileMediaState.profilePhotos.photos + profileMediaState.profilePhotos.avatars)
            .firstOrNull { it.id == photoId } ?: return
        viewModelScope.launch {
            try {
                val engagement = authRepository.setPhotoLiked(photoId, !photo.isLiked)
                replaceProfilePhoto(photo.copy(likeCount = engagement.likeCount, isLiked = engagement.isLiked))
            } catch (error: Exception) {
                error.throwIfCancellation()
                uiState = uiState.copy(errorMessage = error.message ?: "Не удалось изменить отметку")
            }
        }
    }

    private fun replaceProfilePhoto(updated: ProfilePhoto) {
        val media = profileMediaState.profilePhotos
        profileMediaState = profileMediaState.copy(
            profilePhotos = media.copy(
                avatar = media.avatar?.let { if (it.id == updated.id) updated else it },
                avatars = media.avatars.map { if (it.id == updated.id) updated else it },
                photos = media.photos.map { if (it.id == updated.id) updated else it }
            )
        )
    }

    fun loadPhotoContent(photoId: String) {
        if (profileMediaState.photoContentFiles.containsKey(photoId)) return
        val photo = (
            profileMediaState.profilePhotos.photos +
                profileMediaState.profilePhotos.avatars +
                listOfNotNull(profileMediaState.profilePhotos.avatar)
        ).firstOrNull { it.id == photoId } ?: return
        profileMediaState = profileMediaState.copy(
            unavailablePhotoIds = profileMediaState.unavailablePhotoIds - photoId
        )
        viewModelScope.launch {
            try {
                val file = mediaCache.file(photo.contentPath) { authRepository.getPhotoContent(photoId) }
                profileMediaState = profileMediaState.copy(
                    photoContentFiles = profileMediaState.photoContentFiles + (photoId to file.absolutePath)
                )
            } catch (error: Exception) {
                error.throwIfCancellation()
                profileMediaState = profileMediaState.copy(
                    unavailablePhotoIds = profileMediaState.unavailablePhotoIds + photoId
                )
            }
        }
    }

    private fun mediaUploadMessage(error: ApiError): String =
        if (error is ApiError.Server && error.error.code == "OBJECT_STORAGE_UNAVAILABLE") {
            "Хранилище фотографий не запущено на локальном сервере."
        } else {
            error.message ?: "Не удалось загрузить фотографию"
        }

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
            try {
                mediaCache.clear()
            } finally {
                uiState = AuthUiState(phase = AuthPhase.Unauthenticated)
                profileMediaState = ProfileMediaUiState()
            }
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

    private fun validateRegister(name: String, username: String, email: String, password: String, confirmPassword: String): Boolean {
        val errors = mutableMapOf<String, String>()
        if (name.trim().length < 2) errors["name"] = "Введите имя не короче 2 символов"
        UsernameRules.validationMessage(username)?.let { errors["username"] = it }
        if (uiState.usernameAvailability?.available == false) {
            errors["username"] = uiState.usernameAvailability?.message ?: "Этот username уже занят"
        }
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
