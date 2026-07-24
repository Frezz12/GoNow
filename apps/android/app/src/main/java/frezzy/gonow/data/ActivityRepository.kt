package frezzy.gonow.data

import frezzy.gonow.models.*
import frezzy.gonow.network.ApiClient
import frezzy.gonow.models.ApiError
import frezzy.gonow.core.throwIfCancellation

class ActivityRepository(private val apiClient: ApiClient) {

    suspend fun getMapActivities(
        bounds: MapBounds,
        zoom: Double = 11.0,
        categories: Set<ActivityCategory>? = null,
        onlyAvailable: Boolean = false,
        startsFrom: String? = null,
        startsTo: String? = null,
        limit: Int = 500
    ): MapActivitiesPage {
        val categoriesParam = categories?.takeIf { it.isNotEmpty() }
            ?.joinToString(",") { it.apiValue }
        val response = apiClient.authenticatedRequest {
            apiClient.api.getMapActivities(
                south = bounds.south, west = bounds.west, north = bounds.north, east = bounds.east,
                zoom = zoom, categories = categoriesParam,
                startsFrom = startsFrom, startsTo = startsTo,
                onlyAvailable = if (onlyAvailable) true else null, limit = limit
            )
        }
        return response.data
    }

    suspend fun createActivity(request: CreateActivityRequest): GoNowActivity =
        apiClient.authenticatedRequest { apiClient.api.createActivity(request).data }

    suspend fun uploadActivityPhoto(
        activityId: String,
        bytes: ByteArray,
        sortIndex: Int,
        isCover: Boolean
    ): ActivityPhotoRef = apiClient.authenticatedRequest {
        apiClient.api.uploadActivityPhoto(
            id = activityId,
            sortIndex = sortIndex,
            isCover = isCover,
            file = apiClient.createImagePart(bytes, "activity-$sortIndex.jpg")
        ).data
    }

    suspend fun getActivity(id: String): GoNowActivity =
        apiClient.authenticatedRequest { apiClient.api.getActivity(id).data }

    suspend fun getOwnedActivities(): List<GoNowActivity> =
        apiClient.authenticatedRequest { apiClient.api.getOwnedActivities().data }

    suspend fun getParticipatingActivities(): List<GoNowActivity> =
        apiClient.authenticatedRequest { apiClient.api.getParticipatingActivities().data }

    suspend fun updateActivity(id: String, changes: UpdateActivityRequest): GoNowActivity =
        apiClient.authenticatedRequest { apiClient.api.updateActivity(id, changes).data }

    suspend fun duplicateActivity(id: String): GoNowActivity =
        apiClient.authenticatedRequest { apiClient.api.duplicateActivity(id).data }

    suspend fun applyToActivity(
        id: String,
        message: String? = null,
        answers: List<ActivityApplicationAnswer> = emptyList()
    ): ActivityApplication =
        apiClient.authenticatedRequest {
            apiClient.api.applyToActivity(id, CreateApplicationRequest(message, answers)).data
        }

    suspend fun getApplications(id: String): List<ActivityApplication> =
        apiClient.authenticatedRequest { apiClient.api.getApplications(id).data }

    suspend fun updateApplication(activityId: String, appId: String, status: String): ActivityApplication =
        apiClient.authenticatedRequest {
            apiClient.api.updateApplication(activityId, appId, UpdateApplicationRequest(status)).data
        }

    suspend fun getMapStyleJson(): String? {
        return try {
            val response = apiClient.publicRequest { apiClient.api.getMapStyle() }
            if (response.isSuccessful) response.body()?.string() else null
        } catch (error: Exception) {
            error.throwIfCancellation()
            null
        }
    }

    suspend fun getPhotoContent(contentPath: String): ByteArray =
        apiClient.authenticatedRequest {
            val response = apiClient.api.getContent(contentPath.toApiRelativePath())
            if (!response.isSuccessful) throw ApiError.Http(response.code())
            response.body()?.bytes() ?: throw ApiError.Decoding("Empty photo response")
        }
}

internal fun String.toApiRelativePath(): String =
    trim().removePrefix("/").removePrefix("api/v1/")

fun GoNowActivity.toMapActivityResponse(): MapActivityResponse = MapActivityResponse(
    id = id,
    title = title,
    category = category,
    coordinate = location?.coordinate ?: coordinate ?: MapCoordinate(0.0, 0.0),
    startsAt = startsAt,
    participantCount = participantCount,
    participantLimit = participantLimit,
    imageURL = photos.firstOrNull { it.isCover }?.contentPath ?: photos.firstOrNull()?.contentPath,
    isJoined = applicationStatus == "accepted" || isOrganizer
)
