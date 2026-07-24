package frezzy.gonow.features.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import frezzy.gonow.core.cancellableRunCatching
import java.io.ByteArrayOutputStream
import kotlin.math.max

data class CropOffset(val x: Float, val y: Float)

data class CropRect(val left: Float, val top: Float, val size: Float)

object AvatarCropGeometry {
    fun clampedOffset(
        proposed: CropOffset,
        imageWidth: Float,
        imageHeight: Float,
        cropSide: Float,
        zoom: Float
    ): CropOffset {
        if (imageWidth <= 0f || imageHeight <= 0f || cropSide <= 0f) return CropOffset(0f, 0f)
        val baseScale = max(cropSide / imageWidth, cropSide / imageHeight)
        val displayedWidth = imageWidth * baseScale * zoom.coerceAtLeast(1f)
        val displayedHeight = imageHeight * baseScale * zoom.coerceAtLeast(1f)
        val maxX = ((displayedWidth - cropSide) / 2f).coerceAtLeast(0f)
        val maxY = ((displayedHeight - cropSide) / 2f).coerceAtLeast(0f)
        return CropOffset(
            proposed.x.coerceIn(-maxX, maxX),
            proposed.y.coerceIn(-maxY, maxY)
        )
    }

    fun sourceRect(
        imageWidth: Float,
        imageHeight: Float,
        cropSide: Float,
        zoom: Float,
        offset: CropOffset
    ): CropRect {
        require(imageWidth > 0f && imageHeight > 0f && cropSide > 0f)
        val safeZoom = zoom.coerceAtLeast(1f)
        val baseScale = max(cropSide / imageWidth, cropSide / imageHeight)
        val effectiveScale = baseScale * safeZoom
        val sourceSide = (cropSide / effectiveScale).coerceAtMost(minOf(imageWidth, imageHeight))
        val clamped = clampedOffset(offset, imageWidth, imageHeight, cropSide, safeZoom)
        val centeredLeft = (imageWidth - sourceSide) / 2f
        val centeredTop = (imageHeight - sourceSide) / 2f
        return CropRect(
            left = (centeredLeft - clamped.x / effectiveScale).coerceIn(0f, imageWidth - sourceSide),
            top = (centeredTop - clamped.y / effectiveScale).coerceIn(0f, imageHeight - sourceSide),
            size = sourceSide
        )
    }
}

object AvatarCropProcessor {
    fun croppedJpeg(
        sourceBytes: ByteArray,
        cropSide: Float,
        zoom: Float,
        offset: CropOffset,
        outputSize: Int = 1_024
    ): ByteArray {
        val source = requireNotNull(BitmapFactory.decodeByteArray(sourceBytes, 0, sourceBytes.size)) {
            "Не удалось прочитать выбранное изображение"
        }
        val crop = AvatarCropGeometry.sourceRect(
            imageWidth = source.width.toFloat(),
            imageHeight = source.height.toFloat(),
            cropSide = cropSide,
            zoom = zoom,
            offset = offset
        )
        val output = Bitmap.createBitmap(outputSize, outputSize, Bitmap.Config.ARGB_8888)
        Canvas(output).drawBitmap(
            source,
            Rect(
                crop.left.toInt(),
                crop.top.toInt(),
                (crop.left + crop.size).toInt(),
                (crop.top + crop.size).toInt()
            ),
            Rect(0, 0, outputSize, outputSize),
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        )
        return ByteArrayOutputStream().use { stream ->
            check(output.compress(Bitmap.CompressFormat.JPEG, 90, stream))
            stream.toByteArray()
        }
    }
}

@Composable
fun AvatarCropDialog(
    imageBytes: ByteArray,
    onDismiss: () -> Unit,
    onCropped: (ByteArray) -> Unit
) {
    val bitmap = remember(imageBytes) { BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size) }
    if (bitmap == null) {
        onDismiss()
        return
    }
    var zoom by remember(imageBytes) { mutableFloatStateOf(1f) }
    var offset by remember(imageBytes) { mutableStateOf(CropOffset(0f, 0f)) }
    var cropSidePx by remember { mutableFloatStateOf(1f) }
    var processing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val transformState = rememberTransformableState { zoomChange, panChange, _ ->
        val newZoom = (zoom * zoomChange).coerceIn(1f, 4f)
        zoom = newZoom
        offset = AvatarCropGeometry.clampedOffset(
            proposed = CropOffset(offset.x + panChange.x, offset.y + panChange.y),
            imageWidth = bitmap.width.toFloat(),
            imageHeight = bitmap.height.toFloat(),
            cropSide = cropSidePx,
            zoom = newZoom
        )
    }

    Dialog(
        onDismissRequest = { if (!processing) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Text("Кадрирование аватара", style = MaterialTheme.typography.titleLarge)
            Text("Сведите пальцы для масштаба и перетащите фото", style = MaterialTheme.typography.bodyMedium)
            Box(
                modifier = Modifier
                    .size(300.dp)
                    .onSizeChanged {
                        cropSidePx = it.width.toFloat().coerceAtLeast(1f)
                        offset = AvatarCropGeometry.clampedOffset(
                            offset,
                            bitmap.width.toFloat(),
                            bitmap.height.toFloat(),
                            cropSidePx,
                            zoom
                        )
                    }
                    .clip(CircleShape)
                    .background(Color.Black)
                    .transformable(transformState),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = "Предпросмотр кадрирования аватара",
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(300.dp)
                        .graphicsLayer(
                            scaleX = zoom,
                            scaleY = zoom,
                            translationX = offset.x,
                            translationY = offset.y
                        )
                )
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss, enabled = !processing) { Text("Отмена") }
                Button(
                    enabled = !processing,
                    onClick = {
                        processing = true
                        error = null
                        scope.launch {
                            cancellableRunCatching {
                                withContext(Dispatchers.Default) {
                                    AvatarCropProcessor.croppedJpeg(
                                        sourceBytes = imageBytes,
                                        cropSide = cropSidePx,
                                        zoom = zoom,
                                        offset = offset
                                    )
                                }
                            }.onSuccess(onCropped).onFailure {
                                error = it.message ?: "Не удалось кадрировать аватар"
                                processing = false
                            }
                        }
                    }
                ) {
                    if (processing) CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    else Text("Готово")
                }
            }
        }
    }
}
