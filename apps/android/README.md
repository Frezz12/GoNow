# Android

Android клиент GoNow. Написан на Kotlin с Jetpack Compose и Material 3.

## Требования

- Android Studio Ladybug (2024.2.1) или новее
- JDK 17+
- Android SDK: API 35, Build Tools 35.0.0
- Backend GoNow запущенный на `http://10.0.2.2:8080` (localhost эмулятора)

## Структура

```
app/src/main/java/frezzy/gonow/
├── GoNowApp.kt                     # Application class
├── MainActivity.kt                 # Entry point, auth routing
├── models/                         # API data models
│   └── ApiModels.kt
├── network/                        # Retrofit API client
│   ├── ApiService.kt
│   └── ApiClient.kt
├── data/                           # Storage and repositories
│   ├── TokenStore.kt               # Encrypted token storage
│   ├── DeviceIdentity.kt           # Persistent device ID
│   └── AuthRepository.kt           # Auth business logic
└── ui/
    ├── theme/
    │   ├── Color.kt                # GoNow color palette
    │   ├── Type.kt                 # Typography
    │   ├── Theme.kt                # Material 3 theme
    │   └── Components.kt           # Glass card, gradient button, fields
    ├── auth/
    │   ├── AuthViewModel.kt        # Auth state machine
    │   ├── LoginScreen.kt          # Login form
    │   ├── RegisterScreen.kt       # Registration form
    │   └── AuthFlow.kt             # Animated auth switcher
    └── main/
        ├── MainViewModel.kt        # Tab navigation state
        ├── MainScreen.kt           # Bottom nav + tab routing
        ├── MapTab.kt               # Map placeholder
        ├── TasksTab.kt             # Tasks placeholder
        ├── ChatTab.kt              # Chat placeholder
        ├── ProfileTab.kt           # User profile + logout
        └── CreateTaskSheet.kt      # Bottom sheet for task creation
```

## Запуск

1. Убедитесь, что backend запущен: `make backend-dev` из корня проекта
2. Откройте `apps/android/` в Android Studio
3. Запустите на эмуляторе (API 35+)

Для физического устройства замените `10.0.2.2` на IP-адрес вашего компьютера в `app/build.gradle.kts`.

## Архитектура

- **MVVM**: ViewModel + StateFlow (Compose state)
- **Сеть**: Retrofit + OkHttp + Kotlinx Serialization
- **Хранение**: EncryptedSharedPreferences (Android Keystore)
- **UI**: Jetpack Compose + Material 3
- **Навигация**: Compose Navigation (bottom nav)

## Стиль

Следует гайдлайну из `style.md`: pastel liquid glass, градиенты, стеклянные карточки.
