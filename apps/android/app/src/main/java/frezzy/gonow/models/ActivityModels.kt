package frezzy.gonow.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class ActivityCategory(val apiValue: String) {
    WALKING("walking"),
    SPORT("sport"),
    TRAVEL("travel"),
    MUSIC("music"),
    GAMES("games"),
    FOOD("food"),
    HELP("help"),
    EDUCATION("education"),
    ANIMALS("animals"),
    EVENT("event"),
    OTHER("other");

    val titleRu: String
        get() = when (this) {
            WALKING -> "Прогулка"
            SPORT -> "Спорт"
            TRAVEL -> "Путешествия"
            MUSIC -> "Музыка"
            GAMES -> "Игры"
            FOOD -> "Еда"
            HELP -> "Помощь"
            EDUCATION -> "Образование"
            ANIMALS -> "Животные"
            EVENT -> "Мероприятие"
            OTHER -> "Другое"
        }

    companion object {
        fun fromApi(value: String): ActivityCategory =
            entries.firstOrNull { it.apiValue == value } ?: OTHER
    }
}

@Serializable
data class MapActivityResponse(
    @SerialName("id") val id: String,
    @SerialName("title") val title: String,
    @SerialName("category") val category: String,
    @SerialName("coordinate") val coordinate: MapCoordinate,
    @SerialName("startsAt") val startsAt: String? = null,
    @SerialName("participantCount") val participantCount: Int = 0,
    @SerialName("participantLimit") val participantLimit: Int? = null,
    @SerialName("distanceMeters") val distanceMeters: Double? = null,
    @SerialName("imageUrl") val imageURL: String? = null,
    @SerialName("isJoined") val isJoined: Boolean = false
) {
    val parsedCategory: ActivityCategory get() = ActivityCategory.fromApi(category)
    val isFull: Boolean get() = participantLimit?.let { participantCount >= it } ?: false
}

@Serializable
data class MapActivitiesPage(
    @SerialName("activities") val activities: List<MapActivityResponse>,
    @SerialName("viewport") val viewport: MapViewportResponse? = null
)

@Serializable
data class MapViewportResponse(
    @SerialName("south") val south: Double,
    @SerialName("west") val west: Double,
    @SerialName("north") val north: Double,
    @SerialName("east") val east: Double
)

@Serializable
data class MapActivitiesEnvelope(
    @SerialName("data") val data: MapActivitiesPage,
    @SerialName("meta") val meta: MapMeta? = null
)

@Serializable
data class MapMeta(
    @SerialName("count") val count: Int = 0,
    @SerialName("truncated") val truncated: Boolean = false,
    @SerialName("nextCursor") val nextCursor: String? = null
)

@Serializable
data class CreateActivityRequest(
    @SerialName("title") val title: String,
    @SerialName("category") val category: String,
    @SerialName("latitude") val latitude: Double,
    @SerialName("longitude") val longitude: Double,
    @SerialName("description") val description: String = "",
    @SerialName("address") val address: String? = null,
    @SerialName("venueName") val venueName: String? = null,
    @SerialName("locationVisibility") val locationVisibility: String = "everyone",
    @SerialName("startsAt") val startsAt: String? = null,
    @SerialName("durationMinutes") val durationMinutes: Int = 60,
    @SerialName("showAfter") val showAfter: String? = null,
    @SerialName("hideAfter") val hideAfter: String? = null,
    @SerialName("participantLimit") val participantLimit: Int? = null,
    @SerialName("joinPolicy") val joinPolicy: String = "request",
    @SerialName("ageMin") val ageMin: Int? = null,
    @SerialName("ageMax") val ageMax: Int? = null,
    @SerialName("skillLevel") val skillLevel: String = "any",
    @SerialName("languages") val languages: List<String> = emptyList(),
    @SerialName("costType") val costType: String = "free",
    @SerialName("costAmountCents") val costAmountCents: Int? = null,
    @SerialName("costNote") val costNote: String? = null,
    @SerialName("bringItems") val bringItems: List<String> = emptyList(),
    @SerialName("rules") val rules: List<String> = emptyList(),
    @SerialName("additionalQuestions") val additionalQuestions: List<ActivityQuestion> = emptyList(),
    @SerialName("status") val status: String = "published"
)

// ─── Full Activity Model ───────────────────────────────────────

enum class ActivityLifecycleStatus(val apiValue: String) {
    DRAFT("draft"), SCHEDULED("scheduled"), PUBLISHED("published"), FULL("full"),
    STARTED("started"), COMPLETED("completed"), CANCELLED("cancelled"),
    EXPIRED("expired"), HIDDEN("hidden"), BLOCKED("blocked");

    val titleRu: String get() = when (this) {
        DRAFT -> "Черновик"; SCHEDULED -> "Запланирована"; PUBLISHED -> "Опубликована"
        FULL -> "Мест нет"; STARTED -> "Началась"; COMPLETED -> "Завершена"
        CANCELLED -> "Отменена"; EXPIRED -> "Истекла"; HIDDEN -> "Скрыта"; BLOCKED -> "Заблокирована"
    }

    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: PUBLISHED }
}

enum class ActivityApplicationStatus(val apiValue: String) {
    PENDING("pending"), ACCEPTED("accepted"), REJECTED("rejected"),
    CANCELLED("cancelled"), EXPIRED("expired");

    val titleRu: String get() = when (this) {
        PENDING -> "Ожидает"; ACCEPTED -> "Принята"; REJECTED -> "Отклонена"
        CANCELLED -> "Отменена"; EXPIRED -> "Истекла"
    }

    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: PENDING }
}

enum class ActivityJoinPolicy(val apiValue: String) {
    REQUEST("request"), INSTANT("instant");

    val titleRu: String get() = when (this) { REQUEST -> "По заявке"; INSTANT -> "Мгновенно" }
    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: REQUEST }
}

enum class ActivityDurationPreset(val apiValue: String) {
    THIRTY_MINUTES("thirty_minutes"),
    ONE_HOUR("one_hour"),
    TWO_HOURS("two_hours"),
    THREE_HOURS("three_hours"),
    ALL_DAY("all_day"),
    CUSTOM("custom");

    val titleRu: String get() = when (this) {
        THIRTY_MINUTES -> "30 мин"
        ONE_HOUR -> "1 час"
        TWO_HOURS -> "2 часа"
        THREE_HOURS -> "3 часа"
        ALL_DAY -> "Весь день"
        CUSTOM -> "Своё время"
    }

    val minutes: Int? get() = when (this) {
        THIRTY_MINUTES -> 30
        ONE_HOUR -> 60
        TWO_HOURS -> 120
        THREE_HOURS -> 180
        ALL_DAY -> 1440
        CUSTOM -> null
    }

    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: ONE_HOUR }
}

enum class ActivityShowTiming(val apiValue: String) {
    AT_START("at_start"),
    IMMEDIATELY("immediately"),
    ONE_HOUR("one_hour"),
    SIX_HOURS("six_hours"),
    ONE_DAY("one_day"),
    THREE_DAYS("three_days"),
    ONE_WEEK("one_week"),
    CUSTOM("custom");

    val titleRu: String get() = when (this) {
        AT_START -> "В момент начала"
        IMMEDIATELY -> "Сразу"
        ONE_HOUR -> "За час"
        SIX_HOURS -> "За 6 часов"
        ONE_DAY -> "За день"
        THREE_DAYS -> "За 3 дня"
        ONE_WEEK -> "За неделю"
        CUSTOM -> "Своё время"
    }

    val leadTimeSeconds: Long? get() = when (this) {
        AT_START -> 0
        IMMEDIATELY -> 0
        ONE_HOUR -> 3600
        SIX_HOURS -> 21600
        ONE_DAY -> 86400
        THREE_DAYS -> 259200
        ONE_WEEK -> 604800
        CUSTOM -> null
    }

    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: AT_START }
}

enum class ActivityHideTiming(val apiValue: String) {
    AFTER_START("after_start"),
    AFTER_END("after_end"),
    ONE_HOUR_AFTER_END("one_hour_after_end"),
    CUSTOM("custom");

    val titleRu: String get() = when (this) {
        AFTER_START -> "После начала"
        AFTER_END -> "После окончания"
        ONE_HOUR_AFTER_END -> "Час после окончания"
        CUSTOM -> "Своё время"
    }

    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: AFTER_END }
}

enum class ActivityLocationVisibility(val apiValue: String) {
    EVERYONE("everyone"),
    ACCEPTED_PARTICIPANTS("accepted_participants"),
    ONE_HOUR_BEFORE("one_hour_before");

    val titleRu: String get() = when (this) {
        EVERYONE -> "Всем"
        ACCEPTED_PARTICIPANTS -> "Участникам"
        ONE_HOUR_BEFORE -> "За час до старта"
    }

    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: EVERYONE }
}

enum class ActivitySkillLevel(val apiValue: String) {
    ANY("any"),
    BEGINNER("beginner"),
    INTERMEDIATE("intermediate"),
    EXPERIENCED("experienced");

    val titleRu: String get() = when (this) {
        ANY -> "Любой"
        BEGINNER -> "Начинающий"
        INTERMEDIATE -> "Средний"
        EXPERIENCED -> "Опытный"
    }

    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: ANY }
}

enum class ActivityCostType(val apiValue: String) {
    FREE("free"),
    FIXED("fixed"),
    SELF_PAID("self_paid"),
    ESTIMATED("estimated");

    val titleRu: String get() = when (this) {
        FREE -> "Бесплатно"
        FIXED -> "Фиксированная цена"
        SELF_PAID -> "Каждый за себя"
        ESTIMATED -> "Примерная цена"
    }

    companion object { fun fromApi(v: String) = entries.firstOrNull { it.apiValue == v } ?: FREE }
}

@Serializable
data class GoNowActivity(
    @SerialName("id") val id: String,
    @SerialName("creatorId") val creatorId: String = "",
    @SerialName("title") val title: String,
    @SerialName("description") val description: String = "",
    @SerialName("category") val category: String = "other",
    @SerialName("photos") val photos: List<ActivityPhotoRef> = emptyList(),
    @SerialName("location") val location: ActivityLocationModel? = null,
    @SerialName("coordinate") val coordinate: MapCoordinate? = null,
    @SerialName("startsAt") val startsAt: String? = null,
    @SerialName("durationMinutes") val durationMinutes: Int = 60,
    @SerialName("showAfter") val showAfter: String? = null,
    @SerialName("hideAfter") val hideAfter: String? = null,
    @SerialName("participantCount") val participantCount: Int = 0,
    @SerialName("participantLimit") val participantLimit: Int? = null,
    @SerialName("joinPolicy") val joinPolicy: String = "request",
    @SerialName("ageMin") val ageMin: Int? = null,
    @SerialName("ageMax") val ageMax: Int? = null,
    @SerialName("languages") val languages: List<String> = emptyList(),
    @SerialName("skillLevel") val skillLevel: String = "any",
    @SerialName("costType") val costType: String = "free",
    @SerialName("costAmountCents") val costAmountCents: Int? = null,
    @SerialName("costNote") val costNote: String? = null,
    @SerialName("bringItems") val bringItems: List<String> = emptyList(),
    @SerialName("rules") val rules: List<String> = emptyList(),
    @SerialName("additionalQuestions") val additionalQuestions: List<ActivityQuestion> = emptyList(),
    @SerialName("status") val status: String = "published",
    @SerialName("recruitmentClosed") val recruitmentClosed: Boolean = false,
    @SerialName("isOrganizer") val isOrganizer: Boolean = false,
    @SerialName("applicationStatus") val applicationStatus: String? = null,
    @SerialName("canAccessChat") val canAccessChat: Boolean = false,
    @SerialName("chatConversationId") val chatConversationId: String? = null
) {
    val parsedCategory: ActivityCategory get() = ActivityCategory.fromApi(category)
    val parsedStatus: ActivityLifecycleStatus get() = ActivityLifecycleStatus.fromApi(status)
    val isFull: Boolean get() = participantLimit?.let { participantCount >= it } ?: false
}

@Serializable
data class ActivityPhotoRef(
    @SerialName("id") val id: String,
    @SerialName("contentPath") val contentPath: String = "",
    @SerialName("isCover") val isCover: Boolean = false,
    @SerialName("sortIndex") val sortIndex: Int = 0
)

@Serializable
data class ActivityLocationModel(
    @SerialName("coordinate") val coordinate: MapCoordinate,
    @SerialName("address") val address: String? = null,
    @SerialName("venueName") val venueName: String? = null,
    @SerialName("visibility") val visibility: String = "everyone",
    @SerialName("isExact") val isExact: Boolean = true
)

@Serializable
data class ActivityQuestion(
    @SerialName("id") val id: String = java.util.UUID.randomUUID().toString(),
    @SerialName("kind") val kind: String = "short_text",
    @SerialName("prompt") val prompt: String = "",
    @SerialName("options") val options: List<String> = emptyList(),
    @SerialName("required") val required: Boolean = false
)

@Serializable
data class ActivityApplicationAnswer(
    @SerialName("questionId") val questionId: String,
    @SerialName("value") val value: String
)

@Serializable
data class CreateApplicationRequest(
    @SerialName("message") val message: String? = null,
    @SerialName("answers") val answers: List<ActivityApplicationAnswer> = emptyList()
)

@Serializable
data class UpdateApplicationRequest(@SerialName("status") val status: String)

@Serializable
data class ActivityApplicant(
    @SerialName("id") val id: String,
    @SerialName("displayName") val displayName: String,
    @SerialName("rating") val rating: Double = 5.0,
    @SerialName("organizedActivities") val organizedActivities: Int = 0,
    @SerialName("avatarUrl") val avatarUrl: String? = null
)

@Serializable
data class ActivityApplication(
    @SerialName("id") val id: String,
    @SerialName("activityId") val activityId: String = "",
    @SerialName("applicant") val applicant: ActivityApplicant,
    @SerialName("status") val status: String = "pending",
    @SerialName("message") val message: String? = null,
    @SerialName("answers") val answers: List<ActivityApplicationAnswer> = emptyList(),
    @SerialName("createdAt") val createdAt: String = ""
) {
    val parsedStatus: ActivityApplicationStatus get() = ActivityApplicationStatus.fromApi(status)
}

@Serializable
data class UpdateActivityRequest(
    @SerialName("description") val description: String? = null,
    @SerialName("latitude") val latitude: Double? = null,
    @SerialName("longitude") val longitude: Double? = null,
    @SerialName("address") val address: String? = null,
    @SerialName("venueName") val venueName: String? = null,
    @SerialName("startsAt") val startsAt: String? = null,
    @SerialName("durationMinutes") val durationMinutes: Int? = null,
    @SerialName("participantLimit") val participantLimit: Int? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("recruitmentClosed") val recruitmentClosed: Boolean? = null
)

// ─── Activity Creation Draft ───────────────────────────────────

data class ActivityDraft(
    val title: String = "",
    val description: String = "",
    val category: ActivityCategory = ActivityCategory.OTHER,
    val photos: List<ActivityDraftPhoto> = emptyList(),
    val latitude: Double? = null,
    val longitude: Double? = null,
    val address: String? = null,
    val venueName: String? = null,
    val isExactLocation: Boolean = true,
    val locationVisibility: ActivityLocationVisibility = ActivityLocationVisibility.EVERYONE,
    val startsAt: String = "",
    val durationPreset: ActivityDurationPreset = ActivityDurationPreset.ONE_HOUR,
    val customDurationMinutes: Int = 60,
    val showTiming: ActivityShowTiming = ActivityShowTiming.AT_START,
    val customShowAfter: String = "",
    val hideTiming: ActivityHideTiming = ActivityHideTiming.AFTER_END,
    val customHideAfter: String = "",
    val participantLimit: Int? = null,
    val joinPolicy: ActivityJoinPolicy = ActivityJoinPolicy.REQUEST,
    val ageMin: Int? = null,
    val ageMax: Int? = null,
    val skillLevel: ActivitySkillLevel = ActivitySkillLevel.ANY,
    val languages: MutableList<String> = mutableListOf(),
    val costType: ActivityCostType = ActivityCostType.FREE,
    val costAmountCents: Int? = null,
    val costNote: String = "",
    val bringItems: MutableList<String> = mutableListOf(),
    val rules: MutableList<String> = mutableListOf(),
    val additionalQuestions: List<ActivityQuestion> = emptyList()
) {
    val durationMinutes: Int get() = durationPreset.minutes ?: maxOf(1, customDurationMinutes)
}

data class ActivityDraftPhoto(
    val uri: android.net.Uri,
    val isCover: Boolean = false
)

enum class WizardStep(val titleRu: String) {
    BASICS("Основное"),
    PHOTOS("Фото"),
    LOCATION("Место"),
    SCHEDULE("Время"),
    PARTICIPANTS("Участники"),
    PREVIEW("Предпросмотр");

    val index get() = ordinal
    val total get() = entries.size
    val progress get() = (index + 1).toFloat() / total
}
