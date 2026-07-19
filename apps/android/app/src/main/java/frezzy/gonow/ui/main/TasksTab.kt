package frezzy.gonow.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import frezzy.gonow.ui.theme.*

@Composable
fun TasksTab() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 48.dp)
    ) {
        Spacer(modifier = Modifier.height(40.dp))

        Text(
            text = "Ближайшие планы",
            style = MaterialTheme.typography.headlineLarge
        )

        Spacer(modifier = Modifier.height(20.dp))

        TaskPreviewCard(
            icon = Icons.Filled.DirectionsWalk,
            title = "Прогулка после работы",
            subtitle = "Сегодня, 19:00 — рядом"
        )

        Spacer(modifier = Modifier.height(12.dp))

        TaskPreviewCard(
            icon = Icons.Filled.LocalCafe,
            title = "Кофе и знакомство",
            subtitle = "Завтра, 12:30 — центр города"
        )

        Spacer(modifier = Modifier.height(20.dp))

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
        ) {
            Text(
                text = "Здесь будут ваши активности. Создайте первую!",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(16.dp)
            )
        }
    }
}
