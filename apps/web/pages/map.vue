<script setup lang="ts">
import type { Map as MapLibreMap } from 'maplibre-gl'
import type { MapActivity, MapFilterState, ActivityCategory } from '~/utils/map-types'

definePageMeta({ layout: 'default' })

const { styleJson, styleError, styleLoading, bootstrapStyle, load: loadStyle, reload: reloadStyle } = useMapStyle()
const { activities, loading: activitiesLoading, error: activitiesError, debouncedFetch, reset: resetActivities } = useMapActivities()

const selectedActivity = ref<MapActivity | null>(null)
const showFilters = ref(false)
const userLocation = ref<{ latitude: number; longitude: number } | null>(null)
const locationLoading = ref(false)
const mapRef = ref<InstanceType<any> | null>(null)

const filters = reactive<MapFilterState>({
  categories: new Set<ActivityCategory>(),
  onlyAvailable: false,
})

const activeFilterCount = computed(() => {
  let count = filters.categories.size
  if (filters.onlyAvailable) count++
  return count
})

let mapInstance: MapLibreMap | null = null

function onMapReady(map: MapLibreMap) {
  mapInstance = map
  if (styleJson.value) {
    applyStyle(styleJson.value)
  } else {
    loadStyle()
  }
  requestLocation()
}

function onMapIdle(bounds: { south: number; west: number; north: number; east: number }, zoom: number) {
  debouncedFetch(bounds, zoom, filters)
}

function applyStyle(json: string) {
  if (!mapInstance) return
  try {
    const parsed = JSON.parse(json)
    mapInstance.setStyle(parsed)
    mapInstance.once('style.load', () => {
      // Layers will be re-added by MapView's watcher
    })
  } catch { /* ignore */ }
}

function onSelectActivity(id: string) {
  const found = activities.value.find((a) => a.id === id) || null
  selectedActivity.value = found
  if (found && mapInstance) {
    mapInstance.flyTo({
      center: [found.coordinate.longitude, found.coordinate.latitude],
      zoom: Math.max(mapInstance.getZoom(), 14),
      duration: 600,
    })
  }
}

function centerOnUser() {
  if (userLocation.value && mapInstance) {
    mapInstance.flyTo({
      center: [userLocation.value.longitude, userLocation.value.latitude],
      zoom: 12.2,
      duration: 600,
    })
  } else {
    requestLocation()
  }
}

function requestLocation() {
  if (!navigator.geolocation) return
  locationLoading.value = true
  navigator.geolocation.getCurrentPosition(
    (pos) => {
      userLocation.value = { latitude: pos.coords.latitude, longitude: pos.coords.longitude }
      if (!mapInstance) return
      const currentZoom = mapInstance.getZoom()
      if (currentZoom < 11) {
        mapInstance.flyTo({
          center: [pos.coords.longitude, pos.coords.latitude],
          zoom: 12.2,
          duration: 800,
        })
      }
    },
    () => { /* denied */ },
    { enableHighAccuracy: false, timeout: 10000 },
  )
  setTimeout(() => { locationLoading.value = false }, 10000)
}

function onApplyFilters(newFilters: MapFilterState) {
  filters.categories = newFilters.categories
  filters.onlyAvailable = newFilters.onlyAvailable
  resetActivities()
  if (mapInstance) {
    const bounds = mapInstance.getBounds()
    const zoom = mapInstance.getZoom()
    debouncedFetch(
      { south: bounds.getSouth(), west: bounds.getWest(), north: bounds.getNorth(), east: bounds.getEast() },
      zoom,
      filters,
    )
  }
}

function onRetryStyle() {
  reloadStyle()
}

watch(styleError, (err) => {
  if (err) reloadStyle()
})
</script>

<template>
  <div class="relative h-screen w-full overflow-hidden bg-[#F6F5FA]">
    <MapView
      ref="mapRef"
      :style-json="styleJson"
      :bootstrap-style="bootstrapStyle"
      :activities="activities"
      :selected-id="selectedActivity?.id || null"
      :user-location="userLocation"
      @map-ready="onMapReady"
      @map-idle="onMapIdle"
      @select-activity="onSelectActivity"
    />

    <!-- Attribution -->
    <div
      class="absolute bottom-3 left-3 z-10 rounded-full px-3 py-1 text-[10px] backdrop-blur-md border select-none"
      :style="{
        background: 'var(--glass-bg)',
        borderColor: 'var(--glass-border)',
      }"
    >
      © OpenStreetMap contributors · OpenFreeMap
    </div>

    <!-- Top controls -->
    <div class="absolute top-3 right-14 z-10 flex flex-col gap-2">
      <button
        class="flex h-10 w-10 items-center justify-center rounded-full backdrop-blur-md border transition-all"
        :style="{
          background: 'var(--glass-bg)',
          borderColor: 'var(--glass-border)',
          boxShadow: 'var(--glass-shadow-sm)',
        }"
        @click="showFilters = !showFilters"
      >
        <span class="i-lucide-sliders-horizontal h-4 w-4" />
        <span
          v-if="activeFilterCount > 0"
          class="absolute -top-1 -right-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-[#7C5CFC] px-1 text-[9px] font-bold text-white"
        >
          {{ activeFilterCount }}
        </span>
      </button>
    </div>

    <!-- User location button -->
    <div class="absolute bottom-32 right-3 z-10">
      <button
        class="flex h-12 w-12 items-center justify-center rounded-full backdrop-blur-md border transition-all active:scale-95"
        :style="{
          background: 'var(--glass-bg)',
          borderColor: 'var(--glass-border)',
          boxShadow: 'var(--glass-shadow-sm)',
        }"
        @click="centerOnUser"
      >
        <span v-if="locationLoading" class="i-lucide-loader-2 h-5 w-5 animate-spin text-[#239DCC]" />
        <span v-else class="i-lucide-crosshair h-5 w-5 text-[#239DCC]" />
      </button>
    </div>

    <!-- Style loading overlay -->
    <div
      v-if="styleLoading && !styleJson"
      class="absolute inset-0 z-30 flex items-center justify-center bg-[#F6F5FA]"
    >
      <div class="flex flex-col items-center gap-3">
        <span class="i-lucide-loader-2 h-8 w-8 animate-spin text-[#7C5CFC]" />
        <span class="text-sm text-neutral-500">Загрузка карты…</span>
      </div>
    </div>

    <!-- Style error overlay -->
    <div
      v-if="styleError && !styleJson"
      class="absolute inset-0 z-30 flex items-center justify-center bg-[#F6F5FA]"
    >
      <div
        class="flex flex-col items-center gap-3 rounded-2xl px-8 py-6 backdrop-blur-2xl border"
        :style="{
          background: 'var(--glass-bg)',
          borderColor: 'var(--glass-border)',
          boxShadow: 'var(--glass-shadow-md)',
        }"
      >
        <span class="i-lucide-map-off h-8 w-8 text-neutral-400" />
        <p class="text-sm text-neutral-500">Не удалось загрузить стиль карты</p>
        <button class="btn-primary-gradient rounded-xl px-5 py-2 text-sm" @click="onRetryStyle">
          Повторить
        </button>
      </div>
    </div>

    <!-- Activity loading indicator -->
    <div
      v-if="activitiesLoading && activities.length === 0"
      class="absolute top-3 left-1/2 z-10 -translate-x-1/2"
    >
      <div
        class="flex items-center gap-2 rounded-full px-3 py-1.5 text-xs backdrop-blur-md border"
        :style="{
          background: 'var(--glass-bg)',
          borderColor: 'var(--glass-border)',
          boxShadow: 'var(--glass-shadow-sm)',
        }"
      >
        <span class="i-lucide-loader-2 h-3 w-3 animate-spin" />
        <span class="text-neutral-500">Загрузка…</span>
      </div>
    </div>

    <!-- Activity error pill -->
    <div
      v-if="activitiesError && activities.length === 0"
      class="absolute top-3 left-1/2 z-10 -translate-x-1/2"
    >
      <div
        class="flex items-center gap-2 rounded-full px-3 py-1.5 text-xs backdrop-blur-md border"
        :style="{
          background: 'var(--glass-bg)',
          borderColor: 'var(--glass-border)',
          boxShadow: 'var(--glass-shadow-sm)',
        }"
      >
        <span class="text-neutral-500">Ошибка загрузки активностей</span>
      </div>
    </div>

    <!-- Selected activity card -->
    <ActivityMapCard
      v-if="selectedActivity"
      :activity="selectedActivity"
      @close="selectedActivity = null"
    />

    <!-- Filter sheet -->
    <MapFilterSheet
      v-if="showFilters"
      :filters="{ categories: filters.categories, onlyAvailable: filters.onlyAvailable }"
      @apply="onApplyFilters"
      @close="showFilters = false"
    />
  </div>
</template>
