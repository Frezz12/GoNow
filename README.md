# GoNow

GoNow — сервис временных офлайн-активностей на карте. Этот репозиторий содержит первый вертикальный сценарий: регистрация, вход и безопасная сессия.

## Требования

Rust/Cargo 1.95+, Docker Compose, Xcode 26.3+ и iOS 26.2+. Для локальной разработки также нужен `sqlx-cli` (`cargo install sqlx-cli --no-default-features --features rustls,postgres`).

## Первый запуск backend

```bash
cp .env.example .env
make start-infrastructure
make backend-dev
```

Миграции применяются автоматически при старте backend. Отдельно их можно применить так:

```bash
make migrate
```

Проверка:

```bash
curl http://localhost:8080/health
```

## API

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/users/me`
- `GET /api/v1/users/me/photos`
- `POST /api/v1/users/me/avatar`
- `POST /api/v1/users/me/photos`
- `GET /api/v1/users/me/photos/{photoId}/content`
- `DELETE /api/v1/users/me/photos/{photoId}`
- `GET /health`

Интерактивная документация: `http://localhost:8080/api/docs`; JSON-контракт: `http://localhost:8080/api/openapi.json`.

## Миграции

```bash
cd apps/backend
cargo sqlx migrate add <name>
cargo sqlx migrate run
cargo sqlx migrate revert
```

`make reset-development-database` требует `APP_ENV=development` и явного ввода `RESET`.

## iOS

Откройте существующий [GoNow.xcodeproj](/Users/nikolay/Documents/code/gonow/apps/ios/GoNow/GoNow.xcodeproj) в Xcode и выберите Simulator. В Debug используется `http://127.0.0.1:8080/api/v1`; ATS-разрешение на HTTP задано только для Debug. Для физического iPhone измените `GoNowAPIBaseURL` в Debug configuration на локальный IP Mac (например, `http://192.168.1.20:8080/api/v1`) и убедитесь, что телефон и Mac в одной сети. Для Release задан HTTPS URL-заглушка, который необходимо заменить на production API до публикации.

## Проверки

```bash
make backend-test
make backend-integration-test # after infrastructure and backend are running
xcodebuild -project apps/ios/GoNow/GoNow.xcodeproj -scheme GoNow -sdk iphonesimulator build
xcodebuild -project apps/ios/GoNow/GoNow.xcodeproj -scheme GoNow test
```

## Ограничения первого этапа

Карта пока демонстрационная, а активности и чат ещё не реализованы. Email подтверждается кодом, а аватар и личная галерея хранятся в приватном S3-совместимом хранилище; настройка R2 описана в [storage.md](storage.md).
