import type { Map } from 'maplibre-gl'

const BOOTSTRAP_STYLE = {
  version: 8 as const,
  name: 'GoNow bootstrap',
  sources: {},
  layers: [
    { id: 'background', type: 'background' as const, paint: { 'background-color': '#F6F5FA' } },
  ],
}

/**
 * Rewrite absolute backend URLs in a style JSON to relative paths
 * so they go through the Nuxt proxy instead of hitting port 8080 directly.
 */
function rewriteStyleUrls(style: Record<string, any>): Record<string, any> {
  const rewritten = JSON.parse(JSON.stringify(style))
  const backendPattern = /^https?:\/\/[^/]+(\/api\/)/

  function rewriteValue(val: any): any {
    if (typeof val === 'string' && backendPattern.test(val)) {
      return val.replace(backendPattern, '/api/')
    }
    return val
  }

  // Rewrite source tiles arrays
  if (rewritten.sources) {
    for (const source of Object.values(rewritten.sources) as any[]) {
      if (Array.isArray(source.tiles)) {
        source.tiles = source.tiles.map(rewriteValue)
      }
    }
  }

  // Rewrite sprite and glyphs
  if (rewritten.sprite) rewritten.sprite = rewriteValue(rewritten.sprite)
  if (rewritten.glyphs) rewritten.glyphs = rewriteValue(rewritten.glyphs)

  return rewritten
}

export function useMapStyle() {
  const config = useRuntimeConfig()
  const styleJson = ref<string | null>(null)
  const styleError = ref(false)
  const styleLoading = ref(true)

  async function load() {
    styleLoading.value = true
    styleError.value = false
    try {
      const request = crypto.randomUUID()
      const res = await fetch(`${config.public.backendBase}/map/style?t=${request}`, {
        cache: 'no-store',
        headers: { Accept: 'application/json' },
      })
      if (!res.ok) throw new Error(`Style ${res.status}`)
      const json = await res.json()
      if (json.version !== 8 || !json.sources || !json.layers) {
        throw new Error('Invalid style document')
      }
      // Rewrite absolute tile URLs to relative paths for proxy
      const fixed = rewriteStyleUrls(json)
      styleJson.value = JSON.stringify(fixed)
    } catch {
      styleError.value = true
    } finally {
      styleLoading.value = false
    }
  }

  function reload() {
    styleJson.value = null
    return load()
  }

  return {
    styleJson: readonly(styleJson),
    styleError: readonly(styleError),
    styleLoading: readonly(styleLoading),
    load,
    reload,
    bootstrapStyle: BOOTSTRAP_STYLE,
  }
}

export function useMapInstance() {
  const map = shallowRef<Map | null>(null)

  function setInstance(m: Map | null) {
    map.value = m
  }

  return {
    map: readonly(map),
    setInstance,
  }
}
