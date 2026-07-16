# Изменения — Android клиент GoNow

Дата: 2026-07-16

## Созданные файлы

### Build System
- `settings.gradle.kts` — конфигурация Gradle проекта
- `build.gradle.kts` — корневой build-файл с плагинами
- `app/build.gradle.kts` — build-файл приложения с зависимостями
- `gradle.properties` — свойства Gradle
- `gradle/wrapper/gradle-wrapper.properties` — Gradle Wrapper
- `app/proguard-rules.pro` — правила ProGuard для Retrofit и Kotlinx Serialization

### Resources
- `app/src/main/AndroidManifest.xml` — манифест приложения
- `app/src/main/res/values/strings.xml` — строки
- `app/src/main/res/values/themes.xml` — тема (NoActionBar)

### Application & Activity
- `app/src/main/java/frezzy/gonow/GoNowApp.kt` — Application class
- `app/src/main/java/frezzy/gonow/MainActivity.kt` — точка входа, маршрутизация auth/main

### Models
- `app/src/main/java/frezzy/gonow/models/ApiModels.kt` — все data-классы: запросы, ответы, ошибки, AuthPhase

### Network
- `app/src/main/java/frezzy/gonow/network/ApiService.kt` — Retrofit interface (register, login, refresh, logout, users/me)
- `app/src/main/java/frezzy/gonow/network/ApiClient.kt` — HTTP клиент с автообновлением токена на 401

### Data
- `app/src/main/java/frezzy/gonow/data/TokenStore.kt` — защищённое хранилище токенов (EncryptedSharedPreferences)
- `app/src/main/java/frezzy/gonow/data/DeviceIdentity.kt` —ERSISTENT device ID + Build.MODEL
- `app/src/main/java/frezzy/gonow/data/AuthRepository.kt` — бизнес-логика auth (register, login, restore, refresh, logout)

### UI — Theme
- `app/src/main/java/frezzy/gonow/ui/theme/Color.kt` — палитра GoNow из style.md
- `app/src/main/java/frezzy/gonow/ui/theme/Type.kt` — типографика (Roboto, sp-размеры)
- `app/src/main/java/frezzy/gonow/ui/theme/Theme.kt` — Material 3 color scheme + status bar
- `app/src/main/java/frezzy/gonow/ui/theme/Components.kt` — переиспользуемые компоненты:
  - `AuthBackdrop` — вертикальный градиент #FFDEE8 → #DBD6FA → #BADBFA
  - `GlassCard` — стеклянная карточка с радиусом 24, градиентной рамкой
  - `GradientPrimaryButton` — CTA-капсула #D41F63 → #7A38C7 с анимацией нажатия
  - `GlassSecondaryButton` — вторичная стеклянная кнопка
  - `LiquidGlassField` — поле ввода с фокусным градиентом #BA4D85 → #E66E9E → #637DF0
  - `ErrorMessage` — красная ошибка с иконкой
  - `MapPointMarker` — круглый pin маркер
  - `TaskPreviewCard` — карточка задачи

### UI — Auth
- `app/src/main/java/frezzy/gonow/ui/auth/AuthViewModel.kt` — ViewModel с валидацией и API-вызовами
- `app/src/main/java/frezzy/gonow/ui/auth/LoginScreen.kt` — экран входа
- `app/src/main/java/frezzy/gonow/ui/auth/RegisterScreen.kt` — экран регистрации
- `app/src/main/java/frezzy/gonow/ui/auth/AuthFlow.kt` — анимированный переключатель login/register

### UI — Main
- `app/src/main/java/frezzy/gonow/ui/main/MainViewModel.kt` — состояние вкладок
- `app/src/main/java/frezzy/gonow/ui/main/MainScreen.kt` — нижняя навигация + центральный FAB "Создать"
- `app/src/main/java/frezzy/gonow/ui/main/MapTab.kt` — вкладка "Карта"
- `app/src/main/java/frezzy/gonow/ui/main/TasksTab.kt` — вкладка "Задания"
- `app/src/main/java/frezzy/gonow/ui/main/ChatTab.kt` — вкладка "Чат"
- `app/src/main/java/frezzy/gonow/ui/main/ProfileTab.kt` — вкладка "Профиль" с logout
- `app/src/main/java/frezzy/gonow/ui/main/CreateTaskSheet.kt` — нижний лист создания задачи

### Documentation
- `README.md` — обновлён с инструкциями по запуску и структурой проекта

## Ключевые решения

1. **Не затронут backend** — API используется как есть, без изменений
2. **Токены хранятся в EncryptedSharedPreferences** (аналог Keychain на iOS)
3. **Устройство = "android"** — platform field в device payload
4. **Base URL для эмулятора** = `10.0.2.2:8080` (localhost через эмулятор)
5. **Нет внешних зависимостей**除了 Retrofit/OkHttp/Compose — минимум как в iOS
6. **Все тексты на русском** — как в iOS-приложении
7. **Стиль из style.md** — pastel liquid glass, градиенты, стеклянные карточки

## Исправления (сборка и запуск)

- **ApiError** наследует `Exception` вместо sealed class — исправлены catch-блоки
- **LinearGradient crash** — убран `Float.MAX_VALUE` в offset градиента
- **Иконки** — заменены недоступные `ExclamationCircle` → `Error`, `ChevronRight` → `KeyboardArrowRight`, `Walk` → `DirectionsWalk`, `Coffee` → `LocalCafe`
- **Импорты** — добавлены `Icon`, `MaterialTheme`, `graphicsLayer`, `background` в компоненты
- **Gradle** — переключён на 8.14 (кэширована), Kotlin на 2.0.21
- **Иконки launcher** — добавлены adaptive icon XML (primary pin)
