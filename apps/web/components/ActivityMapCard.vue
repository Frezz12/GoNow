<script setup lang="ts">
import type { MapActivity } from '~/utils/map-types'
import { CATEGORY_LABELS, CATEGORY_COLORS } from '~/utils/map-types'

const props = defineProps<{
  activity: MapActivity
}>()

const emit = defineEmits<{
  close: []
}>()

function formatDate(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleDateString('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
}

const isFull = computed(() =>
  props.activity.participantLimit !== null
    && props.activity.participantCount >= props.activity.participantLimit,
)
</script>

<template>
  <div
    class="absolute bottom-20 left-4 right-4 z-20 mx-auto max-w-[380px] rounded-2xl p-4 backdrop-blur-2xl border"
    :style="{
      background: 'var(--glass-bg)',
      borderColor: 'var(--glass-border)',
      boxShadow: 'var(--glass-shadow-md), var(--glass-shadow-lg)',
    }"
  >
    <button
      class="absolute top-3 right-3 flex h-7 w-7 items-center justify-center rounded-full bg-black/5 hover:bg-black/10 transition-colors"
      @click="emit('close')"
    >
      <span class="text-sm leading-none">&times;</span>
    </button>

    <div class="flex items-start gap-3">
      <div
        class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-white text-lg"
        :style="{ backgroundColor: CATEGORY_COLORS[activity.category] }"
      >
        {{ CATEGORY_LABELS[activity.category]?.[0] || '?' }}
      </div>

      <div class="min-w-0 flex-1">
        <h3 class="truncate text-[15px] font-semibold">{{ activity.title }}</h3>
        <p class="mt-0.5 text-xs text-neutral-500">
          {{ CATEGORY_LABELS[activity.category] || activity.category }}
        </p>
      </div>
    </div>

    <div class="mt-3 flex items-center gap-4 text-xs text-neutral-500">
      <span class="flex items-center gap-1">
        <span class="i-lucide-calendar h-3.5 w-3.5" />
        {{ formatDate(activity.startsAt) }}
      </span>
      <span class="flex items-center gap-1">
        <span class="i-lucide-users h-3.5 w-3.5" />
        {{ activity.participantCount }}{{ activity.participantLimit ? ` / ${activity.participantLimit}` : '' }}
      </span>
    </div>

    <div v-if="isFull" class="mt-2 text-xs font-medium text-amber-600">Мест нет</div>
  </div>
</template>
