<script setup lang="ts">
import type { Map as MapLibreMap, GeoJSONSource } from 'maplibre-gl'
import { CATEGORY_COLORS } from '~/utils/map-types'
import type { MapActivity } from '~/utils/map-types'

const props = defineProps<{
  styleJson: string | null
  bootstrapStyle: object
  activities: MapActivity[]
  selectedId: string | null
  userLocation: { latitude: number; longitude: number } | null
}>()

const emit = defineEmits<{
  mapReady: [map: MapLibreMap]
  mapIdle: [bounds: { south: number; west: number; north: number; east: number }, zoom: number]
  selectActivity: [id: string]
}>()

const container = shallowRef<HTMLDivElement | null>(null)
let mapInstance: MapLibreMap | null = null
let styleLoaded = false

const SOURCE_ID = 'gonow-activities'
const MARKERS_LAYER = 'gonow-activity-markers'
const HALO_LAYER = 'gonow-selected-activity-halo'
const USER_SOURCE = 'gonow-user-location'
const USER_POINT_LAYER = 'gonow-user-location-point'

function loadMapLibreGl() {
  return import('maplibre-gl')
}

function rewriteTileUrl(url: string): { url: string } {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    try {
      const parsed = new URL(url)
      if (parsed.pathname.startsWith('/api/')) {
        return { url: parsed.pathname + parsed.search }
      }
    } catch { /* ignore */ }
  }
  return { url }
}

async function initMap() {
  if (!container.value) return
  const maplibregl = await loadMapLibreGl()

  const map = new maplibregl.Map({
    container: container.value,
    style: props.bootstrapStyle as any,
    center: [37.6173, 55.7558],
    zoom: 10,
    attributionControl: false,
    maxZoom: 22,
    transformRequest: rewriteTileUrl,
  })

  map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right')

  map.on('load', () => {
    mapInstance = map
    styleLoaded = false
    addLayers(map)
    emit('mapReady', map)
  })

  map.on('idle', () => {
    if (!mapInstance) return
    const center = map.getCenter()
    const zoom = map.getZoom()
    const bounds = map.getBounds()
    emit('mapIdle', {
      south: bounds.getSouth(),
      west: bounds.getWest(),
      north: bounds.getNorth(),
      east: bounds.getEast(),
    }, zoom)
  })

  map.on('click', MARKERS_LAYER, (e) => {
    const feature = e.features?.[0]
    if (feature?.properties?.activity_id) {
      emit('selectActivity', feature.properties.activity_id as string)
    }
  })

  map.on('mouseenter', MARKERS_LAYER, () => {
    map.getCanvas().style.cursor = 'pointer'
  })
  map.on('mouseleave', MARKERS_LAYER, () => {
    map.getCanvas().style.cursor = ''
  })
}

function addLayers(map: MapLibreMap) {
  if (map.getSource(SOURCE_ID)) return

  map.addSource(SOURCE_ID, {
    type: 'geojson',
    data: { type: 'FeatureCollection', features: [] },
    cluster: true,
    clusterMaxZoom: 14,
    clusterRadius: 58,
  })

  map.addLayer({
    id: 'gonow-cluster-halo',
    type: 'circle',
    source: SOURCE_ID,
    filter: ['has', 'point_count'],
    paint: {
      'circle-color': 'rgba(124, 92, 252, 0.15)',
      'circle-radius': 27,
      'circle-blur': 0.45,
    },
  })

  map.addLayer({
    id: 'gonow-clusters',
    type: 'circle',
    source: SOURCE_ID,
    filter: ['has', 'point_count'],
    paint: {
      'circle-color': [
        'step',
        ['get', 'point_count'],
        '#7C5CFC',
        10,
        '#B05CF5',
        50,
        '#F472B6',
      ],
      'circle-radius': [
        'step',
        ['get', 'point_count'],
        18,
        10,
        24,
        50,
        32,
      ],
    },
  })

  map.addLayer({
    id: 'gonow-cluster-count',
    type: 'symbol',
    source: SOURCE_ID,
    filter: ['has', 'point_count'],
    layout: {
      'text-field': '{point_count_abbreviated}',
      'text-font': ['Noto Sans Bold'],
      'text-size': 12,
    },
    paint: {
      'text-color': '#FFFFFF',
    },
  })

  map.addLayer({
    id: HALO_LAYER,
    type: 'circle',
    source: SOURCE_ID,
    filter: ['==', ['get', 'activity_id'], ''],
    paint: {
      'circle-color': 'rgba(236, 72, 153, 0.20)',
      'circle-radius': 27,
      'circle-blur': 0.45,
    },
  })

  map.addLayer({
    id: MARKERS_LAYER,
    type: 'symbol',
    source: SOURCE_ID,
    filter: ['!', ['has', 'point_count']],
    layout: {
      'icon-image': ['get', 'marker_image'],
      'icon-allow-overlap': true,
      'icon-anchor': 'bottom',
      'icon-offset': [0, 4],
    },
  })

  map.addSource(USER_SOURCE, {
    type: 'geojson',
    data: { type: 'Point', coordinates: [0, 0] },
  })

  map.addLayer({
    id: 'gonow-user-location-halo',
    type: 'circle',
    source: USER_SOURCE,
    paint: {
      'circle-color': 'rgba(239, 68, 68, 0.20)',
      'circle-radius': 20,
      'circle-blur': 0.45,
    },
  })

  map.addLayer({
    id: USER_POINT_LAYER,
    type: 'circle',
    source: USER_SOURCE,
    paint: {
      'circle-color': '#EF4444',
      'circle-radius': 8,
      'circle-stroke-color': '#FFFFFF',
      'circle-stroke-width': 3,
    },
  })
}

function updateSources() {
  if (!mapInstance || !styleLoaded) return

  const features = props.activities.map((a) => ({
    type: 'Feature' as const,
    geometry: {
      type: 'Point' as const,
      coordinates: [a.coordinate.longitude, a.coordinate.latitude] as [number, number],
    },
    properties: {
      activity_id: a.id,
      category: a.category,
      title: a.title,
      participants_count: a.participantCount,
      participants_limit: a.participantLimit,
      is_full: a.participantLimit !== null && a.participantCount >= a.participantLimit,
      is_selected: a.id === props.selectedId,
      marker_image: `marker-${a.category}`,
    },
  }))

  const source = mapInstance.getSource(SOURCE_ID) as GeoJSONSource | undefined
  if (source) {
    source.setData({ type: 'FeatureCollection', features } as any)
  }

  if (mapInstance.getLayer(HALO_LAYER)) {
    mapInstance.setFilter(HALO_LAYER, ['==', ['get', 'activity_id'], props.selectedId || ''])
  }
}

function updateUserLocation() {
  if (!mapInstance || !props.userLocation) return
  const source = mapInstance.getSource(USER_SOURCE) as GeoJSONSource | undefined
  if (source) {
    source.setData({
      type: 'Point',
      coordinates: [props.userLocation.longitude, props.userLocation.latitude],
    } as any)
  }
}

function registerMarkerImages() {
  if (!mapInstance) return

  const categories = [
    'walking', 'sport', 'travel', 'music', 'games',
    'food', 'help', 'education', 'animals', 'event', 'other',
  ] as ActivityCategory[]

  for (const cat of categories) {
    const color = CATEGORY_COLORS[cat]
    const size = 38
    const canvas = document.createElement('canvas')
    canvas.width = size
    canvas.height = size * 1.5
    const ctx = canvas.getContext('2d')!
    drawTeardrop(ctx, size, size * 1.5, color)

    if (mapInstance.hasImage(`marker-${cat}`)) {
      mapInstance.removeImage(`marker-${cat}`)
    }
    mapInstance.addImage(`marker-${cat}`, canvas, { pixelRatio: 2 })
  }
}

function drawTeardrop(ctx: CanvasRenderingContext2D, w: number, h: number, color: string) {
  const cx = w / 2
  const tipY = h - 4
  const radius = w * 0.38

  ctx.beginPath()
  ctx.moveTo(cx, tipY)
  ctx.bezierCurveTo(cx - radius * 0.2, tipY - radius * 1.8, cx - radius, tipY - radius * 2.6, cx - radius, tipY - radius * 2.8)
  ctx.arc(cx, tipY - radius * 2.8, radius, Math.PI, 0, false)
  ctx.bezierCurveTo(cx + radius, tipY - radius * 2.6, cx + radius * 0.2, tipY - radius * 1.8, cx, tipY)
  ctx.closePath()

  ctx.fillStyle = color
  ctx.fill()

  ctx.beginPath()
  ctx.arc(cx, tipY - radius * 2.8, radius * 0.35, 0, Math.PI * 2)
  ctx.fillStyle = '#FFFFFF'
  ctx.fill()
}

function flyTo(lng: number, lat: number, zoom: number) {
  mapInstance?.flyTo({ center: [lng, lat], zoom, duration: 800 })
}

watch(
  () => props.styleJson,
  (json) => {
    if (!json || !mapInstance) return
    try {
      const parsed = JSON.parse(json)
      mapInstance.setStyle(parsed)
      styleLoaded = true
      mapInstance.on('style.load', () => {
        registerMarkerImages()
        addLayers(mapInstance!)
        updateSources()
      })
    } catch { /* ignore */ }
  },
)

watch(() => props.activities, updateSources, { deep: true })
watch(() => props.selectedId, updateSources)
watch(() => props.userLocation, updateUserLocation, { immediate: true })

onMounted(initMap)

onBeforeUnmount(() => {
  mapInstance?.remove()
  mapInstance = null
})

defineExpose({ flyTo, getMap: () => mapInstance })
</script>

<template>
  <div ref="container" class="absolute inset-0" />
</template>
