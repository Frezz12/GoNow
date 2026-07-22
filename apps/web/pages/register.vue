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
        <h2 class="mb-4 text-center text-2xl font-semibold">Регистрация</h2>

        <UAlert
          v-if="error"
          color="error"
          variant="subtle"
          :title="error"
          class="mb-4"
        />

        <UForm :state="form" @submit="handleSubmit" class="flex flex-col gap-3">
          <UFormField label="Имя" name="displayName" :error="fieldErrors.displayName">
            <UInput
              v-model="form.displayName"
              placeholder="Ваше имя"
              autocomplete="name"
              size="lg"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Юзернейм" name="username" :error="fieldErrors.username">
            <UInput
              v-model="form.username"
              placeholder="nikolay_26"
              autocomplete="username"
              size="lg"
              class="w-full"
            />
          </UFormField>

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

          <div class="flex gap-3">
            <UFormField label="Пароль" name="password" :error="fieldErrors.password" class="flex-1">
              <UInput
                v-model="form.password"
                :type="showPassword ? 'text' : 'password'"
                placeholder="от 8 символов"
                autocomplete="new-password"
                size="lg"
                class="w-full"
              />
            </UFormField>
            <UFormField label="Ещё раз" name="confirmPassword" :error="fieldErrors.confirmPassword" class="flex-1">
              <UInput
                v-model="form.confirmPassword"
                :type="showPassword ? 'text' : 'password'"
                placeholder="подтвердите"
                autocomplete="new-password"
                size="lg"
                class="w-full"
              />
            </UFormField>
          </div>

          <label class="flex items-center gap-2 cursor-pointer">
            <UCheckbox v-model="showPassword" />
            <span class="text-xs text-neutral-500 select-none">показать пароли</span>
          </label>

          <UButton
            type="submit"
            block
            size="lg"
            :loading="loading"
            label="Создать аккаунт"
            class="btn-primary-gradient mt-1"
          />
        </UForm>

        <div class="mt-5 text-center">
          <p class="text-sm text-neutral-500">
            Уже есть аккаунт?
            <NuxtLink to="/login" class="text-primary-500 hover:underline">Войти</NuxtLink>
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
const showPassword = ref(false)

const form = reactive({
  displayName: '',
  username: '',
  email: '',
  password: '',
  confirmPassword: '',
})

async function handleSubmit() {
  error.value = ''
  fieldErrors.value = {}

  const errs: Record<string, string> = {}
  if (!form.displayName.trim()) errs.displayName = 'Введите имя'
  else if (form.displayName.trim().length < 2) errs.displayName = 'Минимум 2 символа'
  if (!form.username.trim()) errs.username = 'Введите юзернейм'
  else if (form.username.trim().length < 5) errs.username = 'Минимум 5 символов'
  else if (!/^[a-z][a-z0-9_]*$/.test(form.username.trim())) errs.username = 'Только латиница, цифры и _'
  if (!form.email.trim()) errs.email = 'Введите email'
  if (!form.password) errs.password = 'Введите пароль'
  else if (form.password.length < 8) errs.password = 'Минимум 8 символов'
  if (!form.confirmPassword) errs.confirmPassword = 'Подтвердите пароль'
  else if (form.password !== form.confirmPassword) errs.confirmPassword = 'Пароли не совпадают'

  if (Object.keys(errs).length > 0) {
    fieldErrors.value = errs
    return
  }

  loading.value = true
  try {
    const res = await auth.register(
      form.email.trim(),
      form.password,
      form.displayName.trim(),
      form.username.trim(),
    )
    navigateTo('/verify-email', { state: { email: res.email } })
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
