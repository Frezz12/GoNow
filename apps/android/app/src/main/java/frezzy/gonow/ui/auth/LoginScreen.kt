package frezzy.gonow.ui.auth

import androidx.compose.foundation.clickable
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
fun LoginScreen(
    onLogin: (String, String) -> Unit,
    onNavigateToRegister: () -> Unit,
    isLoading: Boolean,
    fieldErrors: Map<String, String>,
    errorMessage: String?
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
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
                text = "Рядом \u2014 интереснее",
                style = MaterialTheme.typography.headlineLarge,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Войдите, чтобы находить людей для активностей рядом.",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )

            Spacer(modifier = Modifier.height(32.dp))

            AuthField(
                label = "Логин",
                value = email,
                onValueChange = { email = it },
                placeholder = "Email",
                keyboardType = KeyboardType.Email,
                error = fieldErrors["email"]
            )

            Spacer(modifier = Modifier.height(16.dp))

            AuthPasswordField(
                label = "Пароль",
                value = password,
                onValueChange = { password = it },
                isVisible = passwordVisible,
                onToggleVisibility = { passwordVisible = !passwordVisible },
                error = fieldErrors["password"]
            )

            if (errorMessage != null) {
                Spacer(modifier = Modifier.height(12.dp))
                ErrorMessage(text = errorMessage)
            }

            Spacer(modifier = Modifier.height(24.dp))

            GradientPrimaryButton(
                text = "Войти",
                onClick = { onLogin(email, password) },
                loading = isLoading
            )

            Spacer(modifier = Modifier.height(16.dp))

            TextButton(
                onClick = onNavigateToRegister,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "Впервые в GoNow? ",
                    color = TextSecondary,
                    fontSize = 14.sp
                )
                Text(
                    text = "Создать аккаунт",
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
private fun AuthField(
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
private fun AuthPasswordField(
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
