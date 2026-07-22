<template>
  <NuxtLayout name="auth">
    <div class="relative w-full max-w-[400px]">
      <BackgroundDecor />
      <UCard
        :ui="{
          root: 'bg-white/50 dark:bg-neutral-900/50 backdrop-blur-2xl border border-white/20 dark:border-white/5 shadow-[var(--glass-shadow-sm),var(--glass-shadow-md),var(--glass-shadow-lg)]',
        }"
      >
        <template v-if="sent">
          <h2 class="mb-4 text-center text-2xl font-semibold">Письмо отправлено</h2>
          <p class="mb-6 text-center text-sm text-neutral-500">
            Если аккаунт с таким email существует, вы получите письмо с кодом восстановления.
          </p>
            <UButton
              block
              size="lg"
              label="Ввести код"
              class="btn-primary-gradient"
              @click="navigateTo('/reset-password', { state: { email: email.trim() } })"
          />
          <div class="mt-4 text-center">
            <NuxtLink to="/login" class="text-sm text-primary-500 hover:underline">Назад ко входу</NuxtLink>
          </div>
        </template>

        <template v-else>
          <BrandIcon />
          <h2 class="mb-2 text-center text-2xl font-semibold">Восстановление пароля</h2>
          <p class="mb-4 text-center text-sm text-neutral-500">
            Введите email, привязанный к вашему аккаунту
          </p>

          <UAlert
            v-if="error"
            color="error"
            variant="subtle"
            :title="error"
            class="mb-4"
          />

          <UForm :state="{ email }" @submit="handleSubmit" class="flex flex-col gap-3">
            <UFormField label="Email" name="email">
              <UInput
                v-model="email"
                type="email"
                placeholder="user@example.com"
                autocomplete="email"
                size="lg"
                class="w-full"
              />
            </UFormField>

            <UButton
              type="submit"
              block
              size="lg"
              :loading="loading"
              label="Отправить код"
              class="btn-primary-gradient mt-1"
            />
          </UForm>

          <div class="mt-4 text-center">
            <NuxtLink to="/login" class="text-sm text-primary-500 hover:underline">Назад ко входу</NuxtLink>
          </div>
        </template>
      </UCard>
    </div>
  </NuxtLayout>
</template>

<script setup lang="ts">
import { ApiError } from '~/utils/api-error'

definePageMeta({ layout: false })

const auth = useAuth()
const email = ref('')
const loading = ref(false)
const error = ref('')
const sent = ref(false)

async function handleSubmit() {
  error.value = ''
  if (!email.value.trim()) {
    error.value = 'Введите email'
    return
  }
  loading.value = true
  try {
    await auth.forgotPassword(email.value.trim())
    sent.value = true
  } catch (err) {
    if (err instanceof ApiError) error.value = err.message
    else error.value = 'Произошла ошибка. Попробуйте снова.'
  } finally {
    loading.value = false
  }
}
</script>
