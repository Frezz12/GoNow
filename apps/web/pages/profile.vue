<template>
  <div class="flex min-h-screen items-center justify-center px-4">
    <div class="w-full max-w-[500px]">
      <UCard
        :ui="{
          root: 'bg-white/50 dark:bg-neutral-900/50 backdrop-blur-2xl border border-white/20 dark:border-white/5 shadow-[var(--glass-shadow-sm),var(--glass-shadow-md),var(--glass-shadow-lg)]',
        }"
      >
        <div class="flex items-center justify-between mb-6">
          <NuxtLink to="/map" class="flex items-center gap-2 text-neutral-500 hover:text-primary-500 transition-colors">
            <UIcon name="i-lucide-arrow-left" class="w-5 h-5" />
            <span class="text-sm">Назад</span>
          </NuxtLink>
          <h2 class="text-xl font-semibold">Профиль</h2>
          <div class="w-16" />
        </div>

        <UAlert
          v-if="error"
          color="error"
          variant="subtle"
          :title="error"
          class="mb-4"
        />

        <UAlert
          v-if="saved"
          color="success"
          variant="subtle"
          title="Профиль сохранён"
          class="mb-4"
        />

        <UForm :state="form" @submit="handleSave" class="flex flex-col gap-3">
          <div class="flex items-center gap-4 mb-2">
            <div class="flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-br from-[#7C5CFC] via-[#B05CF5] to-[#F472B6] text-2xl font-bold text-white">
              {{ (form.displayName || '?')[0].toUpperCase() }}
            </div>
            <div>
              <p class="font-semibold">{{ form.displayName }}</p>
              <p class="text-xs text-neutral-500">{{ form.email }}</p>
            </div>
          </div>

          <UFormField label="Имя" name="displayName" :error="fieldErrors.displayName">
            <UInput v-model="form.displayName" placeholder="Ваше имя" size="lg" class="w-full" />
          </UFormField>

          <UFormField label="О себе" name="bio">
            <UTextarea v-model="form.bio" placeholder="Расскажите о себе..." :rows="3" size="lg" class="w-full" />
          </UFormField>

          <div class="flex gap-3">
            <UFormField label="Город" name="city" class="flex-1">
              <UInput v-model="form.city" placeholder="Москва" size="lg" class="w-full" />
            </UFormField>
            <UFormField label="Профессия" name="occupation" class="flex-1">
              <UInput v-model="form.occupation" placeholder="Дизайнер" size="lg" class="w-full" />
            </UFormField>
          </div>

          <div class="flex gap-3">
            <UFormField label="Дата рождения" name="birthDate" class="flex-1">
              <UInput v-model="form.birthDate" type="date" size="lg" class="w-full" />
            </UFormField>
            <UFormField label="Статус" name="relationshipStatus" class="flex-1">
              <USelect
                v-model="form.relationshipStatus"
                :items="statusOptions"
                placeholder="Не выбран"
                size="lg"
                class="w-full"
              />
            </UFormField>
          </div>

          <UFormField label="Интересы (через запятую)" name="interests">
            <UInput v-model="interestsStr" placeholder="спорт, музыка, путешествия" size="lg" class="w-full" />
          </UFormField>

          <div class="flex items-center gap-2 mt-1">
            <UCheckbox v-model="form.showDistance" />
            <span class="text-sm text-neutral-500">Показывать расстояние</span>
          </div>

          <UButton
            type="submit"
            block
            size="lg"
            :loading="loading"
            label="Сохранить"
            class="mt-2"
          />
        </UForm>
      </UCard>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ApiError } from '~/utils/api-error'
import type { User } from '~/utils/types'

const auth = useAuth()
const loading = ref(false)
const error = ref('')
const saved = ref(false)
const interestsStr = ref('')

const statusOptions = [
  { label: 'Не указан', value: '' },
  { label: 'В активном поиске', value: 'active' },
  { label: 'Встречаюсь', value: 'dating' },
  { label: 'В отношениях', value: 'relationship' },
  { label: 'Женат/Замужем', value: 'married' },
  { label: 'Всё сложно', value: 'complicated' },
]

const form = reactive({
  displayName: '',
  email: '',
  bio: '',
  city: '',
  occupation: '',
  birthDate: '',
  relationshipStatus: '',
  showDistance: true,
})

onMounted(() => {
  if (auth.user) {
    form.displayName = auth.user.displayName || ''
    form.email = auth.user.email || ''
    form.bio = auth.user.bio || ''
    form.city = auth.user.city || ''
    form.occupation = auth.user.occupation || ''
    form.birthDate = auth.user.birthDate || ''
    form.relationshipStatus = auth.user.relationshipStatus || ''
    form.showDistance = auth.user.showDistance
    interestsStr.value = (auth.user.interests || []).join(', ')
  }
})

const fieldErrors = ref<Record<string, string>>({})

async function handleSave() {
  error.value = ''
  saved.value = false
  fieldErrors.value = {}

  if (!form.displayName.trim()) {
    fieldErrors.value = { displayName: 'Введите имя' }
    return
  }

  loading.value = true
  try {
    const interests = interestsStr.value
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)

    const res = await authApi().updateProfile({
      displayName: form.displayName.trim(),
      bio: form.bio.trim() || null,
      city: form.city.trim() || null,
      occupation: form.occupation.trim() || null,
      birthDate: form.birthDate || null,
      relationshipStatus: form.relationshipStatus || null,
      interests,
      showDistance: form.showDistance,
    })

    auth.user.value = res.data as User
    saved.value = true
    setTimeout(() => { saved.value = false }, 3000)
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
