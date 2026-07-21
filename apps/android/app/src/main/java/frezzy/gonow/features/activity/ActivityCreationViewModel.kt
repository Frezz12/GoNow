package frezzy.gonow.features.activity

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import frezzy.gonow.data.ActivityRepository
import frezzy.gonow.models.*
import kotlinx.coroutines.launch

class ActivityCreationViewModel(private val repository: ActivityRepository) : ViewModel() {

    var draft by mutableStateOf(ActivityDraft())

    var step by mutableIntStateOf(WizardStep.BASICS.index)
        private set

    var isSubmitting by mutableStateOf(false)
        private set

    var errorMessage by mutableStateOf<String?>(null)
        private set

    var publishedActivity by mutableStateOf<MapActivityResponse?>(null)
        private set

    val currentStep: WizardStep get() = WizardStep.entries[step]
    val isLastStep: Boolean get() = step == WizardStep.PREVIEW.index
    val canMoveForward: Boolean get() = validateCurrentStep() == null

    fun updateTitle(title: String) {
        if (title.length <= 70) draft = draft.copy(title = title)
    }

    fun updateDescription(desc: String) {
        if (desc.length <= 3000) draft = draft.copy(description = desc)
    }

    fun updateCategory(category: ActivityCategory) {
        draft = draft.copy(category = category)
    }

    fun updateStartsAt(startsAt: String) {
        draft = draft.copy(startsAt = startsAt)
    }

    fun updateDurationPreset(preset: ActivityDurationPreset) {
        draft = draft.copy(durationPreset = preset)
    }

    fun updateCustomDuration(minutes: Int) {
        draft = draft.copy(customDurationMinutes = minutes)
    }

    fun updateShowTiming(timing: ActivityShowTiming) {
        draft = draft.copy(showTiming = timing)
    }

    fun updateHideTiming(timing: ActivityHideTiming) {
        draft = draft.copy(hideTiming = timing)
    }

    fun updateParticipantLimit(limit: Int?) {
        draft = draft.copy(participantLimit = limit)
    }

    fun updateJoinPolicy(policy: ActivityJoinPolicy) {
        draft = draft.copy(joinPolicy = policy)
    }

    fun updateAgeMin(age: Int?) {
        draft = draft.copy(ageMin = age)
    }

    fun updateSkillLevel(level: ActivitySkillLevel) {
        draft = draft.copy(skillLevel = level)
    }

    fun updateLocationVisibility(visibility: ActivityLocationVisibility) {
        draft = draft.copy(locationVisibility = visibility)
    }

    fun updateCostType(type: ActivityCostType) {
        draft = draft.copy(costType = type)
    }

    fun updateCostAmount(cents: Int?) {
        draft = draft.copy(costAmountCents = cents)
    }

    fun updateLocation(lat: Double, lon: Double) {
        draft = draft.copy(latitude = lat, longitude = lon)
    }

    fun addPhoto(uri: Uri) {
        if (draft.photos.size >= 6) return
        val isCover = draft.photos.isEmpty()
        draft = draft.copy(photos = draft.photos + ActivityDraftPhoto(uri = uri, isCover = isCover))
    }

    fun removePhoto(index: Int) {
        val photos = draft.photos.toMutableList()
        if (index !in photos.indices) return
        val wasCover = photos[index].isCover
        photos.removeAt(index)
        if (wasCover && photos.isNotEmpty()) photos[0] = photos[0].copy(isCover = true)
        draft = draft.copy(photos = photos)
    }

    fun makeCover(index: Int) {
        val photos = draft.photos.toMutableList()
        if (index !in photos.indices) return
        photos.forEachIndexed { i, p -> photos[i] = p.copy(isCover = i == index) }
        val photo = photos.removeAt(index)
        photos.add(0, photo)
        draft = draft.copy(photos = photos)
    }

    fun movePhoto(index: Int, direction: Int) {
        val photos = draft.photos.toMutableList()
        if (index !in photos.indices) return
        val dest = (index + direction).coerceIn(0, photos.size - 1)
        if (index == dest) return
        photos.swap(index, dest)
        draft = draft.copy(photos = photos)
    }

    fun addLanguage(language: String) {
        val clean = language.trim()
        if (clean.isBlank() || draft.languages.contains(clean)) return
        draft = draft.copy(languages = (draft.languages + clean).toMutableList())
    }

    fun removeLanguage(language: String) {
        draft = draft.copy(languages = draft.languages.filter { it != language }.toMutableList())
    }

    fun addBringItem(item: String) {
        val clean = item.trim()
        if (clean.isBlank() || draft.bringItems.contains(clean)) return
        draft = draft.copy(bringItems = (draft.bringItems + clean).toMutableList())
    }

    fun removeBringItem(item: String) {
        draft = draft.copy(bringItems = draft.bringItems.filter { it != item }.toMutableList())
    }

    fun addRule(rule: String) {
        val clean = rule.trim()
        if (clean.isBlank() || draft.rules.contains(clean)) return
        draft = draft.copy(rules = (draft.rules + clean).toMutableList())
    }

    fun removeRule(rule: String) {
        draft = draft.copy(rules = draft.rules.filter { it != rule }.toMutableList())
    }

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
                val activity = repository.createActivity(
                    CreateActivityRequest(
                        title = cleanTitle,
                        category = currentDraft.category.apiValue,
                        latitude = coord.latitude,
                        longitude = coord.longitude,
                        description = currentDraft.description,
                        startsAt = currentDraft.startsAt.ifBlank { null },
                        durationMinutes = currentDraft.durationMinutes,
                        participantLimit = currentDraft.participantLimit,
                        joinPolicy = currentDraft.joinPolicy.apiValue,
                        ageMin = currentDraft.ageMin,
                        skillLevel = currentDraft.skillLevel.apiValue,
                        languages = currentDraft.languages,
                        costType = currentDraft.costType.apiValue,
                        costAmountCents = currentDraft.costAmountCents,
                        bringItems = currentDraft.bringItems,
                        rules = currentDraft.rules
                    )
                )
                publishedActivity = activity
            } catch (e: Exception) {
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
        draft = ActivityDraft()
        step = WizardStep.BASICS.index
        isSubmitting = false
        errorMessage = null
        publishedActivity = null
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
