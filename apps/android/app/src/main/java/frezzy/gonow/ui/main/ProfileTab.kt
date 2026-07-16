package frezzy.gonow.ui.main

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import frezzy.gonow.models.User
import frezzy.gonow.ui.theme.*

@Composable
fun ProfileTab(
    user: User?,
    onRefresh: () -> Unit,
    onLogout: () -> Unit,
    isLoading: Boolean
) {
    AuthBackdrop {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 48.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(40.dp))

            Text(
                text = "Профиль",
                style = MaterialTheme.typography.headlineLarge
            )

            Spacer(modifier = Modifier.height(32.dp))

            GlassCard(modifier = Modifier.fillMaxWidth()) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Surface(
                        modifier = Modifier.size(72.dp),
                        shape = CircleShape,
                        color = Primary.copy(alpha = 0.12f)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Person,
                            contentDescription = null,
                            tint = Primary,
                            modifier = Modifier
                                .padding(16.dp)
                                .fillMaxSize()
                        )
                    }

                    Spacer(modifier = Modifier.height(14.dp))

                    Text(
                        text = user?.displayName ?: "...",
                        style = MaterialTheme.typography.headlineSmall
                    )

                    Spacer(modifier = Modifier.height(4.dp))

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = user?.email ?: "...",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        if (user != null) {
                            Icon(
                                imageVector = if (user.emailVerified) Icons.Filled.CheckCircle
                                else Icons.Filled.ErrorOutline,
                                contentDescription = null,
                                tint = if (user.emailVerified) Primary else Color(0xFFF59E0B),
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            GlassSecondaryButton(
                text = "Обновить профиль",
                onClick = onRefresh
            )

            Spacer(modifier = Modifier.height(12.dp))

            GlassSecondaryButton(
                text = "Выйти из аккаунта",
                onClick = onLogout,
                destructive = true
            )
        }
    }
}
