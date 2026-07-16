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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.ui.theme.*

@Composable
fun RegisterScreen(
    onRegister: (String, String, String, String) -> Unit,
    onNavigateToLogin: () -> Unit,
    isLoading: Boolean,
    fieldErrors: Map<String, String>,
    errorMessage: String?
) {
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }

    AuthBackdrop {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(80.dp))

            MapPointMarker(modifier = Modifier.size(84.dp))
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Ваши планы начинаются здесь",
                style = MaterialTheme.typography.headlineLarge,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Создайте аккаунт \u2014 это займёт меньше минуты.",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )

            Spacer(modifier = Modifier.height(32.dp))

            RegAuthField(
                label = "Ваше имя",
                value = name,
                onValueChange = { name = it },
                placeholder = "Имя",
                error = fieldErrors["name"]
            )

            Spacer(modifier = Modifier.height(16.dp))

            RegAuthField(
                label = "Email",
                value = email,
                onValueChange = { email = it },
                placeholder = "Email",
                keyboardType = KeyboardType.Email,
                error = fieldErrors["email"]
            )

            Spacer(modifier = Modifier.height(16.dp))

            RegAuthPasswordField(
                label = "Пароль",
                value = password,
                onValueChange = { password = it },
                isVisible = passwordVisible,
                onToggleVisibility = { passwordVisible = !passwordVisible },
                error = fieldErrors["password"]
            )

            Spacer(modifier = Modifier.height(16.dp))

            RegAuthPasswordField(
                label = "Повторите пароль",
                value = confirmPassword,
                onValueChange = { confirmPassword = it },
                isVisible = passwordVisible,
                onToggleVisibility = { passwordVisible = !passwordVisible },
                error = fieldErrors["confirmPassword"]
            )

            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = "Минимум 8 символов. Не используйте очевидный пароль.",
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.fillMaxWidth()
            )

            if (errorMessage != null) {
                Spacer(modifier = Modifier.height(12.dp))
                ErrorMessage(text = errorMessage)
            }

            Spacer(modifier = Modifier.height(24.dp))

            GradientPrimaryButton(
                text = "Создать аккаунт",
                onClick = { onRegister(name, email, password, confirmPassword) },
                loading = isLoading
            )

            Spacer(modifier = Modifier.height(16.dp))

            TextButton(
                onClick = onNavigateToLogin,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "Уже есть аккаунт? ",
                    color = TextSecondary,
                    fontSize = 14.sp
                )
                Text(
                    text = "Войти",
                    color = Primary,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp
                )
            }

            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}

@Composable
private fun RegAuthField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    error: String?
) {
    val shape = RoundedCornerShape(18.dp)

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
            placeholder = { Text(placeholder, color = TextSecondary) },
            modifier = Modifier.fillMaxWidth(),
            shape = shape,
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = Border,
                focusedBorderColor = Primary,
                unfocusedContainerColor = GlassBackground,
                focusedContainerColor = GlassBackground,
                cursorColor = Primary,
                focusedTextColor = TextPrimary,
                unfocusedTextColor = TextPrimary,
                unfocusedPlaceholderColor = TextSecondary,
                focusedPlaceholderColor = TextSecondary,
                errorBorderColor = Danger,
                errorCursorColor = Danger,
                errorTextColor = TextPrimary,
                errorPlaceholderColor = TextSecondary
            ),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            supportingText = if (error != null) {
                { ErrorMessage(text = error) }
            } else null
        )
    }
}

@Composable
private fun RegAuthPasswordField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    isVisible: Boolean,
    onToggleVisibility: () -> Unit,
    error: String?
) {
    val shape = RoundedCornerShape(18.dp)

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
            placeholder = { Text("Пароль", color = TextSecondary) },
            modifier = Modifier.fillMaxWidth(),
            shape = shape,
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = Border,
                focusedBorderColor = Primary,
                unfocusedContainerColor = GlassBackground,
                focusedContainerColor = GlassBackground,
                cursorColor = Primary,
                focusedTextColor = TextPrimary,
                unfocusedTextColor = TextPrimary,
                unfocusedPlaceholderColor = TextSecondary,
                focusedPlaceholderColor = TextSecondary,
                errorBorderColor = Danger,
                errorCursorColor = Danger,
                errorTextColor = TextPrimary,
                errorPlaceholderColor = TextSecondary
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
                        tint = TextSecondary
                    )
                }
            },
            supportingText = if (error != null) {
                { ErrorMessage(text = error) }
            } else null
        )
    }
}
