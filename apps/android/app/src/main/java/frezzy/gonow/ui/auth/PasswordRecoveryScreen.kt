package frezzy.gonow.ui.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PasswordRecoveryScreen(
    email: String,
    onEmailChange: (String) -> Unit,
    code: String,
    onCodeChange: (String) -> Unit,
    newPassword: String,
    onNewPasswordChange: (String) -> Unit,
    confirmation: String,
    onConfirmationChange: (String) -> Unit,
    isCodeSent: Boolean,
    onRequestCode: () -> Unit,
    onResetPassword: () -> Unit,
    onDismiss: () -> Unit,
    isLoading: Boolean,
    errorMessage: String?
) {
    var passwordVisible by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = if (isCodeSent) "Установите новый пароль" else "Восстановление пароля",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = if (isCodeSent)
                    "Введите код из письма и придумайте новый пароль."
                else
                    "Введите email. Мы отправим код для восстановления.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(24.dp))

            if (!isCodeSent) {
                RecField(
                    label = "Email",
                    value = email,
                    onValueChange = onEmailChange,
                    placeholder = "Email",
                    keyboardType = KeyboardType.Email
                )
            } else {
                RecField(
                    label = "Код из письма",
                    value = code,
                    onValueChange = { if (it.length <= 6) onCodeChange(it.filter { c -> c.isDigit() }) },
                    placeholder = "000000",
                    keyboardType = KeyboardType.Number
                )

                Spacer(modifier = Modifier.height(16.dp))

                RecPasswordField(
                    label = "Новый пароль",
                    value = newPassword,
                    onValueChange = onNewPasswordChange,
                    isVisible = passwordVisible,
                    onToggleVisibility = { passwordVisible = !passwordVisible }
                )

                Spacer(modifier = Modifier.height(16.dp))

                RecPasswordField(
                    label = "Повторите пароль",
                    value = confirmation,
                    onValueChange = onConfirmationChange,
                    isVisible = passwordVisible,
                    onToggleVisibility = { passwordVisible = !passwordVisible }
                )
            }

            if (errorMessage != null) {
                Spacer(modifier = Modifier.height(8.dp))
                ErrorMessage(text = errorMessage)
            }

            Spacer(modifier = Modifier.height(20.dp))

            GradientPrimaryButton(
                text = when {
                    isLoading -> "Подождите..."
                    isCodeSent -> "Изменить пароль"
                    else -> "Получить код"
                },
                onClick = { if (isCodeSent) onResetPassword() else onRequestCode() },
                loading = isLoading,
                enabled = !isLoading
            )

            if (isCodeSent) {
                Spacer(modifier = Modifier.height(12.dp))

                TextButton(
                    onClick = onRequestCode,
                    enabled = !isLoading,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = "Отправить код ещё раз",
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            TextButton(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "Отмена",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 14.sp
                )
            }
        }
    }
}

@Composable
private fun RecField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text
) {
    Column {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(bottom = 6.dp)
        )
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant) },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                focusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                errorBorderColor = MaterialTheme.colorScheme.error,
                errorTextColor = MaterialTheme.colorScheme.onSurface
            ),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType)
        )
    }
}

@Composable
private fun RecPasswordField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    isVisible: Boolean,
    onToggleVisibility: () -> Unit
) {
    Column {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(bottom = 6.dp)
        )
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text("Пароль", color = MaterialTheme.colorScheme.onSurfaceVariant) },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                focusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                errorBorderColor = MaterialTheme.colorScheme.error,
                errorTextColor = MaterialTheme.colorScheme.onSurface
            ),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            visualTransformation = if (isVisible) VisualTransformation.None
            else PasswordVisualTransformation(),
            trailingIcon = {
                IconButton(onClick = onToggleVisibility) {
                    Icon(
                        imageVector = if (isVisible) Icons.Filled.VisibilityOff
                        else Icons.Filled.Visibility,
                        contentDescription = if (isVisible) "Скрыть пароль"
                        else "Показать пароль",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        )
    }
}
