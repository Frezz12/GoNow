import type { MapActivity, MapFilterState } from '~/utils/map-types'
import {
  getStoredTokens,
  saveTokens,
  clearSession,
} from '~/utils/auth-storage'

export function useMapActivities() {
  const config = useRuntimeConfig()
  const activities = ref<MapActivity[]>([])
  const loading = ref(false)
  const error = ref(false)
  const loadedBounds = ref<{
    south: number
    west: number
    north: number
    east: number
  } | null>(null)

  let debounceTimer: ReturnType<typeof setTimeout> | null = null
  let abortController: AbortController | null = null

  const visibleActivities = computed(() => activities.value)

  function authHeaders(): Record<string, string> {
    const { accessToken } = getStoredTokens()
    if (!accessToken) return {}
    return { Authorization: `Bearer ${accessToken}` }
  }

  async function refreshTokens(): Promise<boolean> {
    const { refreshToken } = getStoredTokens()
    if (!refreshToken) return false
    try {
      const res = await fetch(`${config.public.backendBase}/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken }),
      })
      if (!res.ok) return false
      const json = await res.json()
      saveTokens(
        json.data.tokens.accessToken,
        json.data.tokens.refreshToken,
        json.data.tokens.accessTokenExpiresAt,
      )
      return true
    } catch {
      return false
    }
  }

  async function doFetch(params: URLSearchParams, signal?: AbortSignal): Promise<Response> {
    return fetch(
      `${config.public.backendBase}/activities/map?${params}`,
      {
        headers: { ...authHeaders(), Accept: 'application/json' },
        signal,
      },
    )
  }

  async function fetchActivities(
    bounds: { south: number; west: number; north: number; east: number },
    zoom: number,
    filters: MapFilterState,
    force = false,
  ) {
    if (!force && loadedBounds.value && containsBounds(loadedBounds.value, bounds)) {
      return
    }

    if (!getStoredTokens().accessToken) {
      return
    }

    if (abortController) abortController.abort()
    abortController = new AbortController()

    loading.value = true
    error.value = false

    try {
      const params = new URLSearchParams({
        south: bounds.south.toFixed(6),
        west: bounds.west.toFixed(6),
        north: bounds.north.toFixed(6),
        east: bounds.east.toFixed(6),
        zoom: zoom.toFixed(1),
        limit: '500',
      })

      if (filters.categories.size > 0) {
        params.set('categories', [...filters.categories].sort().join(','))
      }
      if (filters.onlyAvailable) {
        params.set('onlyAvailable', 'true')
      }

      let res = await doFetch(params, abortController.signal)

      if (res.status === 401) {
        const refreshed = await refreshTokens()
        if (refreshed) {
          res = await doFetch(params, abortController.signal)
        } else {
          clearSession()
          navigateTo('/login')
          return
        }
      }

      if (!res.ok) throw new Error(`Activities ${res.status}`)
      const json = await res.json()

      activities.value = json.data.activities
      loadedBounds.value = expandedBounds(bounds, 0.5)
    } catch (err: unknown) {
      if (err instanceof DOMException && err.name === 'AbortError') return
      error.value = true
    } finally {
      loading.value = false
    }
  }

  function debouncedFetch(
    bounds: { south: number; west: number; north: number; east: number },
    zoom: number,
    filters: MapFilterState,
  ) {
    if (debounceTimer) clearTimeout(debounceTimer)
    debounceTimer = setTimeout(() => {
      fetchActivities(bounds, zoom, filters)
    }, 400)
  }

  function reset() {
    activities.value = []
    loadedBounds.value = null
    error.value = false
  }

  function containsBounds(
    outer: { south: number; west: number; north: number; east: number },
    inner: { south: number; west: number; north: number; east: number },
  ) {
    return (
      inner.south >= outer.south
      && inner.north <= outer.north
      && inner.west >= outer.west
      && inner.east <= outer.east
    )
  }

  function expandedBounds(
    b: { south: number; west: number; north: number; east: number },
    factor: number,
  ) {
    const latPad = (b.north - b.south) * factor
    const lngPad = (b.east - b.west) * factor
    return {
      south: b.south - latPad,
      west: b.west - lngPad,
      north: b.north + latPad,
      east: b.east + lngPad,
    }
  }

  return {
    activities: readonly(activities),
    visibleActivities,
    loading: readonly(loading),
    error: readonly(error),
    fetchActivities,
    debouncedFetch,
    reset,
  }
}
