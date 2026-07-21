package frezzy.gonow.features.map

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import frezzy.gonow.models.ActivityCategory
import frezzy.gonow.models.MapFilterState
import frezzy.gonow.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapFilterSheet(
    currentFilters: MapFilterState,
    onApply: (MapFilterState) -> Unit,
    onDismiss: () -> Unit
) {
    var draft by remember { mutableStateOf(currentFilters) }
    var selectedTimeIndex by remember {
        mutableIntStateOf(
            when (currentFilters.startsWithinHours) {
                1 -> 1
                12 -> 2
                24 -> 3
                else -> 0
            }
        )
    }
    val sheetState = rememberModalBottomSheetState()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Background,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp)
        ) {
            Text(
                text = "Фильтры",
                style = MaterialTheme.typography.headlineSmall
            )

            Spacer(modifier = Modifier.height(20.dp))

            // Categories
            Text(
                text = "Категории",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(8.dp))

            val categories = ActivityCategory.entries
            categories.chunked(3).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    row.forEach { category ->
                        val isSelected = category in draft.categories
                        FilterChip(
                            selected = isSelected,
                            onClick = {
                                val newCategories = if (isSelected) {
                                    draft.categories - category
                                } else {
                                    draft.categories + category
                                }
                                draft = draft.copy(categories = newCategories)
                            },
                            label = { Text(category.titleRu, fontSize = MaterialTheme.typography.bodySmall.fontSize) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                    // Fill remaining space if row is not full
                    repeat(3 - row.size) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
                Spacer(modifier = Modifier.height(4.dp))
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Time filter
            Text(
                text = "Начало",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(8.dp))

            val timeOptions = listOf("Любое время", "Следующий час", "Сегодня", "Следующий день")
            val timeValues = listOf(null, 1, 12, 24)

            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                timeOptions.forEachIndexed { index, label ->
                    SegmentedButton(
                        selected = selectedTimeIndex == index,
                        onClick = {
                            selectedTimeIndex = index
                            draft = draft.copy(startsWithinHours = timeValues[index])
                        },
                        shape = SegmentedButtonDefaults.itemShape(index, timeOptions.size)
                    ) {
                        Text(label, fontSize = MaterialTheme.typography.labelSmall.fontSize)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Only available
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Только со свободными местами",
                    style = MaterialTheme.typography.bodyMedium
                )
                Switch(
                    checked = draft.onlyAvailable,
                    onCheckedChange = { draft = draft.copy(onlyAvailable = it) }
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedButton(
                    onClick = { draft = MapFilterState() },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text("Сбросить")
                }

                Button(
                    onClick = { onApply(draft) },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(16.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary
                    )
                ) {
                    Text("Применить")
                }
            }
        }
    }
}
