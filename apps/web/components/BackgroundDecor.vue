<template>
  <div class="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
    <div
      class="absolute -right-[20%] -top-[30%] h-[60%] w-[50%] rounded-full blur-[120px] transition-opacity duration-700"
      :style="{
        background: 'radial-gradient(circle, #7C5CFC 0%, #B05CF5 50%, transparent 70%)',
        opacity: isDark ? 0.08 : 0.15,
      }"
    />
    <div
      class="absolute -bottom-[25%] -left-[15%] h-[55%] w-[45%] rounded-full blur-[100px] transition-opacity duration-700"
      :style="{
        background: 'radial-gradient(circle, #F472B6 0%, #E85CA8 40%, transparent 70%)',
        opacity: isDark ? 0.06 : 0.12,
      }"
    />
    <div
      class="absolute -left-[10%] top-[20%] h-[35%] w-[30%] rounded-full blur-[80px] transition-opacity duration-700"
      :style="{
        background: 'radial-gradient(circle, #239DCC 0%, transparent 70%)',
        opacity: isDark ? 0.04 : 0.08,
      }"
    />
  </div>
</template>

<script setup lang="ts">
const colorMode = useColorMode()
const isDark = computed(() => colorMode.value === 'dark')
</script>
