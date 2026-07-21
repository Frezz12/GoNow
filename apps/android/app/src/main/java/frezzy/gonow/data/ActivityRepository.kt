package frezzy.gonow.data

import frezzy.gonow.models.*
import frezzy.gonow.network.ApiClient

class ActivityRepository(private val apiClient: ApiClient) {

    suspend fun getMapActivities(
        bounds: MapBounds,
        zoom: Double = 11.0,
        categories: Set<ActivityCategory>? = null,
        onlyAvailable: Boolean = false,
        limit: Int = 500
    ): MapActivitiesPage {
        val categoriesParam = categories?.takeIf { it.isNotEmpty() }
            ?.joinToString(",") { it.apiValue }
        val response = apiClient.authenticatedRequest {
            apiClient.api.getMapActivities(
                south = bounds.south, west = bounds.west, north = bounds.north, east = bounds.east,
                zoom = zoom, categories = categoriesParam,
                onlyAvailable = if (onlyAvailable) true else null, limit = limit
            )
        }
        return response.data
    }

    suspend fun createActivity(request: CreateActivityRequest): MapActivityResponse =
        apiClient.authenticatedRequest { apiClient.api.createActivity(request).data }

    suspend fun getActivity(id: String): GoNowActivity =
        apiClient.authenticatedRequest { apiClient.api.getActivity(id).data }

    suspend fun getOwnedActivities(): List<GoNowActivity> =
        apiClient.authenticatedRequest { apiClient.api.getOwnedActivities().data }

    suspend fun updateActivity(id: String, changes: UpdateActivityRequest): GoNowActivity =
        apiClient.authenticatedRequest { apiClient.api.updateActivity(id, changes).data }

    suspend fun duplicateActivity(id: String): GoNowActivity =
        apiClient.authenticatedRequest { apiClient.api.duplicateActivity(id).data }

    suspend fun applyToActivity(id: String, message: String? = null): ActivityApplication =
        apiClient.authenticatedRequest {
            val body = mutableMapOf<String, String>()
            message?.let { body["message"] = it }
            apiClient.api.applyToActivity(id, body).data
        }

    suspend fun getApplications(id: String): List<ActivityApplication> =
        apiClient.authenticatedRequest { apiClient.api.getApplications(id).data }

    suspend fun updateApplication(activityId: String, appId: String, status: String): ActivityApplication =
        apiClient.authenticatedRequest {
            apiClient.api.updateApplication(activityId, appId, mapOf("status" to status)).data
        }

    suspend fun getMapStyleJson(): String? {
        return try {
            val response = apiClient.publicRequest { apiClient.api.getMapStyle() }
            if (response.isSuccessful) response.body()?.string() else null
        } catch (_: Exception) { null }
    }

    suspend fun getPhotoContent(contentPath: String): ByteArray? {
        return try {
            apiClient.authenticatedRequest {
                val response = apiClient.api.getPhotoContent(contentPath.removePrefix("/api/v1/"))
                if (response.isSuccessful) response.body()?.bytes() else null
            }
        } catch (_: Exception) { null }
    }
}
