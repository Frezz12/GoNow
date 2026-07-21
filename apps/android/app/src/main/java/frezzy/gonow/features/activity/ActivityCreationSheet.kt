package frezzy.gonow.features.activity

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import frezzy.gonow.models.ActivityCategory
import frezzy.gonow.models.MapActivityResponse
import frezzy.gonow.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityCreationSheet(
    viewModel: ActivityCreationViewModel,
    locationProvider: frezzy.gonow.core.location.DeviceLocationProvider,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

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
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Новая активность",
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Filled.Close, contentDescription = "Закрыть")
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            WizardProgressBar(
                step = viewModel.currentStep,
                onSelect = { newStep ->
                    if (newStep.index < viewModel.step) {
                        viewModel.moveBack()
                    }
                }
            )

            Spacer(modifier = Modifier.height(20.dp))

            when (viewModel.currentStep) {
                WizardStep.BASICS -> BasicsStep(
                    draft = viewModel.draft,
                    onTitleChange = viewModel::updateTitle,
                    onDescriptionChange = viewModel::updateDescription,
                    onCategoryChange = viewModel::updateCategory
                )
                WizardStep.PHOTOS -> PhotosStep(
                    draft = viewModel.draft,
                    onAddPhoto = viewModel::addPhoto,
                    onRemovePhoto = viewModel::removePhoto,
                    onMakeCover = viewModel::makeCover,
                    onMovePhoto = viewModel::movePhoto
                )
                WizardStep.LOCATION -> LocationStep(
                    draft = viewModel.draft,
                    locationProvider = locationProvider,
                    onLocationSet = { lat, lon ->
                        viewModel.draft = viewModel.draft.copy(latitude = lat, longitude = lon)
                    },
                    onVisibilityChange = viewModel::updateLocationVisibility
                )
                WizardStep.SCHEDULE -> ScheduleStep(
                    draft = viewModel.draft,
                    onStartsAtChange = viewModel::updateStartsAt,
                    onDurationPresetChange = viewModel::updateDurationPreset,
                    onCustomDurationChange = viewModel::updateCustomDuration,
                    onShowTimingChange = viewModel::updateShowTiming,
                    onHideTimingChange = viewModel::updateHideTiming
                )
                WizardStep.PARTICIPANTS -> ParticipantsStep(
                    draft = viewModel.draft,
                    onParticipantLimitChange = viewModel::updateParticipantLimit,
                    onJoinPolicyChange = viewModel::updateJoinPolicy,
                    onAgeMinChange = viewModel::updateAgeMin,
                    onSkillLevelChange = viewModel::updateSkillLevel,
                    onCostTypeChange = viewModel::updateCostType,
                    onCostAmountChange = viewModel::updateCostAmount,
                    onAddLanguage = viewModel::addLanguage,
                    onRemoveLanguage = viewModel::removeLanguage,
                    onAddBringItem = viewModel::addBringItem,
                    onRemoveBringItem = viewModel::removeBringItem,
                    onAddRule = viewModel::addRule,
                    onRemoveRule = viewModel::removeRule
                )
                WizardStep.PREVIEW -> PreviewStep(draft = viewModel.draft)
            }

            viewModel.errorMessage?.let { error ->
                Spacer(modifier = Modifier.height(12.dp))
                ErrorMessage(text = error)
            }

            Spacer(modifier = Modifier.height(20.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (viewModel.step > 0) {
                    GlassSecondaryButton(
                        text = "Назад",
                        onClick = viewModel::moveBack,
                        modifier = Modifier.weight(1f)
                    )
                }

                if (viewModel.isLastStep) {
                    GradientPrimaryButton(
                        text = if (viewModel.isSubmitting) "Публикуем..." else "Опубликовать",
                        onClick = { viewModel.submit() },
                        enabled = !viewModel.isSubmitting,
                        loading = viewModel.isSubmitting,
                        modifier = Modifier.weight(1f)
                    )
                } else {
                    GradientPrimaryButton(
                        text = "Далее",
                        onClick = viewModel::moveForward,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }

    viewModel.publishedActivity?.let {
        AlertDialog(
            onDismissRequest = {
                viewModel.reset()
                onDismiss()
            },
            title = { Text("Активность опубликована!") },
            text = { Text("Ваша активность \"${viewModel.draft.title}\" теперь видна на карте.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.reset()
                    onDismiss()
                }) {
                    Text("Готово")
                }
            }
        )
    }
}

@Composable
private fun WizardProgressBar(
    step: WizardStep,
    onSelect: (WizardStep) -> Unit
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Шаг ${step.index + 1} из ${step.total}",
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = step.titleRu,
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        LinearProgressIndicator(
            progress = { step.progress },
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp)),
            color = MaterialTheme.colorScheme.primary,
            trackColor = MaterialTheme.colorScheme.surfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            WizardStep.entries.forEach { entry ->
                val isActive = entry.ordinal <= step.index
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .clip(RoundedCornerShape(5.dp))
                        .background(if (isActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant)
                        .then(
                            if (entry.ordinal < step.index) Modifier.clickable { onSelect(entry) }
                            else Modifier
                        )
                )
            }
        }
    }
}

@Composable
private fun BasicsStep(
    draft: ActivityDraft,
    onTitleChange: (String) -> Unit,
    onDescriptionChange: (String) -> Unit,
    onCategoryChange: (ActivityCategory) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column {
            Text(
                text = "Название",
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp
            )
            Spacer(modifier = Modifier.height(6.dp))
            LiquidGlassField(
                value = draft.title,
                onValueChange = onTitleChange,
                label = "Например, прогулка в парке"
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                Text(
                    text = "${draft.title.length}/70",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Text(
            text = "Категория",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )
        val categories = ActivityCategory.entries
        val rows = categories.chunked(4)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            rows.forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    row.forEach { category ->
                        val isSelected = draft.category == category
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .aspectRatio(1f)
                                .clip(RoundedCornerShape(12.dp))
                                .background(
                                    if (isSelected) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.surfaceVariant
                                )
                                .clickable { onCategoryChange(category) }
                                .border(
                                    width = if (isSelected) 0.dp else 1.dp,
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                                    shape = RoundedCornerShape(12.dp)
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Icon(
                                    imageVector = categoryIcon(category),
                                    contentDescription = null,
                                    tint = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(24.dp)
                                )
                                Text(
                                    text = category.titleRu,
                                    fontSize = 11.sp,
                                    color = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                    }
                    repeat(4 - row.size) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }

        Column {
            Text(
                text = "Описание",
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp
            )
            Spacer(modifier = Modifier.height(6.dp))
            OutlinedTextField(
                value = draft.description,
                onValueChange = onDescriptionChange,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 120.dp),
                shape = RoundedCornerShape(18.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant
                ),
                placeholder = { Text("Расскажите подробнее...") }
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                Text(
                    text = "${draft.description.length}/3000",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun PhotosStep(
    draft: ActivityDraft,
    onAddPhoto: (Uri) -> Unit,
    onRemovePhoto: (Int) -> Unit,
    onMakeCover: (Int) -> Unit,
    onMovePhoto: (Int, Int) -> Unit
) {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { onAddPhoto(it) }
    }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(
            text = "Фотографии",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )
        Text(
            text = "Добавьте до 6 фотографий. Первая станет обложкой.",
            fontSize = 13.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (draft.photos.isNotEmpty()) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                itemsIndexed(draft.photos) { index, photo ->
                    PhotoCard(
                        photo = photo,
                        onRemove = { onRemovePhoto(index) },
                        onMakeCover = { onMakeCover(index) },
                        onMoveLeft = { onMovePhoto(index, -1) },
                        onMoveRight = { onMovePhoto(index, 1) }
                    )
                }
            }
        } else {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(160.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .clickable { launcher.launch("image/*") },
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        imageVector = Icons.Filled.PhotoLibrary,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(48.dp)
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Нет фотографий",
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        GradientPrimaryButton(
            text = if (draft.photos.size >= 6) "Максимум 6 фото" else "Добавить фото",
            onClick = { launcher.launch("image/*") },
            enabled = draft.photos.size < 6,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun PhotoCard(
    photo: ActivityDraftPhoto,
    onRemove: () -> Unit,
    onMakeCover: () -> Unit,
    onMoveLeft: () -> Unit,
    onMoveRight: () -> Unit
) {
    Column(
        modifier = Modifier
            .width(160.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Box {
            AsyncImage(
                model = photo.uri,
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp)
                    .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)),
                contentScale = ContentScale.Crop
            )
            if (photo.isCover) {
                Box(
                    modifier = Modifier
                        .padding(6.dp)
                        .align(Alignment.TopStart)
                        .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(6.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text("Обложка", fontSize = 10.sp, color = Color.White)
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(4.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            IconButton(onClick = onMoveLeft, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Filled.ChevronLeft, contentDescription = "Влево", modifier = Modifier.size(16.dp))
            }
            IconButton(onClick = onMoveRight, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Filled.ChevronRight, contentDescription = "Вправо", modifier = Modifier.size(16.dp))
            }
            IconButton(onClick = onMakeCover, modifier = Modifier.size(32.dp)) {
                Icon(
                    if (photo.isCover) Icons.Filled.Star else Icons.Filled.StarOutline,
                    contentDescription = "Обложка",
                    modifier = Modifier.size(16.dp),
                    tint = if (photo.isCover) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = onRemove, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Filled.Delete, contentDescription = "Удалить", modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun LocationStep(
    draft: ActivityDraft,
    locationProvider: frezzy.gonow.core.location.DeviceLocationProvider,
    onLocationSet: (Double, Double) -> Unit,
    onVisibilityChange: (frezzy.gonow.models.ActivityLocationVisibility) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(
            text = "Местоположение",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val lat = draft.latitude
                val lon = draft.longitude
                if (lat != null && lon != null) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Success)
                    Text(
                        text = String.format("Координаты: %.5f, %.5f", lat, lon),
                        fontSize = 13.sp
                    )
                } else {
                    Text(
                        text = "Местоположение не выбрано",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                GradientPrimaryButton(
                    text = if (lat != null) "Использовать текущее местоположение" else "Определить местоположение",
                    onClick = {
                        val lat2 = locationProvider.latitude
                        val lon2 = locationProvider.longitude
                        if (lat2 != null && lon2 != null) {
                            onLocationSet(lat2, lon2)
                        } else {
                            locationProvider.requestLocation()
                        }
                    }
                )
            }
        }

        Text(
            text = "Видимость местоположения",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                frezzy.gonow.models.ActivityLocationVisibility.entries.forEach { visibility ->
                    val isSelected = draft.locationVisibility == visibility
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else Color.Transparent
                            )
                            .clickable { onVisibilityChange(visibility) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = { onVisibilityChange(visibility) },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            text = visibility.titleRu,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScheduleStep(
    draft: ActivityDraft,
    onStartsAtChange: (String) -> Unit,
    onDurationPresetChange: (frezzy.gonow.models.ActivityDurationPreset) -> Unit,
    onCustomDurationChange: (Int) -> Unit,
    onShowTimingChange: (frezzy.gonow.models.ActivityShowTiming) -> Unit,
    onHideTimingChange: (frezzy.gonow.models.ActivityHideTiming) -> Unit
) {
    val dateFormat = remember { SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US) }
    val displayFormat = remember { SimpleDateFormat("d MMMM, HH:mm", Locale("ru")) }

    var datePickerVisible by remember { mutableStateOf(false) }
    var timePickerVisible by remember { mutableStateOf(false) }
    var selectedDate by remember { mutableStateOf(Date()) }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(
            text = "Дата и время",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(Icons.Filled.CalendarToday, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = if (draft.startsAt.isNotBlank()) {
                                try {
                                    val date = dateFormat.parse(draft.startsAt)
                                    date?.let { displayFormat.format(it) } ?: "Выберите дату"
                                } catch (_: Exception) { "Выберите дату" }
                            } else "Выберите дату и время",
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text = "Когда начнётся",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = { datePickerVisible = true },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("Выбрать дату")
                    }
                    OutlinedButton(
                        onClick = { timePickerVisible = true },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("Выбрать время")
                    }
                }
            }
        }

        Text(
            text = "Длительность",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                frezzy.gonow.models.ActivityDurationPreset.entries.forEach { preset ->
                    val isSelected = draft.durationPreset == preset
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else Color.Transparent
                            )
                            .clickable { onDurationPresetChange(preset) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = { onDurationPresetChange(preset) },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            text = preset.titleRu,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }

                if (draft.durationPreset == frezzy.gonow.models.ActivityDurationPreset.CUSTOM) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text("Минуты:", fontSize = 14.sp)
                        Slider(
                            value = draft.customDurationMinutes.toFloat(),
                            onValueChange = { onCustomDurationChange(it.toInt()) },
                            valueRange = 15f..43200f,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            text = "${draft.customDurationMinutes} мин",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }

        Text(
            text = "Видимость",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Когда показать", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                frezzy.gonow.models.ActivityShowTiming.entries.forEach { timing ->
                    val isSelected = draft.showTiming == timing
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else Color.Transparent
                            )
                            .clickable { onShowTimingChange(timing) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = { onShowTimingChange(timing) },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            text = timing.titleRu,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }

                HorizontalDivider()

                Text("Когда скрыть", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                frezzy.gonow.models.ActivityHideTiming.entries.forEach { timing ->
                    val isSelected = draft.hideTiming == timing
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else Color.Transparent
                            )
                            .clickable { onHideTimingChange(timing) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = { onHideTimingChange(timing) },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            text = timing.titleRu,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }
            }
        }
    }

    if (datePickerVisible) {
        val datePickerState = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { datePickerVisible = false },
            confirmButton = {
                TextButton(onClick = {
                    datePickerState.selectedDateMillis?.let { millis ->
                        val picked = Date(millis)
                        selectedDate = picked
                        val cal = Calendar.getInstance().apply { time = picked }
                        val existing = if (draft.startsAt.isNotBlank()) {
                            try { dateFormat.parse(draft.startsAt) } catch (_: Exception) { Date() }
                        } else Date()
                        val timeCal = Calendar.getInstance().apply { time = existing }
                        cal.set(Calendar.HOUR_OF_DAY, timeCal.get(Calendar.HOUR_OF_DAY))
                        cal.set(Calendar.MINUTE, timeCal.get(Calendar.MINUTE))
                        onStartsAtChange(dateFormat.format(cal.time))
                    }
                    datePickerVisible = false
                }) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { datePickerVisible = false }) { Text("Отмена") }
            }
        ) {
            DatePicker(state = datePickerState)
        }
    }

    if (timePickerVisible) {
        var hour by remember { mutableIntStateOf(12) }
        var minute by remember { mutableIntStateOf(0) }

        AlertDialog(
            onDismissRequest = { timePickerVisible = false },
            title = { Text("Выберите время") },
            text = {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            IconButton(onClick = { if (hour > 0) hour-- }) {
                                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "+")
                            }
                            Text(String.format("%02d", hour), fontSize = 24.sp, fontWeight = FontWeight.Bold)
                            IconButton(onClick = { if (hour < 23) hour++ }) {
                                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "-")
                            }
                        }
                        Text(":", fontSize = 24.sp, fontWeight = FontWeight.Bold)
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            IconButton(onClick = { if (minute > 0) minute-- }) {
                                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "+")
                            }
                            Text(String.format("%02d", minute), fontSize = 24.sp, fontWeight = FontWeight.Bold)
                            IconButton(onClick = { if (minute < 59) minute++ }) {
                                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "-")
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val base = if (draft.startsAt.isNotBlank()) {
                        try { dateFormat.parse(draft.startsAt) } catch (_: Exception) { Date() }
                    } else Date()
                    val cal = Calendar.getInstance().apply {
                        time = base
                        set(Calendar.HOUR_OF_DAY, hour)
                        set(Calendar.MINUTE, minute)
                    }
                    onStartsAtChange(dateFormat.format(cal.time))
                    timePickerVisible = false
                }) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { timePickerVisible = false }) { Text("Отмена") }
            }
        )
    }
}

@Composable
private fun ParticipantsStep(
    draft: ActivityDraft,
    onParticipantLimitChange: (Int?) -> Unit,
    onJoinPolicyChange: (frezzy.gonow.models.ActivityJoinPolicy) -> Unit,
    onAgeMinChange: (Int?) -> Unit,
    onSkillLevelChange: (frezzy.gonow.models.ActivitySkillLevel) -> Unit,
    onCostTypeChange: (frezzy.gonow.models.ActivityCostType) -> Unit,
    onCostAmountChange: (Int?) -> Unit,
    onAddLanguage: (String) -> Unit,
    onRemoveLanguage: (String) -> Unit,
    onAddBringItem: (String) -> Unit,
    onRemoveBringItem: (String) -> Unit,
    onAddRule: (String) -> Unit,
    onRemoveRule: (String) -> Unit
) {
    val limitOptions = listOf(null to "Без ограничений", 2 to "2", 5 to "5", 10 to "10", 20 to "20")
    var languageInput by remember { mutableStateOf("") }
    var bringInput by remember { mutableStateOf("") }
    var ruleInput by remember { mutableStateOf("") }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(
            text = "Лимит участников",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        limitOptions.forEach { (value, label) ->
            val isSelected = draft.participantLimit == value
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(
                        if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                        else Color.Transparent
                    )
                    .clickable { onParticipantLimitChange(value) }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                RadioButton(
                    selected = isSelected,
                    onClick = { onParticipantLimitChange(value) },
                    colors = RadioButtonDefaults.colors(
                        selectedColor = MaterialTheme.colorScheme.primary
                    )
                )
                Text(
                    text = label,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }

        Text(
            text = "Политика входа",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                frezzy.gonow.models.ActivityJoinPolicy.entries.forEach { policy ->
                    val isSelected = draft.joinPolicy == policy
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else Color.Transparent
                            )
                            .clickable { onJoinPolicyChange(policy) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = { onJoinPolicyChange(policy) },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            text = policy.titleRu,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }
            }
        }

        Text(
            text = "Требования",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Минимальный возраст", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    listOf(null to "Любой", 18 to "18+").forEach { (age, label) ->
                        val isSelected = draft.ageMin == age
                        OutlinedButton(
                            onClick = { onAgeMinChange(age) },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.outlinedButtonColors(
                                containerColor = if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else MaterialTheme.colorScheme.surfaceVariant
                            )
                        ) {
                            Text(label, fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal)
                        }
                    }
                }

                HorizontalDivider()

                Text("Уровень навыков", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                frezzy.gonow.models.ActivitySkillLevel.entries.forEach { level ->
                    val isSelected = draft.skillLevel == level
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else Color.Transparent
                            )
                            .clickable { onSkillLevelChange(level) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = { onSkillLevelChange(level) },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            text = level.titleRu,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }
            }
        }

        Text(
            text = "Языки",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = languageInput,
                        onValueChange = { languageInput = it },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp),
                        placeholder = { Text("Добавить язык") },
                        singleLine = true
                    )
                    IconButton(onClick = {
                        onAddLanguage(languageInput)
                        languageInput = ""
                    }) {
                        Icon(Icons.Filled.Add, contentDescription = "Добавить")
                    }
                }
                if (draft.languages.isNotEmpty()) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(draft.languages) { lang ->
                            InputChip(
                                selected = true,
                                onClick = { onRemoveLanguage(lang) },
                                label = { Text(lang) },
                                trailingIcon = {
                                    Icon(Icons.Filled.Close, contentDescription = "Удалить", modifier = Modifier.size(14.dp))
                                }
                            )
                        }
                    }
                }
            }
        }

        Text(
            text = "Стоимость",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                frezzy.gonow.models.ActivityCostType.entries.forEach { type ->
                    val isSelected = draft.costType == type
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else Color.Transparent
                            )
                            .clickable { onCostTypeChange(type) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = { onCostTypeChange(type) },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = MaterialTheme.colorScheme.primary
                            )
                        )
                        Text(
                            text = type.titleRu,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }

                if (draft.costType == frezzy.gonow.models.ActivityCostType.FIXED ||
                    draft.costType == frezzy.gonow.models.ActivityCostType.ESTIMATED) {
                    OutlinedTextField(
                        value = draft.costAmountCents?.let { "${it / 100}" } ?: "",
                        onValueChange = { text ->
                            val cents = text.replace("[^0-9]".toRegex(), "").toIntOrNull()?.times(100)
                            onCostAmountChange(cents)
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        label = { Text("Сумма (руб)") },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = androidx.compose.ui.text.input.KeyboardType.Number
                        ),
                        singleLine = true
                    )
                }
            }
        }

        Text(
            text = "Что взять с собой",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = bringInput,
                        onValueChange = { bringInput = it },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp),
                        placeholder = { Text("Добавить вещь") },
                        singleLine = true
                    )
                    IconButton(onClick = {
                        onAddBringItem(bringInput)
                        bringInput = ""
                    }) {
                        Icon(Icons.Filled.Add, contentDescription = "Добавить")
                    }
                }
                if (draft.bringItems.isNotEmpty()) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(draft.bringItems) { item ->
                            InputChip(
                                selected = true,
                                onClick = { onRemoveBringItem(item) },
                                label = { Text(item) },
                                trailingIcon = {
                                    Icon(Icons.Filled.Close, contentDescription = "Удалить", modifier = Modifier.size(14.dp))
                                }
                            )
                        }
                    }
                }
            }
        }

        Text(
            text = "Правила",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = ruleInput,
                        onValueChange = { ruleInput = it },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp),
                        placeholder = { Text("Добавить правило") },
                        singleLine = true
                    )
                    IconButton(onClick = {
                        onAddRule(ruleInput)
                        ruleInput = ""
                    }) {
                        Icon(Icons.Filled.Add, contentDescription = "Добавить")
                    }
                }
                if (draft.rules.isNotEmpty()) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(draft.rules) { rule ->
                            InputChip(
                                selected = true,
                                onClick = { onRemoveRule(rule) },
                                label = { Text(rule) },
                                trailingIcon = {
                                    Icon(Icons.Filled.Close, contentDescription = "Удалить", modifier = Modifier.size(14.dp))
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PreviewStep(draft: ActivityDraft) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(
            text = "Проверьте перед публикацией",
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp
        )

        if (draft.photos.isNotEmpty()) {
            val coverPhoto = draft.photos.firstOrNull { it.isCover } ?: draft.photos.first()
            AsyncImage(
                model = coverPhoto.uri,
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(180.dp)
                    .clip(RoundedCornerShape(16.dp)),
                contentScale = ContentScale.Crop
            )
        }

        GlassCard {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(MaterialTheme.colorScheme.primary),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = categoryIcon(draft.category),
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                    Column {
                        Text(
                            text = draft.title.ifBlank { "Без названия" },
                            fontWeight = FontWeight.Bold,
                            fontSize = 18.sp
                        )
                        Text(
                            text = draft.category.titleRu,
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                if (draft.description.isNotBlank()) {
                    Text(text = draft.description, fontSize = 14.sp)
                }

                HorizontalDivider()

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.AccessTime, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                    Text(
                        text = if (draft.startsAt.isNotBlank()) {
                            try {
                                val df = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
                                val out = SimpleDateFormat("d MMMM, HH:mm", Locale("ru"))
                                val d = df.parse(draft.startsAt)
                                d?.let { out.format(it) } ?: draft.startsAt
                            } catch (_: Exception) { draft.startsAt }
                        } else "Не указано",
                        fontSize = 14.sp
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Schedule, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                    Text(
                        text = "${draft.durationMinutes} мин (${draft.durationPreset.titleRu})",
                        fontSize = 14.sp
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.People, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                    Text(
                        text = draft.participantLimit?.let { "до $it участников" } ?: "Без ограничений",
                        fontSize = 14.sp
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Person, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                    Text(
                        text = draft.joinPolicy.titleRu,
                        fontSize = 14.sp
                    )
                }

                if (draft.costType != frezzy.gonow.models.ActivityCostType.FREE) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.AttachMoney, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                        Text(
                            text = draft.costType.titleRu + (draft.costAmountCents?.let { " — ${it / 100} руб." } ?: ""),
                            fontSize = 14.sp
                        )
                    }
                }

                draft.latitude?.let { lat ->
                    draft.longitude?.let { lon ->
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Filled.LocationOn, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                            Text(
                                text = String.format("%.5f, %.5f", lat, lon),
                                fontSize = 14.sp
                            )
                        }
                    }
                }

                if (draft.languages.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Language, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                        Text(
                            text = draft.languages.joinToString(", "),
                            fontSize = 14.sp
                        )
                    }
                }

                if (draft.bringItems.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Backpack, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                        Column {
                            Text("Взять с собой:", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(
                                text = draft.bringItems.joinToString(", "),
                                fontSize = 14.sp
                            )
                        }
                    }
                }

                if (draft.rules.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Gavel, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                        Column {
                            Text("Правила:", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(
                                text = draft.rules.joinToString(", "),
                                fontSize = 14.sp
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun categoryIcon(category: ActivityCategory) = when (category) {
    ActivityCategory.WALKING -> Icons.Filled.DirectionsWalk
    ActivityCategory.SPORT -> Icons.Filled.Sports
    ActivityCategory.TRAVEL -> Icons.Filled.Flight
    ActivityCategory.MUSIC -> Icons.Filled.MusicNote
    ActivityCategory.GAMES -> Icons.Filled.SportsEsports
    ActivityCategory.FOOD -> Icons.Filled.Restaurant
    ActivityCategory.HELP -> Icons.Filled.Handshake
    ActivityCategory.EDUCATION -> Icons.Filled.School
    ActivityCategory.ANIMALS -> Icons.Filled.Pets
    ActivityCategory.EVENT -> Icons.Filled.Event
    ActivityCategory.OTHER -> Icons.Filled.AutoAwesome
}
