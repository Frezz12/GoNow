package frezzy.gonow.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class MapCoordinate(
    @SerialName("latitude") val latitude: Double,
    @SerialName("longitude") val longitude: Double
) {
    val isValid: Boolean
        get() = latitude.isFinite() && longitude.isFinite()
            && latitude in -90.0..90.0 && longitude in -180.0..180.0
}

@Serializable
data class MapBounds(
    @SerialName("south") val south: Double,
    @SerialName("west") val west: Double,
    @SerialName("north") val north: Double,
    @SerialName("east") val east: Double
) {
    val crossesAntimeridian: Boolean get() = west > east

    fun contains(coordinate: MapCoordinate): Boolean {
        if (coordinate.latitude < south || coordinate.latitude > north) return false
        return if (crossesAntimeridian) {
            coordinate.longitude >= west || coordinate.longitude <= east
        } else {
            coordinate.longitude >= west && coordinate.longitude <= east
        }
    }

    fun expanded(factor: Double = 0.2): MapBounds {
        val latPad = (north - south) * factor
        val lonSpan = if (crossesAntimeridian) (180 - west) + (east + 180) else east - west
        val lonPad = lonSpan * factor
        return MapBounds(
            south = maxOf(-85.0, south - latPad),
            west = west - lonPad,
            north = minOf(85.0, north + latPad),
            east = east + lonPad
        )
    }
}

@Serializable
data class MapFilterState(
    val categories: Set<ActivityCategory> = emptySet(),
    val startsWithinHours: Int? = null,
    val onlyAvailable: Boolean = false
) {
    val isEmpty: Boolean get() = categories.isEmpty() && startsWithinHours == null && !onlyAvailable
    val activeCount: Int get() = categories.size + (if (startsWithinHours != null) 1 else 0) + (if (onlyAvailable) 1 else 0)
}

@Serializable
data class PersistedMapCamera(
    @SerialName("center") val center: MapCoordinate,
    @SerialName("zoom") val zoom: Double,
    @SerialName("bearing") val bearing: Double = 0.0,
    @SerialName("pitch") val pitch: Double = 0.0
)

enum class MapContentState {
    Initial, Loading, Loaded, Empty, Failed
}

data class MapViewport(
    val bounds: MapBounds,
    val center: MapCoordinate,
    val zoom: Double
)
