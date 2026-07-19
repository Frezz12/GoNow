package frezzy.gonow.ui.auth

import androidx.compose.foundation.background
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.ui.theme.*

@Composable
fun LoginScreen(
    onLogin: (String, String) -> Unit,
    onNavigateToRegister: () -> Unit,
    onForgotPassword: () -> Unit,
    isLoading: Boolean,
    fieldErrors: Map<String, String>,
    errorMessage: String?
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(80.dp))

            MapPointMarker(modifier = Modifier.size(72.dp))
            Spacer(modifier = Modifier.height(12.dp))
            Text("Рядом — интереснее", style = MaterialTheme.typography.headlineLarge, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Spacer(modifier = Modifier.height(6.dp))
            Text("Войдите, чтобы находить людей для активностей рядом.", style = MaterialTheme.typography.bodyMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)

            Spacer(modifier = Modifier.height(24.dp))

            AuthField("Логин", email, { email = it }, "Email", KeyboardType.Email, fieldErrors["email"])
            Spacer(modifier = Modifier.height(16.dp))
            AuthPasswordField("Пароль", password, { password = it }, passwordVisible, { passwordVisible = !passwordVisible }, fieldErrors["password"])

            Spacer(modifier = Modifier.height(4.dp))
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                TextButton(
                    onClick = onForgotPassword,
                    contentPadding = PaddingValues(horizontal = 4.dp)
                ) {
                    Text(
                        "Забыли пароль?",
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Medium,
                        fontSize = 13.sp
                    )
                }
            }

            if (errorMessage != null) {
                Spacer(modifier = Modifier.height(8.dp))
                ErrorMessage(text = errorMessage)
            }

            Spacer(modifier = Modifier.height(16.dp))
            GradientPrimaryButton(text = "Войти", onClick = { onLogin(email, password) }, loading = isLoading)

            Spacer(modifier = Modifier.height(12.dp))
            TextButton(onClick = onNavigateToRegister, modifier = Modifier.fillMaxWidth()) {
                Text("Впервые в GoNow? ", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
                Text("Создать аккаунт", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun AuthField(label: String, value: String, onValueChange: (String) -> Unit, placeholder: String, keyboardType: KeyboardType = KeyboardType.Text, error: String?) {
    Column {
        Text(label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, modifier = Modifier.padding(bottom = 6.dp))
        OutlinedTextField(
            value = value, onValueChange = onValueChange,
            placeholder = { Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant) },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                cursorColor = MaterialTheme.colorScheme.primary,
                focusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                focusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                errorBorderColor = MaterialTheme.colorScheme.error,
                errorCursorColor = MaterialTheme.colorScheme.error,
                errorTextColor = MaterialTheme.colorScheme.onSurface,
                errorPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            supportingText = if (error != null) {{ ErrorMessage(text = error) }} else null
        )
    }
}

@Composable
private fun AuthPasswordField(label: String, value: String, onValueChange: (String) -> Unit, isVisible: Boolean, onToggleVisibility: () -> Unit, error: String?) {
    Column {
        Text(label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, modifier = Modifier.padding(bottom = 6.dp))
        OutlinedTextField(
            value = value, onValueChange = onValueChange,
            placeholder = { Text("Пароль", color = MaterialTheme.colorScheme.onSurfaceVariant) },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                cursorColor = MaterialTheme.colorScheme.primary,
                focusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                unfocusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                focusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                errorBorderColor = MaterialTheme.colorScheme.error,
                errorCursorColor = MaterialTheme.colorScheme.error,
                errorTextColor = MaterialTheme.colorScheme.onSurface,
                errorPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            visualTransformation = if (isVisible) VisualTransformation.None else PasswordVisualTransformation(),
            trailingIcon = {
                IconButton(onClick = onToggleVisibility) {
                    Icon(
                        if (isVisible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                        contentDescription = if (isVisible) "Скрыть пароль" else "Показать пароль",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            },
            supportingText = if (error != null) {{ ErrorMessage(text = error) }} else null
        )
    }
}
