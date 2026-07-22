<template>
  <NuxtLayout name="auth">
    <div class="relative w-full max-w-[400px]">
      <BackgroundDecor />
      <UCard
        :ui="{
          root: 'bg-white/50 dark:bg-neutral-900/50 backdrop-blur-2xl border border-white/20 dark:border-white/5 shadow-[var(--glass-shadow-sm),var(--glass-shadow-md),var(--glass-shadow-lg)]',
        }"
      >
        <BrandIcon />
        <h2 class="mb-4 text-center text-2xl font-semibold">Вход</h2>

        <UAlert
          v-if="error"
          color="error"
          variant="subtle"
          :title="error"
          class="mb-4"
        />

        <UForm :state="form" @submit="handleSubmit" class="flex flex-col gap-3">
          <UFormField label="Email" name="email" :error="fieldErrors.email">
            <UInput
              v-model="form.email"
              type="email"
              placeholder="user@example.com"
              autocomplete="email"
              size="lg"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Пароль" name="password" :error="fieldErrors.password">
            <UInput
              v-model="form.password"
              type="password"
              placeholder="••••••••"
              autocomplete="current-password"
              size="lg"
              class="w-full"
            />
          </UFormField>

          <UButton
            type="submit"
            block
            size="lg"
            :loading="loading"
            label="Войти"
            class="btn-primary-gradient mt-1"
          />
        </UForm>

        <div class="mt-5 flex flex-col items-center gap-2">
          <NuxtLink to="/forgot-password" class="text-sm text-primary-500 hover:underline">
            Забыли пароль?
          </NuxtLink>
          <p class="text-sm text-neutral-500">
            Если у вас нет аккаунта,
            <NuxtLink to="/register" class="text-primary-500 hover:underline">создайте</NuxtLink>
          </p>
        </div>
      </UCard>
    </div>
  </NuxtLayout>
</template>

<script setup lang="ts">
import { ApiError } from '~/utils/api-error'

definePageMeta({ layout: false })

const auth = useAuth()
const loading = ref(false)
const error = ref('')
const fieldErrors = ref<Record<string, string>>({})

const form = reactive({
  email: '',
  password: '',
})

async function handleSubmit() {
  error.value = ''
  fieldErrors.value = {}

  if (!form.email.trim()) {
    fieldErrors.value = { email: 'Введите email' }
    return
  }
  if (!form.password) {
    fieldErrors.value = { password: 'Введите пароль' }
    return
  }

  loading.value = true
  try {
    await auth.login(form.email.trim(), form.password)
    navigateTo('/')
  } catch (err) {
    if (err instanceof ApiError) {
      if (err.code === 'EMAIL_NOT_VERIFIED') {
        navigateTo('/verify-email', { state: { email: form.email.trim() } })
        return
      }
      if (err.fields) fieldErrors.value = err.fields
      error.value = err.message
    } else {
      error.value = 'Произошла ошибка. Попробуйте снова.'
    }
  } finally {
    loading.value = false
  }
}
</script>
