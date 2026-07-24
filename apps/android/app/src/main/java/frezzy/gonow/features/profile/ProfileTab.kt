package frezzy.gonow.features.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
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
import java.io.File

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileTab(
    user: User?,
    avatarBytes: ByteArray?,
    profilePhotos: List<ProfilePhoto>,
    avatarHistory: List<ProfilePhoto>,
    photoContentFiles: Map<String, String>,
    unavailablePhotoIds: Set<String>,
    onRefresh: () -> Unit,
    onLogout: () -> Unit,
    onEditProfile: () -> Unit,
    onOpenSocial: () -> Unit,
    onSettings: () -> Unit,
    onUploadAvatar: (ByteArray) -> Unit,
    onUploadPhoto: (ByteArray) -> Unit,
    onDeletePhoto: (String) -> Unit,
    onUpdatePhotoDescription: (String, String?) -> Unit,
    onTogglePhotoLike: (String) -> Unit,
    onLoadPhotoContent: (String) -> Unit,
    isLoading: Boolean
) {
    val context = LocalContext.current
    val horizontalPadding = if (LocalConfiguration.current.screenWidthDp >= 600) 32.dp else 16.dp
    val maxPhotos = 12
    var avatarToCrop by remember { mutableStateOf<ByteArray?>(null) }

    val avatarPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        uri?.let {
            val bytes = context.contentResolver.openInputStream(it)?.use { s -> compressBitmap(BitmapFactory.decodeStream(s), 1600) }
            if (bytes != null) avatarToCrop = bytes
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
    var profileInfoExpanded by rememberSaveable { mutableStateOf(false) }
    var profileActionsExpanded by remember { mutableStateOf(false) }
    val allViewablePhotos = remember(profilePhotos, avatarHistory) {
        (avatarHistory + profilePhotos).distinctBy { it.id }
    }

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
                modifier = Modifier.fillMaxWidth().padding(horizontal = horizontalPadding, vertical = 8.dp),
                horizontalArrangement = Arrangement.End
            ) {
                Box {
                    Surface(
                        onClick = { profileActionsExpanded = true },
                        modifier = Modifier.size(48.dp),
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f),
                        shadowElevation = 2.dp
                    ) {
                        Icon(Icons.Filled.Settings, contentDescription = "Меню профиля", tint = MaterialTheme.colorScheme.onBackground, modifier = Modifier.padding(12.dp))
                    }
                    DropdownMenu(
                        expanded = profileActionsExpanded,
                        onDismissRequest = { profileActionsExpanded = false },
                        shape = RoundedCornerShape(20.dp),
                        containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 0.dp,
                        shadowElevation = 4.dp
                    ) {
                        DropdownMenuItem(
                            text = { Text("Редактировать профиль") },
                            leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                            onClick = { profileActionsExpanded = false; onEditProfile() }
                        )
                        DropdownMenuItem(
                            text = { Text("Настройки") },
                            leadingIcon = { Icon(Icons.Filled.Settings, contentDescription = null) },
                            onClick = { profileActionsExpanded = false; onSettings() }
                        )
                    }
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = horizontalPadding)
        ) {
            // ─── Avatar + Name ───
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box {
                    ProfileAvatar(avatarBytes = avatarBytes, initials = user.initials, size = 96)
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(44.dp)
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

                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(
                        user.displayName,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold
                    )
                    Text("@${user.username.ifBlank { user.id.take(8) }}", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
                }
            }

            Spacer(Modifier.height(22.dp))

            GlassCard(modifier = Modifier.fillMaxWidth().clickable { profileInfoExpanded = !profileInfoExpanded }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Badge, contentDescription = null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(30.dp))
                    Text(
                        if (profileInfoExpanded) "Скрыть информацию" else "Информация о себе",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(start = 16.dp).weight(1f)
                    )
                    Icon(
                        if (profileInfoExpanded) Icons.Filled.ExpandLess else Icons.Filled.ChevronRight,
                        contentDescription = if (profileInfoExpanded) "Скрыть информацию" else "Показать информацию",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                AnimatedVisibility(profileInfoExpanded) {
                    Column(
                        modifier = Modifier.padding(top = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        user.birthDateDisplay?.let { ProfileInfoFact(Icons.Filled.Cake, it) }
                        (user.city ?: user.locationLabel)?.takeIf { it.isNotBlank() }?.let {
                            ProfileInfoFact(Icons.Filled.LocationOn, it)
                        }
                        if (!user.bio.isNullOrBlank()) {
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text("О себе", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                                Text(user.bio, style = MaterialTheme.typography.bodyLarge, lineHeight = 22.sp)
                            }
                        }
                        if (!user.interests.isNullOrEmpty()) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("Интересы", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    user.interests.forEach { interest ->
                                        Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)) {
                                            Text(interest, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                                        }
                                    }
                                }
                            }
                        }
                        if (user.birthDate == null && user.city.isNullOrBlank() && user.bio.isNullOrBlank() && user.interests.isNullOrEmpty()) {
                            Text("Добавьте информацию о себе, чтобы людям было проще вас узнать.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            GlassCard(modifier = Modifier.fillMaxWidth().clickable(onClick = onOpenSocial)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)) {
                        Icon(Icons.Filled.Groups, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(10.dp).size(26.dp))
                    }
                    Column(modifier = Modifier.padding(start = 14.dp).weight(1f)) {
                        Text("\u0414\u0440\u0443\u0437\u044c\u044f \u0438 \u043f\u0440\u0438\u0433\u043b\u0430\u0448\u0435\u043d\u0438\u044f", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text("\u041d\u0430\u0439\u0434\u0438\u0442\u0435 \u043b\u044e\u0434\u0435\u0439, \u043e\u0442\u0432\u0435\u0442\u044c\u0442\u0435 \u043d\u0430 \u0437\u0430\u044f\u0432\u043a\u0438 \u0438\u043b\u0438 \u043f\u043e\u0437\u043e\u0432\u0438\u0442\u0435 \u0432\u0441\u0442\u0440\u0435\u0442\u0438\u0442\u044c\u0441\u044f", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(24.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.GridView, contentDescription = null, modifier = Modifier.size(28.dp))
                Text("\u041f\u043e\u0441\u0442\u044b", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 12.dp))
            }
            Spacer(Modifier.height(12.dp))

            GlassCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {

                    // Photos section
                    Column {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Фотографии", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                        Text(
                            "Каждое фото — пост с описанием и лайками",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                            if (profilePhotos.isNotEmpty()) {
                                TextButton(onClick = { expandedGallery = !expandedGallery }) {
                                    Text(
                                        text = if (expandedGallery) "Свернуть" else "Все (${profilePhotos.size})",
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
                                    val contentFile = photoContentFiles[photo.id]
                                    if (contentFile == null) {
                                        LaunchedEffect(photo.id) { onLoadPhotoContent(photo.id) }
                                    }
                                    PhotoThumbnail(
                                        file = contentFile?.let(::File),
                                        unavailable = photo.id in unavailablePhotoIds,
                                        onClick = {
                                            if (photo.id in unavailablePhotoIds) onLoadPhotoContent(photo.id)
                                            else viewingPhoto = photo.id
                                        },
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
                                    val contentFile = photoContentFiles[photo.id]
                                    if (contentFile == null) {
                                        LaunchedEffect(photo.id) { onLoadPhotoContent(photo.id) }
                                    }
                                    PhotoThumbnail(
                                        file = contentFile?.let(::File),
                                        unavailable = photo.id in unavailablePhotoIds,
                                        onClick = {
                                            if (photo.id in unavailablePhotoIds) onLoadPhotoContent(photo.id)
                                            else viewingPhoto = photo.id
                                        },
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
        val contentFile = photoContentFiles[photoId]?.let(::File)
        val photo = allViewablePhotos.find { it.id == photoId }
        var showDeleteConfirm by remember { mutableStateOf(false) }
        var descriptionDraft by remember(photoId, photo?.description) { mutableStateOf(photo?.description.orEmpty()) }

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
                if (contentFile != null) {
                    val bitmap = remember(contentFile) { BitmapFactory.decodeFile(contentFile.absolutePath) }
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

                if (photo != null) {
                    Card(
                        modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(16.dp).clickable(enabled = false) {},
                        colors = CardDefaults.cardColors(containerColor = Color.Black.copy(alpha = 0.72f))
                    ) {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = descriptionDraft,
                                onValueChange = { descriptionDraft = it.take(500) },
                                label = { Text("Описание") },
                                modifier = Modifier.fillMaxWidth(),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedTextColor = Color.White,
                                    unfocusedTextColor = Color.White,
                                    focusedBorderColor = Color.White,
                                    unfocusedBorderColor = Color.White.copy(alpha = 0.6f)
                                )
                            )
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                TextButton(onClick = { onTogglePhotoLike(photo.id) }) {
                                    Icon(
                                        if (photo.isLiked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                                        contentDescription = null,
                                        tint = Color.White
                                    )
                                    Text("${photo.likeCount}", color = Color.White)
                                }
                                Spacer(Modifier.weight(1f))
                                TextButton(onClick = {
                                    onUpdatePhotoDescription(photo.id, descriptionDraft.trim().ifBlank { null })
                                }) { Text("Сохранить", color = Color.White) }
                            }
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

    avatarToCrop?.let { source ->
        AvatarCropDialog(
            imageBytes = source,
            onDismiss = { avatarToCrop = null },
            onCropped = {
                avatarToCrop = null
                onUploadAvatar(it)
            }
        )
    }
}

@Composable
private fun ProfileInfoFact(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(22.dp))
        Text(text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
private fun PhotoThumbnail(file: File?, unavailable: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Box {
        if (file?.isFile == true) {
            val bitmap = remember(file) { try { BitmapFactory.decodeFile(file.absolutePath) } catch (_: Exception) { null } }
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
        } else if (unavailable) {
            Box(
                modifier = Modifier
                    .size(width = 88.dp, height = 112.dp)
                    .clip(shape)
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .clickable(onClick = onClick),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Filled.CloudOff, contentDescription = "Повторить загрузку фото", tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(24.dp))
            }
        } else {
            Box(
                modifier = Modifier.size(width = 88.dp, height = 112.dp).clip(shape).background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            }
        }

    }
}

private fun compressBitmap(bitmap: Bitmap, maxSide: Int): ByteArray {
    val scale = if (maxOf(bitmap.width, bitmap.height) > maxSide) maxSide.toFloat() / maxOf(bitmap.width, bitmap.height) else 1f
    val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
    val stream = ByteArrayOutputStream()
    scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
    return stream.toByteArray()
}
