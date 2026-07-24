package frezzy.gonow.features.map

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Log
import android.view.ViewGroup
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import frezzy.gonow.models.ActivityCategory
import frezzy.gonow.models.MapActivityResponse
import frezzy.gonow.models.MapBounds
import frezzy.gonow.models.MapCoordinate
import frezzy.gonow.models.MapViewport
import frezzy.gonow.models.PersistedMapCamera
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapView
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.Point

private object MapLayerIds {
    const val ACTIVITIES_SOURCE = "gonow-activities"
    const val ACTIVITIES_MARKERS = "gonow-activity-markers"
    const val SELECTED_HALO = "gonow-selected-activity-halo"
    const val USER_SOURCE = "gonow-user-location"
    const val USER_HALO = "gonow-user-location-halo"
    const val USER_POINT = "gonow-user-location-point"
}

private val categoryColors = mapOf(
    "walking" to Color.parseColor("#4CAF50"),
    "sport" to Color.parseColor("#F44336"),
    "travel" to Color.parseColor("#2196F3"),
    "music" to Color.parseColor("#9C27B0"),
    "games" to Color.parseColor("#3F51B5"),
    "food" to Color.parseColor("#FF9800"),
    "help" to Color.parseColor("#009688"),
    "education" to Color.parseColor("#795548"),
    "animals" to Color.parseColor("#00C853"),
    "event" to Color.parseColor("#E91E63"),
    "other" to Color.parseColor("#9E9E9E")
)

@Composable
fun MapLibreMapView(
    modifier: Modifier = Modifier,
    styleJson: String?,
    activities: List<MapActivityResponse>,
    userCoordinate: MapCoordinate?,
    selectedActivityId: String?,
    initialCamera: PersistedMapCamera?,
    onViewportIdle: (MapViewport) -> Unit,
    onCameraMove: (MapCoordinate) -> Unit = {},
    onActivityTap: (String) -> Unit,
    onMapTap: (MapCoordinate) -> Unit,
    pickerMode: Boolean = false
) {
    // MapLibre's native renderer currently crashes Android's x86 emulator.
    // Keep the production renderer on devices and use the WebView map only there.
    if (android.os.Build.SUPPORTED_ABIS.any { it.contains("x86") }) {
        EmulatorRasterMapView(
            modifier = modifier,
            activities = activities,
            userCoordinate = userCoordinate,
            selectedActivityId = selectedActivityId,
            initialCamera = initialCamera,
            onViewportIdle = onViewportIdle,
            onCameraMove = onCameraMove,
            onActivityTap = onActivityTap,
            onMapTap = onMapTap,
            pickerMode = pickerMode
        )
        return
    }

    if (styleJson == null) {
        Box(
            modifier = modifier.background(androidx.compose.ui.graphics.Color(0xFFF6F2F5))
        )
        return
    }

    var isSetup by remember { mutableStateOf(false) }
    var mapView by remember { mutableStateOf<MapView?>(null) }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            val mv = mapView ?: return@LifecycleEventObserver
            try {
                when (event) {
                    Lifecycle.Event.ON_START -> mv.onStart()
                    Lifecycle.Event.ON_RESUME -> mv.onResume()
                    Lifecycle.Event.ON_PAUSE -> mv.onPause()
                    Lifecycle.Event.ON_STOP -> mv.onStop()
                    else -> {}
                }
            } catch (e: Exception) {
                Log.w("MapLibreMapView", "Lifecycle event failed", e)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            MapView(ctx).apply {
                onCreate(null)
                if (lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) onStart()
                if (lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) onResume()
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
        },
        onRelease = { mv ->
            try {
                mv.onPause()
                mv.onStop()
                mv.onDestroy()
            } catch (e: Exception) {
                Log.w("MapLibreMapView", "MapView destroy failed", e)
            }
            mapView = null
        },
        update = { mv ->
            mapView = mv
            if (!isSetup) {
                isSetup = true
                setupMap(
                    mapView = mv,
                    styleJson = styleJson,
                    initialCamera = initialCamera,
                    onViewportIdle = onViewportIdle,
                    onCameraMove = onCameraMove,
                    onActivityTap = onActivityTap,
                    onMapTap = onMapTap,
                    pickerMode = pickerMode
                )
            }
            if (isSetup) {
                updateActivities(mv, activities, userCoordinate, selectedActivityId)
            }
        }
    )
}

private fun setupMap(
    mapView: MapView,
    styleJson: String,
    initialCamera: PersistedMapCamera?,
    onViewportIdle: (MapViewport) -> Unit,
    onCameraMove: (MapCoordinate) -> Unit,
    onActivityTap: (String) -> Unit,
    onMapTap: (MapCoordinate) -> Unit,
    pickerMode: Boolean
) {
    mapView.getMapAsync { map ->
        initialCamera?.let { camera ->
            map.cameraPosition = CameraPosition.Builder()
                .target(LatLng(camera.center.latitude, camera.center.longitude))
                .zoom(camera.zoom)
                .bearing(camera.bearing)
                .tilt(camera.pitch)
                .build()
        }
        map.uiSettings.apply {
            isAttributionEnabled = false
            isLogoEnabled = false
            // Keep navigation direct: pan with one finger, zoom only with pinch.
            isScrollGesturesEnabled = true
            isZoomGesturesEnabled = true
            isDoubleTapGesturesEnabled = false
            isQuickZoomGesturesEnabled = false
        }
        map.setStyle(styleJson) { style ->
            for ((category, color) in categoryColors) {
                style.addImage("gonow-pin-$category", createPinDrawable(color, 38f))
                style.addImage("gonow-pin-$category-sel", createPinDrawable(color, 46f))
            }

            style.addSource(GeoJsonSource(MapLayerIds.ACTIVITIES_SOURCE, FeatureCollection.fromFeatures(emptyList())))
            style.addLayer(CircleLayer(MapLayerIds.SELECTED_HALO, MapLayerIds.ACTIVITIES_SOURCE).apply {
                withProperties(
                    PropertyFactory.circleColor(Color.parseColor("#E91E63")),
                    PropertyFactory.circleRadius(27f),
                    PropertyFactory.circleBlur(0.45f),
                    PropertyFactory.circleOpacity(0.2f)
                )
                withFilter(
                    org.maplibre.android.style.expressions.Expression.eq(
                        org.maplibre.android.style.expressions.Expression.get("is_selected"),
                        org.maplibre.android.style.expressions.Expression.literal(true)
                    )
                )
            })
            style.addLayer(SymbolLayer(MapLayerIds.ACTIVITIES_MARKERS, MapLayerIds.ACTIVITIES_SOURCE).apply {
                withProperties(
                    PropertyFactory.iconImage(org.maplibre.android.style.expressions.Expression.get("marker_image")),
                    PropertyFactory.iconAllowOverlap(true),
                    PropertyFactory.iconIgnorePlacement(true),
                    PropertyFactory.iconAnchor("bottom")
                )
            })

            style.addSource(GeoJsonSource(MapLayerIds.USER_SOURCE))
            style.addLayer(CircleLayer(MapLayerIds.USER_HALO, MapLayerIds.USER_SOURCE).apply {
                withProperties(
                    PropertyFactory.circleColor(Color.parseColor("#F44336")),
                    PropertyFactory.circleRadius(20f),
                    PropertyFactory.circleBlur(0.45f),
                    PropertyFactory.circleOpacity(0.2f)
                )
            })
            style.addLayer(CircleLayer(MapLayerIds.USER_POINT, MapLayerIds.USER_SOURCE).apply {
                withProperties(
                    PropertyFactory.circleColor(Color.parseColor("#F44336")),
                    PropertyFactory.circleRadius(8f),
                    PropertyFactory.circleStrokeColor(Color.WHITE),
                    PropertyFactory.circleStrokeWidth(3f)
                )
            })
        }

        map.addOnCameraIdleListener {
            val cam = map.cameraPosition
            val target = cam.target ?: return@addOnCameraIdleListener
            val zoom = cam.zoom
            val latDegrees = 360.0 / Math.pow(2.0, zoom) * 0.5
            val lngDegrees = latDegrees / Math.cos(Math.toRadians(target.latitude))
            onViewportIdle(
                MapViewport(
                    bounds = MapBounds(
                        south = target.latitude - latDegrees,
                        west = target.longitude - lngDegrees,
                        north = target.latitude + latDegrees,
                        east = target.longitude + lngDegrees
                    ),
                    center = MapCoordinate(target.latitude, target.longitude),
                    zoom = zoom
                )
            )
        }

        if (pickerMode) {
            map.addOnCameraMoveListener {
                map.cameraPosition.target?.let { target ->
                    onCameraMove(MapCoordinate(target.latitude, target.longitude))
                }
            }
        }

        map.addOnMapClickListener { latLng ->
            val screenPoint = map.projection?.toScreenLocation(latLng) ?: return@addOnMapClickListener true
            val features = map.queryRenderedFeatures(
                android.graphics.PointF(screenPoint.x.toFloat(), screenPoint.y.toFloat()),
                MapLayerIds.ACTIVITIES_MARKERS
            )
            if (features.isNotEmpty()) {
                val activityId = features.first().getStringProperty("activity_id")
                if (activityId != null) {
                    onActivityTap(activityId)
                }
            } else {
                if (pickerMode) map.animateCamera(CameraUpdateFactory.newLatLng(latLng))
                onMapTap(MapCoordinate(latLng.latitude, latLng.longitude))
            }
            true
        }
    }
}

private fun updateActivities(
    mapView: MapView,
    activities: List<MapActivityResponse>,
    userCoordinate: MapCoordinate?,
    selectedActivityId: String?
) {
    mapView.getMapAsync { map ->
        map.getStyle { style ->
            val source = style.getSource(MapLayerIds.ACTIVITIES_SOURCE) as? GeoJsonSource
            if (source != null) {
                val features = activities.map { activity ->
                    val isSelected = activity.id == selectedActivityId
                    val markerImage = if (isSelected) {
                        "gonow-pin-${activity.category}-sel"
                    } else {
                        "gonow-pin-${activity.category}"
                    }
                    Feature.fromGeometry(
                        Point.fromLngLat(activity.coordinate.longitude, activity.coordinate.latitude)
                    ).apply {
                        addStringProperty("activity_id", activity.id)
                        addStringProperty("category", activity.category)
                        addStringProperty("title", activity.title)
                        addNumberProperty("participant_count", activity.participantCount)
                        addBooleanProperty("is_full", activity.isFull)
                        addBooleanProperty("is_selected", isSelected)
                        addStringProperty("marker_image", markerImage)
                    }
                }
                source.setGeoJson(FeatureCollection.fromFeatures(features))
            }

            val userSource = style.getSource(MapLayerIds.USER_SOURCE) as? GeoJsonSource
            if (userSource != null && userCoordinate != null) {
                userSource.setGeoJson(
                    Feature.fromGeometry(
                        Point.fromLngLat(userCoordinate.longitude, userCoordinate.latitude)
                    )
                )
            }
        }
    }
}

private fun createPinDrawable(color: Int, size: Float): Drawable {
    val scale = size / 38f
    val width = (38 * scale).toInt()
    val height = (48 * scale).toInt()
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
    val path = Path().apply {
        moveTo(width / 2f, height - 2f)
        cubicTo(width * 0.44f, height * 0.76f, 2f, height * 0.61f, 2f, height * 0.38f)
        cubicTo(2f, height * 0.14f, width * 0.24f, 2f, width / 2f, 2f)
        cubicTo(width * 0.76f, 2f, width - 2f, height * 0.14f, width - 2f, height * 0.38f)
        cubicTo(width - 2f, height * 0.61f, width * 0.56f, height * 0.76f, width / 2f, height - 2f)
        close()
    }
    canvas.drawPath(path, paint)
    paint.style = Paint.Style.STROKE
    paint.strokeWidth = maxOf(2f, width * 0.06f)
    paint.color = Color.WHITE
    canvas.drawPath(path, paint)
    paint.style = Paint.Style.FILL
    paint.color = Color.WHITE
    canvas.drawCircle(width / 2f, height * 0.31f, width * 0.15f, paint)
    paint.color = color
    canvas.drawCircle(width / 2f, height * 0.31f, width * 0.06f, paint)
    return BitmapDrawable(null, bitmap)
}
