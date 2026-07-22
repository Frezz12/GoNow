<template>
  <UApp>
    <NuxtLayout>
      <NuxtPage />
    </NuxtLayout>
  </UApp>
</template>

<script setup lang="ts">
const auth = useAuth()

onMounted(() => {
  auth.init()
})
</script>
