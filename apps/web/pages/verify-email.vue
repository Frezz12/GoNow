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
        <h2 class="mb-2 text-center text-2xl font-semibold">Подтвердите email</h2>
        <p class="mb-4 text-center text-sm text-neutral-500">
          Мы отправили 6-значный код на <strong>{{ email || 'ваш email' }}</strong>
        </p>

        <UAlert
          v-if="error"
          color="error"
          variant="subtle"
          :title="error"
          class="mb-4"
        />

        <form @submit.prevent="handleSubmit">
          <div class="mb-4 flex justify-center gap-3">
            <input
              v-for="(_, i) in 6"
              :key="i"
              :ref="(el: any) => { if (el) inputRefs[i] = el }"
              type="text"
              inputmode="numeric"
              maxlength="1"
              :value="digits[i]"
              @input="(e: Event) => handleDigitInput(i, (e.target as HTMLInputElement).value)"
              @keydown="(e: KeyboardEvent) => handleKeyDown(i, e)"
              @paste="i === 0 ? handlePaste : undefined"
              class="h-14 w-12 rounded-lg border border-neutral-200 bg-white text-center text-xl font-semibold outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-neutral-700 dark:bg-neutral-900"
              required
            />
          </div>

          <UButton
            type="submit"
            block
            size="lg"
            :loading="loading"
            label="Подтвердить"
            class="btn-primary-gradient"
          />
        </form>

        <div class="mt-4 text-center">
          <NuxtLink to="/login" class="text-sm text-primary-500 hover:underline">
            Назад ко входу
          </NuxtLink>
        </div>
      </UCard>
    </div>
  </NuxtLayout>
</template>

<script setup lang="ts">
import { ApiError } from '~/utils/api-error'

definePageMeta({ layout: false })

const route = useRoute()
const auth = useAuth()

const email = computed(() => (route.state as { email?: string })?.email || '')
const digits = ref<string[]>(['', '', '', '', '', ''])
const loading = ref(false)
const error = ref('')
const inputRefs = ref<HTMLInputElement[]>([])

function handleDigitInput(index: number, value: string) {
  if (value.length > 1) value = value[value.length - 1]
  if (!/^\d?$/.test(value)) return
  const newDigits = [...digits.value]
  newDigits[index] = value
  digits.value = newDigits
  if (value && index < 5) inputRefs.value[index + 1]?.focus()
}

function handleKeyDown(index: number, e: KeyboardEvent) {
  if (e.key === 'Backspace' && !digits.value[index] && index > 0) {
    inputRefs.value[index - 1]?.focus()
  }
}

function handlePaste(e: ClipboardEvent) {
  const text = e.clipboardData?.getData('text') || ''
  const nums = text.replace(/\D/g, '').slice(0, 6).split('')
  const newDigits = ['', '', '', '', '', '']
  nums.forEach((d, i) => { newDigits[i] = d })
  digits.value = newDigits
  inputRefs.value[Math.min(nums.length, 5)]?.focus()
}

async function handleSubmit() {
  error.value = ''
  const code = digits.value.join('')
  if (code.length !== 6) {
    error.value = 'Введите полный код из письма'
    return
  }
  if (!email.value) {
    error.value = 'Email не указан. Вернитесь к регистрации.'
    return
  }

  loading.value = true
  try {
    await auth.verifyEmail(email.value, code)
    navigateTo('/')
  } catch (err) {
    if (err instanceof ApiError) error.value = err.message
    else error.value = 'Произошла ошибка. Попробуйте снова.'
  } finally {
    loading.value = false
  }
}
</script>
