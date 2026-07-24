package frezzy.gonow.features.activity

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.ActivityRepository
import frezzy.gonow.data.ActivityDraftStore
import frezzy.gonow.data.ActivityPhotoProcessor
import frezzy.gonow.data.PendingActivityUpload
import frezzy.gonow.models.*
import frezzy.gonow.core.throwIfCancellation
import kotlinx.coroutines.launch

class ActivityCreationViewModel(
    private val repository: ActivityRepository,
    private val draftStore: ActivityDraftStore,
    private val photoProcessor: ActivityPhotoProcessor
) : ViewModel() {

    var draft by mutableStateOf(draftStore.load() ?: ActivityDraft())
        private set

    var step by mutableIntStateOf(WizardStep.BASICS.index)
        private set

    var isSubmitting by mutableStateOf(false)
        private set

    var errorMessage by mutableStateOf<String?>(null)
        private set

    var publishedActivity by mutableStateOf<GoNowActivity?>(null)
        private set

    val currentStep: WizardStep get() = WizardStep.entries[step]
    val isLastStep: Boolean get() = step == WizardStep.PREVIEW.index
    val canMoveForward: Boolean get() = validateCurrentStep() == null

    fun updateTitle(title: String) {
        if (title.length <= 70) updateDraft(draft.copy(title = title))
    }

    fun updateDescription(desc: String) {
        if (desc.length <= 3000) updateDraft(draft.copy(description = desc))
    }

    fun updateCategory(category: ActivityCategory) {
        updateDraft(draft.copy(category = category))
    }

    fun updateStartsAt(startsAt: String) {
        updateDraft(draft.copy(startsAt = startsAt))
    }

    fun updateDurationPreset(preset: ActivityDurationPreset) {
        updateDraft(draft.copy(durationPreset = preset))
    }

    fun updateCustomDuration(minutes: Int) {
        updateDraft(draft.copy(customDurationMinutes = minutes))
    }

    fun updateShowTiming(timing: ActivityShowTiming) {
        updateDraft(draft.copy(showTiming = timing))
    }

    fun updateHideTiming(timing: ActivityHideTiming) {
        updateDraft(draft.copy(hideTiming = timing))
    }

    fun updateParticipantLimit(limit: Int?) {
        updateDraft(draft.copy(participantLimit = limit))
    }

    fun updateJoinPolicy(policy: ActivityJoinPolicy) {
        updateDraft(draft.copy(joinPolicy = policy))
    }

    fun updateAgeMin(age: Int?) {
        updateDraft(draft.copy(ageMin = age))
    }

    fun updateAgeMax(age: Int?) = updateDraft(draft.copy(ageMax = age))

    fun updateSkillLevel(level: ActivitySkillLevel) {
        updateDraft(draft.copy(skillLevel = level))
    }

    fun updateLocationVisibility(visibility: ActivityLocationVisibility) {
        updateDraft(draft.copy(locationVisibility = visibility))
    }

    fun updateCostType(type: ActivityCostType) {
        updateDraft(draft.copy(costType = type))
    }

    fun updateCostAmount(cents: Int?) {
        updateDraft(draft.copy(costAmountCents = cents))
    }

    fun updateCostNote(note: String) = updateDraft(draft.copy(costNote = note.take(500)))

    fun updateLocation(lat: Double, lon: Double) {
        updateDraft(draft.copy(latitude = lat, longitude = lon))
    }

    fun updateLocationDetails(address: String?, venueName: String?, isExact: Boolean) =
        updateDraft(draft.copy(address = address, venueName = venueName, isExactLocation = isExact))

    fun addPhoto(uri: Uri) {
        if (draft.photos.size >= 6) return
        val isCover = draft.photos.isEmpty()
        updateDraft(draft.copy(photos = draft.photos + ActivityDraftPhoto(uri = uri, isCover = isCover)))
    }

    fun removePhoto(index: Int) {
        val photos = draft.photos.toMutableList()
        if (index !in photos.indices) return
        val wasCover = photos[index].isCover
        photos.removeAt(index)
        if (wasCover && photos.isNotEmpty()) photos[0] = photos[0].copy(isCover = true)
        updateDraft(draft.copy(photos = photos))
    }

    fun makeCover(index: Int) {
        val photos = draft.photos.toMutableList()
        if (index !in photos.indices) return
        photos.forEachIndexed { i, p -> photos[i] = p.copy(isCover = i == index) }
        val photo = photos.removeAt(index)
        photos.add(0, photo)
        updateDraft(draft.copy(photos = photos))
    }

    fun movePhoto(index: Int, direction: Int) {
        val photos = draft.photos.toMutableList()
        if (index !in photos.indices) return
        val dest = (index + direction).coerceIn(0, photos.size - 1)
        if (index == dest) return
        photos.swap(index, dest)
        updateDraft(draft.copy(photos = photos))
    }

    fun addLanguage(language: String) {
        val clean = language.trim()
        if (clean.isBlank() || draft.languages.contains(clean)) return
        updateDraft(draft.copy(languages = (draft.languages + clean).toMutableList()))
    }

    fun removeLanguage(language: String) {
        updateDraft(draft.copy(languages = draft.languages.filter { it != language }.toMutableList()))
    }

    fun addBringItem(item: String) {
        val clean = item.trim()
        if (clean.isBlank() || draft.bringItems.contains(clean)) return
        updateDraft(draft.copy(bringItems = (draft.bringItems + clean).toMutableList()))
    }

    fun removeBringItem(item: String) {
        updateDraft(draft.copy(bringItems = draft.bringItems.filter { it != item }.toMutableList()))
    }

    fun addRule(rule: String) {
        val clean = rule.trim()
        if (clean.isBlank() || draft.rules.contains(clean)) return
        updateDraft(draft.copy(rules = (draft.rules + clean).toMutableList()))
    }

    fun removeRule(rule: String) {
        updateDraft(draft.copy(rules = draft.rules.filter { it != rule }.toMutableList()))
    }

    fun addQuestion(question: ActivityQuestion) =
        updateDraft(draft.copy(additionalQuestions = draft.additionalQuestions + question))

    fun removeQuestion(id: String) =
        updateDraft(draft.copy(additionalQuestions = draft.additionalQuestions.filterNot { it.id == id }))

    fun moveForward() {
        val error = validateCurrentStep()
        if (error != null) {
            errorMessage = error
            return
        }
        errorMessage = null
        if (step < WizardStep.PREVIEW.index) step++
    }

    fun moveBack() {
        errorMessage = null
        if (step > 0) step--
    }

    fun submit() {
        val currentDraft = draft
        val cleanTitle = currentDraft.title.trim()
        val lat = currentDraft.latitude
        val lon = currentDraft.longitude
        val coord = if (lat != null && lon != null) MapCoordinate(lat, lon) else null

        if (cleanTitle.length < 2 || coord == null || !coord.isValid) {
            errorMessage = "Заполните название и выберите местоположение"
            return
        }

        isSubmitting = true
        errorMessage = null
        viewModelScope.launch {
            try {
                val startsAt = currentDraft.startsAt.ifBlank {
                    java.time.Instant.now().plusSeconds(3_600).toString()
                }
                val createRequest = CreateActivityRequest(
                        title = cleanTitle,
                        category = currentDraft.category.apiValue,
                        latitude = coord.latitude,
                        longitude = coord.longitude,
                        description = currentDraft.description,
                        address = currentDraft.address,
                        venueName = currentDraft.venueName,
                        locationVisibility = currentDraft.locationVisibility.apiValue,
                        startsAt = startsAt,
                        durationMinutes = currentDraft.durationMinutes,
                        showAfter = computeShowAfter(currentDraft, startsAt),
                        hideAfter = computeHideAfter(currentDraft, startsAt),
                        participantLimit = currentDraft.participantLimit,
                        joinPolicy = currentDraft.joinPolicy.apiValue,
                        ageMin = currentDraft.ageMin,
                        ageMax = currentDraft.ageMax,
                        skillLevel = currentDraft.skillLevel.apiValue,
                        languages = currentDraft.languages,
                        costType = currentDraft.costType.apiValue,
                        costAmountCents = currentDraft.costAmountCents,
                        costNote = currentDraft.costNote.trim().ifBlank { null },
                        bringItems = currentDraft.bringItems,
                        rules = currentDraft.rules,
                        additionalQuestions = currentDraft.additionalQuestions,
                        status = if (currentDraft.photos.isEmpty()) "published" else "draft"
                    )
                suspend fun createFreshActivity(): GoNowActivity =
                    repository.createActivity(createRequest).also {
                        draftStore.savePendingUpload(PendingActivityUpload(it.id))
                    }
                var pending = draftStore.pendingUpload()
                val created = if (pending == null) {
                    createFreshActivity()
                } else {
                    val savedPending = requireNotNull(pending)
                    try {
                        repository.getActivity(savedPending.activityId)
                    } catch (error: ApiError) {
                        val statusCode = when (error) {
                            is ApiError.Http -> error.statusCode
                            is ApiError.Server -> error.statusCode
                            else -> null
                        }
                        if (statusCode != 404) throw error
                        draftStore.clearPendingUpload()
                        pending = null
                        createFreshActivity()
                    }
                }

                var uploaded = pending?.uploadedPhotos ?: 0
                currentDraft.photos.drop(uploaded).forEachIndexed { offset, photo ->
                    val index = uploaded + offset
                    val bytes = photoProcessor.jpeg(photo.uri)
                    repository.uploadActivityPhoto(created.id, bytes, index, photo.isCover)
                    draftStore.savePendingUpload(PendingActivityUpload(created.id, index + 1))
                }
                repository.updateActivity(created.id, UpdateActivityRequest(status = "published"))
                publishedActivity = repository.getActivity(created.id)
                draftStore.clear()
            } catch (e: Exception) {
                e.throwIfCancellation()
                errorMessage = e.message
            } finally {
                isSubmitting = false
            }
        }
    }

    fun dismissError() {
        errorMessage = null
    }

    fun reset() {
        draftStore.clear()
        draft = ActivityDraft()
        step = WizardStep.BASICS.index
        isSubmitting = false
        errorMessage = null
        publishedActivity = null
    }

    private fun updateDraft(value: ActivityDraft) {
        draft = value
        draftStore.save(value)
    }

    private fun computeShowAfter(value: ActivityDraft, startsAt: String): String {
        val start = parseInstant(startsAt)
        return when (value.showTiming) {
            ActivityShowTiming.IMMEDIATELY -> java.time.Instant.now().toString()
            ActivityShowTiming.CUSTOM -> value.customShowAfter.takeIf { it.isNotBlank() } ?: startsAt
            else -> start.minusSeconds(value.showTiming.leadTimeSeconds ?: 0).toString()
        }
    }

    private fun computeHideAfter(value: ActivityDraft, startsAt: String): String {
        val start = parseInstant(startsAt)
        val end = start.plusSeconds(value.durationMinutes * 60L)
        return when (value.hideTiming) {
            ActivityHideTiming.AFTER_START -> start
            ActivityHideTiming.AFTER_END -> end
            ActivityHideTiming.ONE_HOUR_AFTER_END -> end.plusSeconds(3_600)
            ActivityHideTiming.CUSTOM -> parseInstant(value.customHideAfter.ifBlank { end.toString() })
        }.toString()
    }

    private fun parseInstant(value: String): java.time.Instant =
        runCatching { java.time.Instant.parse(value) }.getOrElse {
            runCatching { java.time.OffsetDateTime.parse(value).toInstant() }
                .getOrElse { java.time.Instant.now().plusSeconds(3_600) }
        }

    private fun validateCurrentStep(): String? {
        return when (currentStep) {
            WizardStep.BASICS -> {
                val titleLen = draft.title.trim().length
                if (titleLen < 2 || titleLen > 70) "Название должно содержать от 2 до 70 символов"
                else null
            }
            WizardStep.PHOTOS -> null
            WizardStep.LOCATION -> null
            WizardStep.SCHEDULE -> null
            WizardStep.PARTICIPANTS -> null
            WizardStep.PREVIEW -> null
        }
    }
}

private fun <T> MutableList<T>.swap(i: Int, j: Int) {
    val tmp = this[i]
    this[i] = this[j]
    this[j] = tmp
}
