package frezzy.gonow.features.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import frezzy.gonow.models.ProfilePhoto
import frezzy.gonow.models.User
import frezzy.gonow.ui.theme.*
import java.io.ByteArrayOutputStream

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileTab(
    user: User?,
    avatarBytes: ByteArray?,
    profilePhotos: List<ProfilePhoto>,
    photoContentMap: Map<String, ByteArray>,
    onRefresh: () -> Unit,
    onLogout: () -> Unit,
    onEditProfile: () -> Unit,
    onSettings: () -> Unit,
    onUploadAvatar: (ByteArray) -> Unit,
    onUploadPhoto: (ByteArray) -> Unit,
    onDeletePhoto: (String) -> Unit,
    onLoadPhotoContent: (String) -> Unit,
    isLoading: Boolean
) {
    val context = LocalContext.current
    val cardShape = RoundedCornerShape(20.dp)
    val maxPhotos = 12

    val avatarPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        uri?.let {
            val bytes = context.contentResolver.openInputStream(it)?.use { s -> compressBitmap(BitmapFactory.decodeStream(s), 1600) }
            if (bytes != null) onUploadAvatar(bytes)
        }
    }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        uri?.let {
            val bytes = context.contentResolver.openInputStream(it)?.use { s -> compressBitmap(BitmapFactory.decodeStream(s), 1600) }
            if (bytes != null) onUploadPhoto(bytes)
        }
    }

    var expandedGallery by remember { mutableStateOf(false) }
    var viewingPhoto by remember { mutableStateOf<String?>(null) }

    if (user == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
        }
        return
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.End
            ) {
                IconButton(onClick = onSettings) {
                    Icon(Icons.Filled.Settings, contentDescription = "Настройки", tint = MaterialTheme.colorScheme.onBackground)
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
        ) {
            // ─── Avatar + Name ───
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box {
                    ProfileAvatar(avatarBytes = avatarBytes, initials = user.initials, size = 80)
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(32.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary)
                            .border(2.dp, MaterialTheme.colorScheme.surface, CircleShape)
                            .clickable { avatarPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Filled.CameraAlt, contentDescription = "Изменить аватар", tint = Color.White, modifier = Modifier.size(16.dp))
                    }
                }

                Spacer(Modifier.width(14.dp))

                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        user.displayName,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold
                    )
                    user.birthDateDisplay?.let { text ->
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Filled.CalendarToday, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
                            Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    val locationText = user.city?.takeIf { it.isNotBlank() }
                    if (locationText != null) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Filled.LocationOn, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
                            Text(locationText ?: "", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                        }
                    }
                }
            }

            Spacer(Modifier.height(24.dp))

            // ─── Single info card: Photos + Bio + Interests ───
            Card(shape = cardShape, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {

                    // Photos section
                    Column {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("Фотографии", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                            if (profilePhotos.isNotEmpty()) {
                                TextButton(onClick = { expandedGallery = !expandedGallery }) {
                                    Text(
                                        text = if (expandedGallery) "Свернуть" else "Показать все (${profilePhotos.size})",
                                        color = MaterialTheme.colorScheme.primary,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Medium
                                    )
                                }
                            }
                        }
                        Spacer(Modifier.height(12.dp))

                        if (expandedGallery) {
                            // Grid layout (like iOS LazyVGrid)
                            LazyVerticalGrid(
                                columns = GridCells.Adaptive(minSize = 88.dp),
                                modifier = Modifier.heightIn(max = 400.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                items(profilePhotos) { photo ->
                                    val contentBytes = photoContentMap[photo.id]
                                    if (contentBytes == null) {
                                        LaunchedEffect(photo.id) { onLoadPhotoContent(photo.id) }
                                    }
                                    PhotoThumbnail(
                                        bytes = contentBytes,
                                        onClick = { viewingPhoto = photo.id },
                                        onDelete = { onDeletePhoto(photo.id) }
                                    )
                                }
                                if (profilePhotos.size < maxPhotos) {
                                    item {
                                        AddPhotoButton { photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                                    }
                                }
                            }
                        } else {
                            // Horizontal scroll (like iOS)
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                itemsIndexed(profilePhotos) { index, photo ->
                                    val contentBytes = photoContentMap[photo.id]
                                    if (contentBytes == null) {
                                        LaunchedEffect(photo.id) { onLoadPhotoContent(photo.id) }
                                    }
                                    PhotoThumbnail(
                                        bytes = contentBytes,
                                        onClick = { viewingPhoto = photo.id },
                                        onDelete = { onDeletePhoto(photo.id) }
                                    )
                                }
                                if (profilePhotos.size < maxPhotos) {
                                    item {
                                        AddPhotoButton { photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                                    }
                                }
                            }
                        }
                    }

                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                    // Bio
                    if (!user.bio.isNullOrBlank()) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(Icons.Filled.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                                Text("О себе", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text(user.bio, style = MaterialTheme.typography.bodyMedium, lineHeight = 22.sp, modifier = Modifier.padding(start = 28.dp))
                        }
                    }

                    // Interests
                    if (!user.interests.isNullOrEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(Icons.Filled.Tag, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                                Text("Интересы", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(start = 28.dp)) {
                                user.interests.forEach { interest ->
                                    Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)) {
                                        Text(interest, modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // ─── Edit button ───
            GradientPrimaryButton(
                text = "Редактировать профиль",
                onClick = onEditProfile
            )

            Spacer(Modifier.height(32.dp))
        }
    }

    // ─── Full-screen photo viewer ───
    if (viewingPhoto != null) {
        val photoId = viewingPhoto!!
        val contentBytes = photoContentMap[photoId]
        val photo = profilePhotos.find { it.id == photoId }
        var showDeleteConfirm by remember { mutableStateOf(false) }

        Dialog(
            onDismissRequest = { viewingPhoto = null }
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.95f))
                    .clickable { viewingPhoto = null }
            ) {
                // Photo
                if (contentBytes != null) {
                    val bitmap = remember(contentBytes) { BitmapFactory.decodeByteArray(contentBytes, 0, contentBytes.size) }
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = "Фото",
                            modifier = Modifier.fillMaxSize().padding(16.dp),
                            contentScale = ContentScale.Fit
                        )
                    }
                } else {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                        color = Color.White
                    )
                }

                // Top bar with close and delete
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        .statusBarsPadding(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { viewingPhoto = null }) {
                        Icon(Icons.Filled.Close, contentDescription = "Закрыть", tint = Color.White, modifier = Modifier.size(24.dp))
                    }
                    if (photo != null) {
                        IconButton(onClick = { showDeleteConfirm = true }) {
                            Icon(Icons.Filled.Delete, contentDescription = "Удалить", tint = Color.White, modifier = Modifier.size(24.dp))
                        }
                    }
                }
            }

            if (showDeleteConfirm) {
                AlertDialog(
                    onDismissRequest = { showDeleteConfirm = false },
                    title = { Text("Удалить фотографию?") },
                    text = { Text("Это действие нельзя отменить.") },
                    confirmButton = {
                        TextButton(onClick = {
                            showDeleteConfirm = false
                            viewingPhoto = null
                            onDeletePhoto(photoId)
                        }) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
                    },
                    dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text("Отмена") } }
                )
            }
        }
    }
}

@Composable
private fun AddPhotoButton(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(width = 88.dp, height = 112.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.3f), RoundedCornerShape(20.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(Icons.Filled.Add, contentDescription = "Добавить фото", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
    }
}

@Composable
fun ProfileAvatar(avatarBytes: ByteArray?, initials: String, size: Int, modifier: Modifier = Modifier) {
    val shape = CircleShape
    Box(
        modifier = modifier.size(size.dp).clip(shape)
            .then(if (avatarBytes != null && avatarBytes.isNotEmpty()) Modifier else Modifier.background(MaterialTheme.colorScheme.primary))
            .border(3.dp, MaterialTheme.colorScheme.outline, shape),
        contentAlignment = Alignment.Center
    ) {
        if (avatarBytes != null && avatarBytes.isNotEmpty()) {
            val bitmap = remember(avatarBytes) { try { BitmapFactory.decodeByteArray(avatarBytes, 0, avatarBytes.size) } catch (_: Exception) { null } }
            bitmap?.let {
                Image(bitmap = it.asImageBitmap(), contentDescription = "Аватар", modifier = Modifier.fillMaxSize().clip(CircleShape), contentScale = ContentScale.Crop)
            } ?: Text(initials, color = Color.White, fontWeight = FontWeight.Bold, fontSize = (size * 0.34f).sp)
        } else {
            Text(initials, color = Color.White, fontWeight = FontWeight.Bold, fontSize = (size * 0.34f).sp)
        }
    }
}

@Composable
private fun PhotoThumbnail(bytes: ByteArray?, onClick: () -> Unit, onDelete: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    var showDeleteConfirm by remember { mutableStateOf(false) }

    Box {
        if (bytes != null && bytes.isNotEmpty()) {
            val bitmap = remember(bytes) { try { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) } catch (_: Exception) { null } }
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = "Фото",
                    modifier = Modifier
                        .size(width = 88.dp, height = 112.dp)
                        .clip(shape)
                        .clickable { onClick() },
                    contentScale = ContentScale.Crop
                )
            } else {
                Box(
                    modifier = Modifier.size(width = 88.dp, height = 112.dp).clip(shape).background(MaterialTheme.colorScheme.surfaceVariant),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Filled.BrokenImage, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(24.dp))
                }
            }
        } else {
            Box(
                modifier = Modifier.size(width = 88.dp, height = 112.dp).clip(shape).background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            }
        }

        IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.align(Alignment.TopEnd).size(24.dp).padding(2.dp)) {
            Icon(Icons.Filled.Close, contentDescription = "Удалить", tint = Color.White, modifier = Modifier.size(14.dp))
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Удалить фотографию?") },
            text = { Text("Это действие нельзя отменить.") },
            confirmButton = { TextButton(onClick = { showDeleteConfirm = false; onDelete() }) { Text("Удалить", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { showDeleteConfirm = false }) { Text("Отмена") } }
        )
    }
}

private fun compressBitmap(bitmap: Bitmap, maxSide: Int): ByteArray {
    val scale = if (maxOf(bitmap.width, bitmap.height) > maxSide) maxSide.toFloat() / maxOf(bitmap.width, bitmap.height) else 1f
    val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
    val stream = ByteArrayOutputStream()
    scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
    return stream.toByteArray()
}
