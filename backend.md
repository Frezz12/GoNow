# Запуск backend GoNow

## Требования

- Rust и Cargo (версия не ниже 1.95);
- Docker Desktop с запущенным Docker daemon;
- Docker Compose.

`sqlx-cli` нужен только для ручного управления миграциями:

```bash
cargo install sqlx-cli --no-default-features --features rustls,postgres
```

## Первый запуск

В корне репозитория создайте локальную конфигурацию. Файл `.env` игнорируется Git и не должен содержать production-секреты в development-окружении.

```bash
cp .env.example .env
make start-infrastructure
make backend-dev
```

Если локальный порт `5432` уже занят другой PostgreSQL-базой, в `.env` используйте свободный порт и синхронно измените URL:

```env
POSTGRES_PORT=5433
DATABASE_URL=postgres://gonow:change_me@localhost:5433/gonow
```

`make backend-dev` передаёт переменные из `.env`, запускает Rust API на `http://127.0.0.1:8080` и автоматически применяет миграции.

В том же терминале backend выводит одну строку после каждого HTTP-запроса: метод, путь, query, HTTP-статус, время обработки и `request_id`. Тела запросов и ответов не логируются, чтобы не попасть в логи паролям, токенам и кодам подтверждения.

## Email-подтверждение через Resend

Для регистрации с кодом подтверждения создайте API key в Resend, подтвердите домен отправителя в панели Resend и добавьте только в локальный `.env` (не коммитить). Адрес в `RESEND_FROM_EMAIL` обязан принадлежать подтверждённому домену:

```env
RESEND_API_KEY=re_ваш_секретный_ключ
RESEND_FROM_EMAIL="GoNow <noreply@ваш-домен>"
EMAIL_CODE_TTL_SECONDS=600
```

После регистрации и при восстановлении пароля backend отправляет шестизначный одноразовый код. Без первых двух переменных или при отклонении отправителя Resend вернёт `503`, чтобы письмо не было потеряно молча. Для локальной проверки до подключения домена можно использовать `onboarding@resend.dev`, но письмо Resend отправит только на email владельца аккаунта.

Проверьте зависимости и API в отдельном терминале:

```bash
curl http://localhost:8080/health
```

Ожидаемый ответ:

```json
{
  "status": "ok",
  "services": {
    "postgres": "ok",
    "redis": "ok"
  }
}
```

OpenAPI: `http://localhost:8080/api/openapi.json`; интерактивная документация: `http://localhost:8080/api/docs`.

## Полезные команды

```bash
make stop-infrastructure
make migrate
make backend-test
make backend-integration-test
```

`backend-integration-test` запускайте после старта инфраструктуры и API. Сброс development-базы: `make reset-development-database`; команда требует `APP_ENV=development` и подтверждение `RESET`.

## Миграции

```bash
cd apps/backend
cargo sqlx migrate add <name>
cargo sqlx migrate run
cargo sqlx migrate revert
```

Не используйте development `.env` и локальные Docker volumes для production.
