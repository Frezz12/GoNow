<script setup lang="ts">
import { CATEGORIES } from '~/utils/map-types'
import type { MapFilterState, ActivityCategory } from '~/utils/map-types'

const props = defineProps<{
  filters: MapFilterState
}>()

const emit = defineEmits<{
  apply: [filters: MapFilterState]
  close: []
}>()

const selectedCategories = ref<Set<ActivityCategory>>(new Set(props.filters.categories))
const onlyAvailable = ref(props.filters.onlyAvailable)

function toggleCategory(cat: ActivityCategory) {
  const s = new Set(selectedCategories.value)
  if (s.has(cat)) s.delete(cat)
  else s.add(cat)
  selectedCategories.value = s
}

function apply() {
  emit('apply', {
    categories: new Set(selectedCategories.value),
    onlyAvailable: onlyAvailable.value,
  })
  emit('close')
}

function clearAll() {
  selectedCategories.value = new Set()
  onlyAvailable.value = false
}
</script>

<template>
  <div
    class="absolute bottom-0 left-0 right-0 z-30 rounded-t-2xl p-5 pb-8 backdrop-blur-2xl border-t"
    :style="{
      background: 'var(--glass-bg)',
      borderColor: 'var(--glass-border)',
      boxShadow: 'var(--glass-shadow-lg)',
    }"
  >
    <div class="mx-auto mb-4 h-1 w-10 rounded-full bg-neutral-300" />

    <div class="flex items-center justify-between mb-4">
      <h3 class="text-[15px] font-semibold">Фильтры</h3>
      <button class="text-xs text-neutral-500 hover:text-neutral-700 transition-colors" @click="clearAll">
        Сбросить
      </button>
    </div>

    <div class="mb-4">
      <p class="mb-2 text-xs font-medium text-neutral-500">Категории</p>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="cat in CATEGORIES"
          :key="cat.value"
          class="flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition-all"
          :class="selectedCategories.has(cat.value)
            ? 'border-transparent text-white'
            : 'border-neutral-200 dark:border-neutral-700 bg-white/50 dark:bg-neutral-800/50'"
          :style="selectedCategories.has(cat.value) ? { backgroundColor: '#7C5CFC' } : {}"
          @click="toggleCategory(cat.value)"
        >
          <span>{{ cat.emoji }}</span>
          <span>{{ cat.label }}</span>
        </button>
      </div>
    </div>

    <div class="flex items-center gap-2 mb-4">
      <UToggle v-model="onlyAvailable" />
      <span class="text-sm">Только с местами</span>
    </div>

    <button
      class="btn-primary-gradient w-full rounded-xl"
      @click="apply"
    >
      Применить
    </button>
  </div>
</template>
