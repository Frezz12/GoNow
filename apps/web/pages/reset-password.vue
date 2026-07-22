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
        <h2 class="mb-2 text-center text-2xl font-semibold">Новый пароль</h2>
        <p class="mb-4 text-center text-sm text-neutral-500">
          Введите код из письма и новый пароль
        </p>

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

          <UFormField label="Код из письма" name="code" :error="fieldErrors.code">
            <UInput
              v-model="form.code"
              placeholder="123456"
              autocomplete="one-time-code"
              size="lg"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Новый пароль" name="password" :error="fieldErrors.password">
            <UInput
              v-model="form.password"
              type="password"
              placeholder="Минимум 8 символов"
              autocomplete="new-password"
              size="lg"
              class="w-full"
            />
          </UFormField>

          <UButton
            type="submit"
            block
            size="lg"
            :loading="loading"
            label="Сохранить пароль"
            class="btn-primary-gradient mt-1"
          />
        </UForm>
      </UCard>
    </div>
  </NuxtLayout>
</template>

<script setup lang="ts">
import { ApiError } from '~/utils/api-error'

definePageMeta({ layout: false })

const route = useRoute()
const auth = useAuth()

const stateEmail = computed(() => (route.state as { email?: string })?.email || '')
const loading = ref(false)
const error = ref('')
const fieldErrors = ref<Record<string, string>>({})

const form = reactive({
  email: stateEmail.value,
  code: '',
  password: '',
})

async function handleSubmit() {
  error.value = ''
  fieldErrors.value = {}

  const errs: Record<string, string> = {}
  if (!form.email.trim()) errs.email = 'Введите email'
  if (!form.code.trim() || form.code.trim().length !== 6) errs.code = 'Введите 6-значный код'
  if (!form.password) errs.password = 'Введите новый пароль'
  else if (form.password.length < 8) errs.password = 'Минимум 8 символов'

  if (Object.keys(errs).length > 0) {
    fieldErrors.value = errs
    return
  }

  loading.value = true
  try {
    await auth.resetPassword(form.email.trim(), form.code.trim(), form.password)
    navigateTo('/')
  } catch (err) {
    if (err instanceof ApiError) {
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
