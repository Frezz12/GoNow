package frezzy.gonow.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import frezzy.gonow.models.ActivityCategory
import frezzy.gonow.models.ActivityCostType
import frezzy.gonow.models.ActivityDraft
import frezzy.gonow.models.ActivityDraftPhoto
import frezzy.gonow.models.ActivityDurationPreset
import frezzy.gonow.models.ActivityHideTiming
import frezzy.gonow.models.ActivityJoinPolicy
import frezzy.gonow.models.ActivityLocationVisibility
import frezzy.gonow.models.ActivityQuestion
import frezzy.gonow.models.ActivityShowTiming
import frezzy.gonow.models.ActivitySkillLevel
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class ActivityDraftStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("gonow_activity_draft", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun load(): ActivityDraft? = prefs.getString(KEY_DRAFT, null)?.let { value ->
        runCatching { json.decodeFromString<ActivityDraftSnapshot>(value).toDraft() }.getOrNull()
    }

    fun save(draft: ActivityDraft) {
        prefs.edit().putString(KEY_DRAFT, json.encodeToString(ActivityDraftSnapshot.from(draft))).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY_DRAFT).remove(KEY_PENDING_UPLOAD).apply()
    }

    fun pendingUpload(): PendingActivityUpload? = prefs.getString(KEY_PENDING_UPLOAD, null)?.let { value ->
        runCatching { json.decodeFromString<PendingActivityUpload>(value) }.getOrNull()
    }

    fun savePendingUpload(value: PendingActivityUpload) {
        prefs.edit().putString(KEY_PENDING_UPLOAD, json.encodeToString(value)).commit()
    }

    fun clearPendingUpload() {
        prefs.edit().remove(KEY_PENDING_UPLOAD).apply()
    }

    private companion object {
        const val KEY_DRAFT = "draft"
        const val KEY_PENDING_UPLOAD = "pending_upload"
    }
}

@Serializable
data class PendingActivityUpload(val activityId: String, val uploadedPhotos: Int = 0)

interface ActivityPhotoProcessor {
    suspend fun jpeg(uri: Uri, maxSide: Int = 2_048, quality: Int = 85): ByteArray
}

class AndroidActivityPhotoProcessor(private val context: Context) : ActivityPhotoProcessor {
    override suspend fun jpeg(uri: Uri, maxSide: Int, quality: Int): ByteArray =
        withContext(Dispatchers.IO) {
            val bitmap = decodeLegacy(uri, maxSide)
            ByteArrayOutputStream().use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(60, 95), output))
                output.toByteArray()
            }
        }

    private fun decodeLegacy(uri: Uri, maxSide: Int): Bitmap =
        context.contentResolver.openInputStream(uri).use { stream ->
            requireNotNull(BitmapFactory.decodeStream(stream)) { "Unable to decode selected photo" }
        }.scaledTo(maxSide)

    private fun Bitmap.scaledTo(maxSide: Int): Bitmap {
        val largest = max(width, height)
        if (largest <= maxSide) return this
        val scale = maxSide.toFloat() / largest
        return Bitmap.createScaledBitmap(this, (width * scale).toInt(), (height * scale).toInt(), true)
    }
}

@Serializable
private data class ActivityDraftSnapshot(
    val title: String,
    val description: String,
    val category: String,
    val photos: List<DraftPhotoSnapshot>,
    val latitude: Double?,
    val longitude: Double?,
    val address: String?,
    val venueName: String?,
    val isExactLocation: Boolean,
    val locationVisibility: String,
    val startsAt: String,
    val durationPreset: String,
    val customDurationMinutes: Int,
    val showTiming: String,
    val customShowAfter: String,
    val hideTiming: String,
    val customHideAfter: String,
    val participantLimit: Int?,
    val joinPolicy: String,
    val ageMin: Int?,
    val ageMax: Int?,
    val skillLevel: String,
    val languages: List<String>,
    val costType: String,
    val costAmountCents: Int?,
    val costNote: String,
    val bringItems: List<String>,
    val rules: List<String>,
    val additionalQuestions: List<ActivityQuestion>
) {
    fun toDraft() = ActivityDraft(
        title = title,
        description = description,
        category = ActivityCategory.fromApi(category),
        photos = photos.map { ActivityDraftPhoto(Uri.parse(it.uri), it.isCover) },
        latitude = latitude,
        longitude = longitude,
        address = address,
        venueName = venueName,
        isExactLocation = isExactLocation,
        locationVisibility = ActivityLocationVisibility.fromApi(locationVisibility),
        startsAt = startsAt,
        durationPreset = ActivityDurationPreset.fromApi(durationPreset),
        customDurationMinutes = customDurationMinutes,
        showTiming = ActivityShowTiming.fromApi(showTiming),
        customShowAfter = customShowAfter,
        hideTiming = ActivityHideTiming.fromApi(hideTiming),
        customHideAfter = customHideAfter,
        participantLimit = participantLimit,
        joinPolicy = ActivityJoinPolicy.fromApi(joinPolicy),
        ageMin = ageMin,
        ageMax = ageMax,
        skillLevel = ActivitySkillLevel.fromApi(skillLevel),
        languages = languages.toMutableList(),
        costType = ActivityCostType.fromApi(costType),
        costAmountCents = costAmountCents,
        costNote = costNote,
        bringItems = bringItems.toMutableList(),
        rules = rules.toMutableList(),
        additionalQuestions = additionalQuestions
    )

    companion object {
        fun from(draft: ActivityDraft) = ActivityDraftSnapshot(
            title = draft.title,
            description = draft.description,
            category = draft.category.apiValue,
            photos = draft.photos.map { DraftPhotoSnapshot(it.uri.toString(), it.isCover) },
            latitude = draft.latitude,
            longitude = draft.longitude,
            address = draft.address,
            venueName = draft.venueName,
            isExactLocation = draft.isExactLocation,
            locationVisibility = draft.locationVisibility.apiValue,
            startsAt = draft.startsAt,
            durationPreset = draft.durationPreset.apiValue,
            customDurationMinutes = draft.customDurationMinutes,
            showTiming = draft.showTiming.apiValue,
            customShowAfter = draft.customShowAfter,
            hideTiming = draft.hideTiming.apiValue,
            customHideAfter = draft.customHideAfter,
            participantLimit = draft.participantLimit,
            joinPolicy = draft.joinPolicy.apiValue,
            ageMin = draft.ageMin,
            ageMax = draft.ageMax,
            skillLevel = draft.skillLevel.apiValue,
            languages = draft.languages,
            costType = draft.costType.apiValue,
            costAmountCents = draft.costAmountCents,
            costNote = draft.costNote,
            bringItems = draft.bringItems,
            rules = draft.rules,
            additionalQuestions = draft.additionalQuestions
        )
    }
}

@Serializable
private data class DraftPhotoSnapshot(val uri: String, val isCover: Boolean)
